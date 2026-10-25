# ============================================================
#  daemon.ps1 v3.1 — AutoDivert resident collector
#  - Two output files: hosts-history.txt (append-only log) + hosts (clean)
#  - IP blocklist via Windows Firewall (wildcard -> CIDR)
#  - Domain filter for CLEAN file only (filter-domains.txt)
#  - State persisted in state.tsv (domain -> newest IP + timestamp)
#  - History resort every N cycles
#  v3.1: fixed double firewall apply; added domain filter
# ============================================================

$ErrorActionPreference = "SilentlyContinue"

# --- Single instance ---
$mutexName = "Local\AutoDivertDaemon"
$mutex = New-Object System.Threading.Mutex($false, $mutexName)
if (-not $mutex.WaitOne(0)) { exit }

# --- Paths ---
$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) { $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $ScriptDir) { $ScriptDir = (Get-Location).Path }

$HistoryFile = Join-Path $ScriptDir "hosts-history.txt"
$CleanFile   = Join-Path $ScriptDir "hosts"
$LogFile     = Join-Path $ScriptDir "collector.log"
$StopFlag    = Join-Path $ScriptDir "stop.flag"
$CfgFile     = Join-Path $ScriptDir "autodivert.cfg"
$BlockFile   = Join-Path $ScriptDir "blocklist-ips.txt"
$FilterFile  = Join-Path $ScriptDir "filter-domains.txt"
$StateFile   = Join-Path $ScriptDir "state.tsv"
$SystemHosts = Join-Path $env:SystemRoot "System32\drivers\etc\hosts"

# --- Defaults ---
$IntervalSeconds      = 120
$LogMaxLines          = 60
$HistoryResortEvery   = 100
$ApplyFirewallRules   = 1
$CleanSkipSystemDupes = 1

# --- Config ---
function Load-Config {
    if (Test-Path $script:CfgFile) {
        Get-Content $script:CfgFile | ForEach-Object {
            $l = $_.Trim()
            if ($l -match '^\s*interval\s*=\s*(\d+)')               { $script:IntervalSeconds = [int]$matches[1] }
            if ($l -match '^\s*log_max_lines\s*=\s*(\d+)')          { $script:LogMaxLines = [int]$matches[1] }
            if ($l -match '^\s*history_resort_every\s*=\s*(\d+)')   { $script:HistoryResortEvery = [int]$matches[1] }
            if ($l -match '^\s*apply_firewall_rules\s*=\s*(\d)')    { $script:ApplyFirewallRules = [int]$matches[1] }
            if ($l -match '^\s*clean_skip_system_dupes\s*=\s*(\d)') { $script:CleanSkipSystemDupes = [int]$matches[1] }
        }
    } else {
        @(
            "interval=$($script:IntervalSeconds)",
            "log_max_lines=$($script:LogMaxLines)",
            "history_resort_every=$($script:HistoryResortEvery)",
            "apply_firewall_rules=$($script:ApplyFirewallRules)",
            "clean_skip_system_dupes=$($script:CleanSkipSystemDupes)"
        ) | Set-Content $script:CfgFile -Encoding ASCII
    }
    if ($script:IntervalSeconds    -lt 10) { $script:IntervalSeconds = 10 }
    if ($script:LogMaxLines        -lt 10) { $script:LogMaxLines = 10 }
    if ($script:HistoryResortEvery -lt 1)  { $script:HistoryResortEvery = 1 }
}

# --- Logging ---
function Log($msg) {
    Add-Content -Path $script:LogFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $msg" -ErrorAction SilentlyContinue
    try {
        $lines = @(Get-Content $script:LogFile -ErrorAction SilentlyContinue)
        if ($lines.Count -gt $script:LogMaxLines) {
            $start = $lines.Count - $script:LogMaxLines
            $lines[$start..($lines.Count - 1)] | Set-Content $script:LogFile -Encoding ASCII
        }
    } catch { }
}

# --- Reverse DNS with timeout ---
function Get-ReverseDnsWithTimeout {
    param([string]$IP, [int]$TimeoutMs = 400)
    try {
        $task = [System.Net.Dns]::BeginGetHostEntry($IP, $null, $null)
        if ($task.AsyncWaitHandle.WaitOne($TimeoutMs)) {
            $r = [System.Net.Dns]::EndGetHostEntry($task)
            if ($r -and $r.HostName) { return $r.HostName }
        }
    } catch { }
    return $null
}

