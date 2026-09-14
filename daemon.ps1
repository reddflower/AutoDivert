# ============================================================
#  daemon.ps1 — AutoDivert resident collector
#  Reads settings from autodivert.cfg (interval, log_max_lines).
#  Reloads config every cycle, so no restart needed after change.
# ============================================================

$ErrorActionPreference = "SilentlyContinue"

# --- Single instance (mutex) ---
$mutexName = "Local\AutoDivertDaemon"
$mutex = New-Object System.Threading.Mutex($false, $mutexName)
if (-not $mutex.WaitOne(0)) { exit }

# --- Paths ---
$ScriptDir = $PSScriptRoot
if ([string]::IsNullOrEmpty($ScriptDir)) {
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
}
if ([string]::IsNullOrEmpty($ScriptDir)) {
    $ScriptDir = (Get-Location).Path
}
$OutputFile = Join-Path $ScriptDir "hosts.txt"
$LogFile    = Join-Path $ScriptDir "collector.log"
$StopFlag   = Join-Path $ScriptDir "stop.flag"
$CfgFile    = Join-Path $ScriptDir "autodivert.cfg"

# --- Defaults ---
$IntervalSeconds = 120
$LogMaxLines     = 60

# --- Load / create config ---
function Load-Config {
    if (Test-Path $script:CfgFile) {
        Get-Content $script:CfgFile -ErrorAction SilentlyContinue | ForEach-Object {
            $line = $_.Trim()
            if ($line -match '^\s*interval\s*=\s*(\d+)')      { $script:IntervalSeconds = [int]$matches[1] }
            if ($line -match '^\s*log_max_lines\s*=\s*(\d+)') { $script:LogMaxLines     = [int]$matches[1] }
        }
    } else {
        "interval=$($script:IntervalSeconds)"  | Set-Content $script:CfgFile -Encoding ASCII
        "log_max_lines=$($script:LogMaxLines)" | Add-Content $script:CfgFile -Encoding ASCII
    }
    if ($script:IntervalSeconds -lt 10)  { $script:IntervalSeconds = 10 }
    if ($script:LogMaxLines     -lt 10)  { $script:LogMaxLines     = 10 }
}

# --- Log with auto-trim ---
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
            $result = [System.Net.Dns]::EndGetHostEntry($task)
            if ($result -and $result.HostName) { return $result.HostName }
        }
    } catch { }
    return $null
}

# --- One collect pass ---
function Invoke-Collect {
    $dnsCache = @{}
    Get-DnsClientCache -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Data -and $_.Entry) {
            if (-not $dnsCache.ContainsKey($_.Data)) {
                $dnsCache[$_.Data] = New-Object System.Collections.Generic.HashSet[string]
            }
            [void]$dnsCache[$_.Data].Add($_.Entry)
        }
    }

    $ips = @{}
    Get-NetTCPConnection -ErrorAction SilentlyContinue | Where-Object {
        $_.RemoteAddress -and
        $_.RemoteAddress -ne '0.0.0.0' -and
        $_.RemoteAddress -ne '::' -and
        $_.RemoteAddress -notmatch '^(127\.|::1|169\.254\.|198\.18\.|fe80:)'
    } | ForEach-Object { $ips[$_.RemoteAddress] = $true }

    Get-NetUDPEndpoint -ErrorAction SilentlyContinue | Where-Object {
        $_.RemoteAddress -and
        $_.RemoteAddress -ne '0.0.0.0' -and
        $_.RemoteAddress -ne '::' -and
        $_.RemoteAddress -notmatch '^(127\.|169\.254\.|198\.18\.|fe80:)'
    } | ForEach-Object { $ips[$_.RemoteAddress] = $true }

    $newEntries = New-Object System.Collections.Generic.HashSet[string]
    foreach ($ip in $ips.Keys) {
        $domains = @()
        if ($dnsCache.ContainsKey($ip)) { $domains = @($dnsCache[$ip]) }
        if ($domains.Count -eq 0) {
            $rev = Get-ReverseDnsWithTimeout -IP $ip -TimeoutMs 400
            if ($rev) { $domains = @($rev) }
        }
        if ($domains.Count -eq 0) { continue }
        foreach ($d in $domains) {
            if ($d -match '^N/A') { continue }
            [void]$newEntries.Add("$ip`t$d")
        }
    }

    $existing = @()
    if (Test-Path $OutputFile) {
        $existing = @(Get-Content $OutputFile -ErrorAction SilentlyContinue |
                      Where-Object { $_ -and $_ -notmatch '^#' })
    }
    $all = New-Object System.Collections.Generic.HashSet[string]
    foreach ($line in $existing)   { [void]$all.Add($line.Trim()) }
    foreach ($line in $newEntries) { [void]$all.Add($line) }

    $all | Sort-Object | Set-Content -Path $OutputFile -Encoding ASCII
    Log "collected=$($newEntries.Count) total=$($all.Count)"
}

# --- Main loop ---
Load-Config
Log "daemon started (interval=${IntervalSeconds}s, log_max=${LogMaxLines})"

while (-not (Test-Path $StopFlag)) {
    try { Invoke-Collect } catch { }

    # Sleep in 1-sec chunks: react to stop flag within a second
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