# --- Wildcard -> CIDR (for firewall) ---
function ConvertTo-Cidr {
    param([string]$Pattern)
    $p = $Pattern.Trim()
    if ($p -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') { return "$p/32" }
    if ($p -match '^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.\*$') { return "$($matches[1]).$($matches[2]).$($matches[3]).0/24" }
    if ($p -match '^(\d{1,3})\.(\d{1,3})\.\*\.\*$')        { return "$($matches[1]).$($matches[2]).0.0/16" }
    if ($p -match '^(\d{1,3})\.\*\.\*\.\*$')               { return "$($matches[1]).0.0.0/8" }
    return $null
}

# --- Firewall ---
function Apply-FirewallRules {
    if ($script:ApplyFirewallRules -ne 1) {
        Log "firewall: disabled (apply_firewall_rules=0)"
        return
    }

    Get-NetFirewallRule -DisplayName "AutoDivert-Block-*" -ErrorAction SilentlyContinue |
        Remove-NetFirewallRule -ErrorAction SilentlyContinue

    if (-not (Test-Path $script:BlockFile)) { return }

    $count = 0
    Get-Content $script:BlockFile -ErrorAction SilentlyContinue | ForEach-Object {
        $line = $_.Trim()
        if (-not $line)            { return }
        if ($line.StartsWith('#')) { return }
        $cidr = ConvertTo-Cidr $line
        if (-not $cidr) {
            Log "firewall: invalid pattern '$line'"
            return
        }
        $name = "AutoDivert-Block-$cidr"
        try {
            New-NetFirewallRule -DisplayName $name -Direction Outbound `
                -RemoteAddress $cidr -Action Block -ErrorAction Stop | Out-Null
            $count++
        } catch {
            Log "firewall: failed $cidr : $_"
        }
    }
    Log "firewall: $count rules applied"
}

# --- Domain filter for clean file ---
function Load-DomainFilter {
    $patterns = New-Object System.Collections.Generic.List[string]
    if (Test-Path $script:FilterFile) {
        Get-Content $script:FilterFile -ErrorAction SilentlyContinue | ForEach-Object {
            $l = $_.Trim()
            if ($l -and -not $l.StartsWith('#')) { $patterns.Add($l) }
        }
    }
    return $patterns
}

function Test-DomainFiltered {
    param([string]$Domain)
    foreach ($p in $script:filterPatterns) {
        if ($p.StartsWith('*.')) {
            $suffix = $p.Substring(2)
            if ($Domain -eq $suffix -or $Domain.EndsWith(".$suffix")) { return $true }
        } elseif ($p.Contains('*')) {
            $re = '^' + ($p -replace '\.', '\.' -replace '\*', '.*') + '$'
            if ($Domain -match $re) { return $true }
        } else {
            if ($Domain -eq $p) { return $true }
        }
    }
    return $false
}

# --- State persistence ---
function Load-State {
    $s = @{}
    if (Test-Path $script:StateFile) {
        Get-Content $script:StateFile -ErrorAction SilentlyContinue | ForEach-Object {
            $parts = $_ -split "`t"
            if ($parts.Count -ge 3) {
                $s[$parts[0]] = @{ IP = $parts[1]; LastSeen = [long]$parts[2] }
            }
        }
    }
    return $s
}

function Save-State {
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($domain in $script:domainState.Keys) {
        $e = $script:domainState[$domain]
        $out.Add("$domain`t$($e.IP)`t$($e.LastSeen)")
    }
    $out | Set-Content $script:StateFile -Encoding ASCII
}

# --- One collect cycle ---
function Invoke-Collect {
    # 1. DNS cache
    $dnsCache = @{}
    Get-DnsClientCache -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Data -and $_.Entry) {
            if (-not $dnsCache.ContainsKey($_.Data)) {
                $dnsCache[$_.Data] = New-Object System.Collections.Generic.HashSet[string]
            }
            [void]$dnsCache[$_.Data].Add($_.Entry)
        }
    }

    # 2. IPs from TCP + UDP, exclude local
    $ips = @{}
    Get-NetTCPConnection -ErrorAction SilentlyContinue | Where-Object {
        $_.RemoteAddress -and
        $_.RemoteAddress -ne '0.0.0.0' -and
        $_.RemoteAddress -ne '::' -and
        $_.RemoteAddress -notmatch '^(127\.|::1|169\.254\.|198\.18\.|fe80:|fd[0-9a-f]{2}:|fc[0-9a-f]{2}:)'
    } | ForEach-Object { $ips[$_.RemoteAddress] = $true }

    Get-NetUDPEndpoint -ErrorAction SilentlyContinue | Where-Object {
        $_.RemoteAddress -and
        $_.RemoteAddress -ne '0.0.0.0' -and
        $_.RemoteAddress -ne '::' -and
        $_.RemoteAddress -notmatch '^(127\.|169\.254\.|198\.18\.|fe80:|fd[0-9a-f]{2}:|fc[0-9a-f]{2}:)'
    } | ForEach-Object { $ips[$_.RemoteAddress] = $true }

    # 3. Resolve domains
    $pairs = New-Object System.Collections.Generic.List[object]
    foreach ($ip in $ips.Keys) {
        $domains = @()
        if ($dnsCache.ContainsKey($ip)) { $domains = @($dnsCache[$ip]) }
        if ($domains.Count -eq 0) {
            $rev = Get-ReverseDnsWithTimeout -IP $ip -TimeoutMs 400
            if ($rev) { $domains = @($rev) }
        }
        foreach ($d in $domains) {
            if (-not $d) { continue }
            if ($d -match '^N/A') { continue }
            if ($d -match '\.lan$' -or $d -match '\.local$' -or $d -eq 'localhost') { continue }
            $pairs.Add([PSCustomObject]@{ IP = $ip; Domain = $d })
        }
    }

    # 4. Append NEW lines to history
    $newHistory = 0
    foreach ($p in $pairs) {
        $line = "$($p.IP)`t$($p.Domain)"
        if (-not $script:historySeen.Contains($line)) {
            [void]$script:historySeen.Add($line)
            Add-Content -Path $script:HistoryFile -Value $line -Encoding ASCII -ErrorAction SilentlyContinue
            $newHistory++
        }
    }

    # 5. Update domain state (newest wins)
    $now = [int][double]::Parse((Get-Date -UFormat %s))
    foreach ($p in $pairs) {
        $script:domainState[$p.Domain] = @{ IP = $p.IP; LastSeen = $now }
    }

    # 6. Periodic history resort
    $script:cycleCount++
    if ($script:cycleCount % $script:HistoryResortEvery -eq 0) {
        $sorted = Get-Content $script:HistoryFile -ErrorAction SilentlyContinue | Sort-Object -Unique
        $sorted | Set-Content $script:HistoryFile -Encoding ASCII
    }

    # 7. Clean hosts file
    # 7a. System hosts domains
    $sysDomains = New-Object System.Collections.Generic.HashSet[string]
    if ($script:CleanSkipSystemDupes -eq 1 -and (Test-Path $script:SystemHosts)) {
        Get-Content $script:SystemHosts -ErrorAction SilentlyContinue | ForEach-Object {
            $l = $_.Trim()
            if ($l -and -not $l.StartsWith('#')) {
                $parts = $l -split '\s+'
                if ($parts.Count -ge 2) { [void]$sysDomains.Add($parts[1]) }
            }
        }
    }

    # 7b. Blocked IP patterns
    $blockRe = @()
    if (Test-Path $script:BlockFile) {
        Get-Content $script:BlockFile -ErrorAction SilentlyContinue | ForEach-Object {
            $l = $_.Trim()
            if ($l -and -not $l.StartsWith('#')) {
                $re = '^' + ($l -replace '\.', '\.' -replace '\*', '\d+') + '$'
                $blockRe += $re
            }
        }
    }

    # 7c. Compose clean file
    $cleanLines = New-Object System.Collections.Generic.List[string]
    foreach ($domain in $script:domainState.Keys) {
        $ip = $script:domainState[$domain].IP
        if ($sysDomains.Contains($domain))          { continue }
        if (Test-DomainFiltered -Domain $domain)    { continue }
        $blocked = $false
        foreach ($re in $blockRe) { if ($ip -match $re) { $blocked = $true; break } }
        if ($blocked) { continue }
        $cleanLines.Add("$ip`t$domain")
    }
    $cleanLines | Sort-Object | Set-Content $script:CleanFile -Encoding ASCII

    Log "cycle=$($script:cycleCount) new=$newHistory hist=$($script:historySeen.Count) clean=$($cleanLines.Count)"
}

# --- File watchers ---
$script:lastBlockMtime  = $null
$script:lastCfgMtime    = $null
$script:lastFilterMtime = $null

function Check-FirewallRefresh {
    $refresh = $false
    if (Test-Path $script:BlockFile) {
        $mt = (Get-Item $script:BlockFile).LastWriteTime
        if ($script:lastBlockMtime -eq $null -or $mt -ne $script:lastBlockMtime) {
            $script:lastBlockMtime = $mt
            $refresh = $true
        }
    }
    if (Test-Path $script:CfgFile) {
        $mt = (Get-Item $script:CfgFile).LastWriteTime
        if ($script:lastCfgMtime -eq $null -or $mt -ne $script:lastCfgMtime) {
            $script:lastCfgMtime = $mt
            $refresh = $true
        }
    }
    if ($refresh) { Apply-FirewallRules }
}

function Check-FilterRefresh {
    if (Test-Path $script:FilterFile) {
        $mt = (Get-Item $script:FilterFile).LastWriteTime
        if ($script:lastFilterMtime -eq $null -or $mt -ne $script:lastFilterMtime) {
            $script:lastFilterMtime = $mt
            $script:filterPatterns  = Load-DomainFilter
            Log "filter-domains loaded: $($script:filterPatterns.Count) patterns"
        }
    }
}

# ============================================================
#  MAIN
# ============================================================
Load-Config

$script:historySeen = New-Object System.Collections.Generic.HashSet[string]
if (Test-Path $HistoryFile) {
    Get-Content $HistoryFile -ErrorAction SilentlyContinue |
        Where-Object { $_ } | ForEach-Object { [void]$script:historySeen.Add($_.Trim()) }
}

$script:domainState = Load-State
$script:cycleCount  = 0

# Ensure blocklist file exists
if (-not (Test-Path $BlockFile)) {
    @(
        "# AutoDivert IP blocklist (wildcards allowed)",
        "# Examples:",
        "#   213.180.204.15    exact IP",
        "#   213.180.204.*     /24 subnet",
        "#   213.180.*.*       /16 subnet",
        "#   213.*.*.*         /8  subnet",
        "# Applied via Windows Firewall (Outbound, Block).",
        "# Set apply_firewall_rules=0 in autodivert.cfg to disable."
    ) | Set-Content $BlockFile -Encoding ASCII
}

# Ensure domain filter file exists
if (-not (Test-Path $FilterFile)) {
    @(
        "# AutoDivert domain filter",
        "# Applies to CLEAN hosts file only. History keeps everything.",
        "# Patterns: *.example.com (suffix), ads.* (prefix), exact.domain",
        "",
        "*.1e100.net",
        "*.akamaitechnologies.com",
        "*.deploy.static.akamaitechnologies.com",
        "*.r.cloudfront.net",
        "*.compute.amazonaws.com",
        "*.compute.hwclouds-dns.com",
        "*.rascom.as20764.net",
        "*.serverdedicati.aruba.it",
        "*.broadband.corbina.ru",
        "*.novotelecom.ru",
        "*.sibset.net",
        "*.2day.kz",
        "*.lencr.org",
        "*.digicert.com",
        "*.globalsign.com"
    ) | Set-Content $FilterFile -Encoding ASCII
}

# Initial firewall apply — handled by Check-FirewallRefresh (no double call!)
Check-FirewallRefresh | Out-Null
Check-FilterRefresh   | Out-Null

Log "daemon v3.1 started (interval=${IntervalSeconds}s, resort_every=${HistoryResortEvery})"

while (-not (Test-Path $StopFlag)) {
    try { Invoke-Collect }         catch { Log "ERROR collect: $_" }
    try { Save-State }             catch { Log "ERROR state: $_" }
    try { Check-FirewallRefresh }  catch { }
    try { Check-FilterRefresh }    catch { }

    $waited = 0
    while ($waited -lt $IntervalSeconds -and -not (Test-Path $StopFlag)) {
        Start-Sleep -Seconds 1
        $waited++
    }
    Load-Config
}

Log "daemon stopped"
Remove-Item $StopFlag -ErrorAction SilentlyContinue
try { $mutex.ReleaseMutex() } catch { }