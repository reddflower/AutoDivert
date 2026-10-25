@echo off
set "LOCAL_VERSION=1.1"
set "GITHUB_VERSION_URL=https://reddflower.github.io/autodivert_version.html"
set "GITHUB_DOWNLOAD_URL=https://github.com/reddflower/AutoDivert/releases/latest"
chcp 437 > nul
setlocal enableDelayedExpansion
cd /d "%~dp0"

color 0F

if exist "%~dp0autoloader.bat" set "autoloader=1"

set "ADV_DIR=%~dp0AutoDivert"
if not exist "%ADV_DIR%" md "%ADV_DIR%" >nul 2>&1

if not exist "%ADV_DIR%\daemon.ps1"     set "no-autodivert=1"
if not exist "%ADV_DIR%\run_hidden.vbs" set "no-autodivert=1"

:: AUTODIVERT MENU ===========================================================

:autodivert_menu
cls
title AutoDivert v!LOCAL_VERSION!

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting admin rights...
    powershell -NoProfile -Command "Start-Process 'cmd.exe' -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b
)

:: Read current config values for display
set "adv_interval=120"
set "adv_loglines=60"
set "adv_resort=100"
set "adv_fw=1"
if exist "%ADV_DIR%\autodivert.cfg" (
    for /f "tokens=2 delims==" %%A in ('findstr /b /c:"interval=" "%ADV_DIR%\autodivert.cfg" 2^>nul') do set "adv_interval=%%A"
    for /f "tokens=2 delims==" %%A in ('findstr /b /c:"log_max_lines=" "%ADV_DIR%\autodivert.cfg" 2^>nul') do set "adv_loglines=%%A"
    for /f "tokens=2 delims==" %%A in ('findstr /b /c:"history_resort_every=" "%ADV_DIR%\autodivert.cfg" 2^>nul') do set "adv_resort=%%A"
    for /f "tokens=2 delims==" %%A in ('findstr /b /c:"apply_firewall_rules=" "%ADV_DIR%\autodivert.cfg" 2^>nul') do set "adv_fw=%%A"
)

:: Count current firewall rules
set "adv_fw_count=0"
for /f %%A in ('powershell -NoProfile -Command "(Get-NetFirewallRule -DisplayName 'AutoDivert-Block-*' -ErrorAction SilentlyContinue | Measure-Object).Count"') do set "adv_fw_count=%%A"

:: Get the latest version
for /f "delims=" %%A in ('powershell -NoProfile -Command "(Invoke-WebRequest -Uri \"%GITHUB_VERSION_URL%\" -Headers @{\"Cache-Control\"=\"no-cache\"} -UseBasicParsing -TimeoutSec 5).Content.Trim()" 2^>nul') do set "GITHUB_VERSION=%%A"

echo.
if "%LOCAL_VERSION%"=="%GITHUB_VERSION%" (
echo      AutoDivert v!LOCAL_VERSION!
) else ( 
set "new_version=avaible"
call :PrintWhiteGreen "     AutoDivert v!LOCAL_VERSION!" " [new - %GITHUB_VERSION%]"
)
echo   ----------------------------------------
echo.
echo      1. Install ^& Start daemon
echo      2. Uninstall ^& Stop daemon
echo      3. Check status
echo.
echo      4. Open clean hosts
echo      5. Open history file
echo      6. Open config
echo      7. Open blocklist ^(IPs^)
echo      8. Open domain filter
echo.
call :PrintWhiteGreen "     9. Change interval     " "[!adv_interval!s]"
call :PrintWhiteGreen "    10. Change log max lines " "[!adv_loglines!]"
call :PrintWhiteGreen "    11. Change resort every " "[!adv_resort!]"
echo.
echo     12. Clear log now
echo     13. Firewall menu  [active: !adv_fw_count! rules, fw=!adv_fw!]
echo.
echo      0. Exit
if "%autoloader%"=="1" call :PrintWhiteGreen "     AL. " "Open AutoLoader menu"
echo.
if "%new_version%"=="avaible" call :PrintGreen "     upd. For update %GITHUB_VERSION%"
echo   ----------------------------------------
echo.

set /p adv_choice=   Select option: 

if "!adv_choice!"=="1"  goto autodivert_install
if "!adv_choice!"=="2"  goto autodivert_uninstall
if "!adv_choice!"=="3"  goto autodivert_status
if "!adv_choice!"=="4"  goto autodivert_open_clean
if "!adv_choice!"=="5"  goto autodivert_open_history
if "!adv_choice!"=="6"  goto autodivert_edit_cfg
if "!adv_choice!"=="7"  goto autodivert_edit_blocklist
if "!adv_choice!"=="8"  goto autodivert_edit_filter
if "!adv_choice!"=="9"  goto autodivert_set_interval
if "!adv_choice!"=="10" goto autodivert_set_loglines
if "!adv_choice!"=="11" goto autodivert_set_resort
if "!adv_choice!"=="12" goto autodivert_clear_log
if "!adv_choice!"=="13" goto autodivert_firewall_menu
if "!adv_choice!"=="0"  exit

if /i "!adv_choice!"=="upd"    start "" "%GITHUB_DOWNLOAD_URL%"
if /i "!adv_choice!"=="update" start "" "%GITHUB_DOWNLOAD_URL%"

if /i "!adv_choice!"=="al" (
    if "%autoloader%"=="1" (
        call autoloader.bat
    )
)

goto autodivert_menu


:: ------------------- FIREWALL SUBMENU -------------------

:autodivert_firewall_menu
cls
echo.
echo      Firewall rules
echo   ----------------------------------------
echo.

set "fw_count=0"
for /f %%A in ('powershell -NoProfile -Command "(Get-NetFirewallRule -DisplayName 'AutoDivert-Block-*' -ErrorAction SilentlyContinue | Measure-Object).Count"') do set "fw_count=%%A"

echo      Active rules:    !fw_count!
if "%adv_fw%"=="1" (
    call :PrintGreen "     Firewall mode:   ENABLED"
) else (
    call :PrintRed   "     Firewall mode:   DISABLED"
)
echo.
echo      1. Reapply rules now
echo      2. Show current rules
echo      3. Remove all rules
echo      4. Toggle firewall on/off
echo.
echo      0. Back
echo.
echo   ----------------------------------------
echo.

set /p fw_choice=   Select option: 

if "!fw_choice!"=="1" goto fw_reapply
if "!fw_choice!"=="2" goto fw_show
if "!fw_choice!"=="3" goto fw_remove
if "!fw_choice!"=="4" goto fw_toggle
if "!fw_choice!"=="0" goto autodivert_menu
goto autodivert_firewall_menu


:fw_reapply
cls
echo.
echo Reapplying firewall rules...
powershell -NoProfile -Command "Get-NetFirewallRule -DisplayName 'AutoDivert-Block-*' -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue; Write-Host 'Old rules removed. Triggering reapply via blocklist touch...'"
:: Touching blocklist file makes daemon reapply on next cycle
powershell -NoProfile -Command "(Get-Item '%ADV_DIR%\blocklist-ips.txt').LastWriteTime = Get-Date"
call :PrintGreen "Done. Daemon will reapply on next cycle (~!adv_interval!s)."
echo.
pause
goto autodivert_firewall_menu


:fw_show
cls
echo.
echo      Current AutoDivert firewall rules
echo   ----------------------------------------
echo.
powershell -NoProfile -Command "Get-NetFirewallRule -DisplayName 'AutoDivert-Block-*' -ErrorAction SilentlyContinue | Format-Table DisplayName, Direction, Action, Enabled -AutoSize"
echo.
pause
goto autodivert_firewall_menu


:fw_remove
cls
echo.
echo Removing ALL AutoDivert firewall rules...
powershell -NoProfile -Command "Get-NetFirewallRule -DisplayName 'AutoDivert-Block-*' -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue"
call :PrintGreen "All rules removed."
echo.
call :PrintYellow "Note: daemon will re-add them on next cycle if blocklist-ips.txt is not empty."
call :PrintYellow "To keep them off permanently, use option 4 to disable firewall mode."
echo.
pause
goto autodivert_firewall_menu


:fw_toggle
cls
echo.
if "%adv_fw%"=="1" (
    set "new_fw=0"
    call :PrintYellow "Disabling firewall mode..."
) else (
    set "new_fw=1"
    call :PrintGreen "Enabling firewall mode..."
)
if not exist "%ADV_DIR%\autodivert.cfg" (
    echo interval=120                 > "%ADV_DIR%\autodivert.cfg"
    echo log_max_lines=60            >> "%ADV_DIR%\autodivert.cfg"
    echo history_resort_every=100    >> "%ADV_DIR%\autodivert.cfg"
    echo apply_firewall_rules=1      >> "%ADV_DIR%\autodivert.cfg"
    echo clean_skip_system_dupes=1   >> "%ADV_DIR%\autodivert.cfg"
)
powershell -NoProfile -Command ^
    "$f='%ADV_DIR%\autodivert.cfg'; $c=Get-Content $f; if ($c -match '^apply_firewall_rules=') { $c = $c -replace '^apply_firewall_rules=.*', 'apply_firewall_rules=!new_fw!' } else { $c += 'apply_firewall_rules=!new_fw!' }; $c | Set-Content $f -Encoding ASCII"

if "%new_fw%"=="0" (
    powershell -NoProfile -Command "Get-NetFirewallRule -DisplayName 'AutoDivert-Block-*' -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue"
    call :PrintYellow "Firewall mode OFF. All rules removed."
) else (
    call :PrintGreen "Firewall mode ON. Rules will apply on next cycle."
)
echo.
call :PrintGreen "Setting updated (applies next cycle)."
echo.
pause
goto autodivert_firewall_menu


:: ------------------- INSTALL -------------------

:autodivert_install
cls

if "%no-autodivert%"=="1" (
    echo.
    call :PrintRed "daemon.ps1 or run_hidden.vbs not found"
    echo.
    pause
    goto autodivert_menu
)

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    call :PrintRed "Administrator rights required"
    echo.
    pause
    goto autodivert_menu
)

echo.
call :PrintGreen "Installing AutoDivert daemon..."
echo.

schtasks /Delete /TN "AutoDivert" /F >nul 2>&1

schtasks /Create /TN "AutoDivert" ^
    /TR "wscript.exe \"%ADV_DIR%\run_hidden.vbs\" daemon.ps1" ^
    /SC ONLOGON /RL HIGHEST /F >nul 2>&1

if !errorlevel! neq 0 (
    call :PrintRed "Failed to create scheduled task"
    echo.
    pause
    goto autodivert_menu
)

call :PrintGreen "Scheduled task created (runs at logon)"

wscript.exe "%ADV_DIR%\run_hidden.vbs" daemon.ps1
timeout /t 2 >nul

call :PrintGreen "Daemon started"
echo.
pause
goto autodivert_menu


:: ------------------- UNINSTALL -------------------

:autodivert_uninstall
cls

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    call :PrintRed "Administrator rights required"
    echo.
    pause
    goto autodivert_menu
)

echo.
echo Stopping AutoDivert daemon...
echo.

schtasks /Delete /TN "AutoDivert" /F >nul 2>&1
call :PrintGreen "Scheduled task removed"

echo stop > "%ADV_DIR%\stop.flag"
timeout /t 5 >nul
del "%ADV_DIR%\stop.flag" >nul 2>&1

powershell -NoProfile -Command "$self=$PID; Get-CimInstance Win32_Process -Filter \"Name='powershell.exe'\" | Where-Object { $_.ProcessId -ne $self -and $_.CommandLine -like '*daemon.ps1*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }" >nul 2>&1

call :PrintGreen "Daemon stopped"
echo.
call :PrintYellow "Note: firewall rules are NOT removed (they persist)."
call :PrintYellow "Use firewall menu -> option 3 to remove them manually."
echo.
pause
goto autodivert_menu


:: ------------------- SET INTERVAL -------------------

:autodivert_set_interval
cls
echo.
echo      Change interval
echo   ----------------------------------------
echo.
echo  Current: !adv_interval! seconds
echo.
call :PrintYellow " Recommended: 60 - 600 seconds."
call :PrintRed " Minimum: 10 seconds."
echo.

set /p new_interval=  Enter new interval in seconds: 

echo !new_interval!| findstr /r "^[0-9][0-9]*$" >nul
if !errorlevel! neq 0 (
    call :PrintRed "Invalid number"
    timeout /t 2 >nul
    goto autodivert_set_interval
)
if !new_interval! lss 10 (
    call :PrintRed "Minimum is 10 seconds"
    timeout /t 2 >nul
    goto autodivert_set_interval
)

if not exist "%ADV_DIR%\autodivert.cfg" (
    echo interval=120                 > "%ADV_DIR%\autodivert.cfg"
    echo log_max_lines=60            >> "%ADV_DIR%\autodivert.cfg"
    echo history_resort_every=100    >> "%ADV_DIR%\autodivert.cfg"
    echo apply_firewall_rules=1      >> "%ADV_DIR%\autodivert.cfg"
    echo clean_skip_system_dupes=1   >> "%ADV_DIR%\autodivert.cfg"
)
powershell -NoProfile -Command ^
    "$f='%ADV_DIR%\autodivert.cfg'; $c=Get-Content $f; if ($c -match '^interval=') { $c = $c -replace '^interval=.*', 'interval=!new_interval!' } else { $c += 'interval=!new_interval!' }; $c | Set-Content $f -Encoding ASCII"

call :PrintGreen "Interval updated to !new_interval!s (applies next cycle)"
echo.
pause
goto autodivert_menu


:: ------------------- SET LOG LINES -------------------

:autodivert_set_loglines
cls
echo.
echo      Change log max lines
echo   ----------------------------------------
echo.
echo  Current: !adv_loglines! lines
echo.
call :PrintYellow " Recommended: 30 - 200."
call :PrintRed " Minimum: 10."
echo.

set /p new_loglines=  Enter new max lines: 

echo !new_loglines!| findstr /r "^[0-9][0-9]*$" >nul
if !errorlevel! neq 0 (
    call :PrintRed "Invalid number"
    timeout /t 2 >nul
    goto autodivert_set_loglines
)
if !new_loglines! lss 10 (
    call :PrintRed "Minimum is 10 lines"
    timeout /t 2 >nul
    goto autodivert_set_loglines
)

if not exist "%ADV_DIR%\autodivert.cfg" (
    echo interval=120                 > "%ADV_DIR%\autodivert.cfg"
    echo log_max_lines=60            >> "%ADV_DIR%\autodivert.cfg"
    echo history_resort_every=100    >> "%ADV_DIR%\autodivert.cfg"
    echo apply_firewall_rules=1      >> "%ADV_DIR%\autodivert.cfg"
    echo clean_skip_system_dupes=1   >> "%ADV_DIR%\autodivert.cfg"
)
powershell -NoProfile -Command ^
    "$f='%ADV_DIR%\autodivert.cfg'; $c=Get-Content $f; if ($c -match '^log_max_lines=') { $c = $c -replace '^log_max_lines=.*', 'log_max_lines=!new_loglines!' } else { $c += 'log_max_lines=!new_loglines!' }; $c | Set-Content $f -Encoding ASCII"

call :PrintGreen "Log max lines updated to !new_loglines! (applies next cycle)"
echo.
pause
goto autodivert_menu


:: ------------------- SET RESORT EVERY -------------------

:autodivert_set_resort
cls
echo.
echo      Change history resort frequency
echo   ----------------------------------------
echo.
echo  Current: every !adv_resort! cycles
echo.
call :PrintYellow " How often the history file is fully rewritten"
call :PrintYellow " with deduplication and sorting."
echo.
call :PrintYellow " Recommended: 50 - 500 cycles."
call :PrintRed " Minimum: 1."
echo.

set /p new_resort=  Enter new value: 

echo !new_resort!| findstr /r "^[0-9][0-9]*$" >nul
if !errorlevel! neq 0 (
    call :PrintRed "Invalid number"
    timeout /t 2 >nul
    goto autodivert_set_resort
)
if !new_resort! lss 1 (
    call :PrintRed "Minimum is 1"
    timeout /t 2 >nul
    goto autodivert_set_resort
)

if not exist "%ADV_DIR%\autodivert.cfg" (
    echo interval=120                 > "%ADV_DIR%\autodivert.cfg"
    echo log_max_lines=60            >> "%ADV_DIR%\autodivert.cfg"
    echo history_resort_every=100    >> "%ADV_DIR%\autodivert.cfg"
    echo apply_firewall_rules=1      >> "%ADV_DIR%\autodivert.cfg"
    echo clean_skip_system_dupes=1   >> "%ADV_DIR%\autodivert.cfg"
)
powershell -NoProfile -Command ^
    "$f='%ADV_DIR%\autodivert.cfg'; $c=Get-Content $f; if ($c -match '^history_resort_every=') { $c = $c -replace '^history_resort_every=.*', 'history_resort_every=!new_resort!' } else { $c += 'history_resort_every=!new_resort!' }; $c | Set-Content $f -Encoding ASCII"

call :PrintGreen "Resort frequency updated to every !new_resort! cycles"
echo.
pause
goto autodivert_menu


:: ------------------- CLEAR LOG NOW -------------------

:autodivert_clear_log
cls
echo.
if exist "%ADV_DIR%\collector.log" (
    del /f /q "%ADV_DIR%\collector.log"
    call :PrintGreen "Log cleared"
) else (
    call :PrintYellow "Log file does not exist"
)
echo.
pause
goto autodivert_menu


:: ------------------- STATUS -------------------

:autodivert_status
cls
echo.
echo      AutoDivert status
echo   ----------------------------------------
echo.

schtasks /Query /TN "AutoDivert" >nul 2>&1
if !errorlevel! equ 0 (
    call :PrintGreen "Scheduled task:  INSTALLED"
) else (
    call :PrintRed   "Scheduled task:  NOT INSTALLED"
)

powershell -NoProfile -Command ^
    "$p = Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like '*daemon.ps1*' }; if ($p) { Write-Host 'Daemon process:  RUNNING (PID ' $p.ProcessId ')' -ForegroundColor Green } else { Write-Host 'Daemon process:  NOT RUNNING' -ForegroundColor Red }"

:: Firewall rules
set "fw_count=0"
for /f %%A in ('powershell -NoProfile -Command "(Get-NetFirewallRule -DisplayName 'AutoDivert-Block-*' -ErrorAction SilentlyContinue | Measure-Object).Count"') do set "fw_count=%%A"
echo Firewall rules:  !fw_count!

:: File sizes
if exist "%ADV_DIR%\hosts" (
    for %%A in ("%ADV_DIR%\hosts") do echo Clean hosts:     %%A ^(%%~zA bytes^)
) else (
    echo Clean hosts:     not created yet
)
if exist "%ADV_DIR%\hosts-history.txt" (
    for %%A in ("%ADV_DIR%\hosts-history.txt") do echo History file:    %%A ^(%%~zA bytes^)
) else (
    echo History file:    not created yet
)
if exist "%ADV_DIR%\state.tsv" (
    for %%A in ("%ADV_DIR%\state.tsv") do echo State file:      %%A ^(%%~zA bytes^)
) else (
    echo State file:      not created yet
)
if exist "%ADV_DIR%\collector.log" (
    for %%A in ("%ADV_DIR%\collector.log") do echo Log file:        %%A ^(%%~zA bytes^)
) else (
    echo Log file:        not created yet
)

echo.
echo   ----------------------------------------
echo  Last 10 log lines:
echo   ----------------------------------------
if exist "%ADV_DIR%\collector.log" (
    powershell -NoProfile -Command "Get-Content '%ADV_DIR%\collector.log' -Tail 10"
) else (
    echo  ^(no log yet^)
)
echo.
pause
goto autodivert_menu


:: ------------------- OPEN FILES -------------------

:autodivert_open_clean
cls
if exist "%ADV_DIR%\hosts" (
    start "" notepad "%ADV_DIR%\hosts"
) else (
    call :PrintYellow "Clean hosts not created yet"
    timeout /t 2 >nul
)
goto autodivert_menu


:autodivert_open_history
cls
if exist "%ADV_DIR%\hosts-history.txt" (
    start "" notepad "%ADV_DIR%\hosts-history.txt"
) else (
    call :PrintYellow "History file not created yet"
    timeout /t 2 >nul
)
goto autodivert_menu


:autodivert_edit_cfg
cls
if not exist "%ADV_DIR%\autodivert.cfg" (
    echo interval=120                 > "%ADV_DIR%\autodivert.cfg"
    echo log_max_lines=60            >> "%ADV_DIR%\autodivert.cfg"
    echo history_resort_every=100    >> "%ADV_DIR%\autodivert.cfg"
    echo apply_firewall_rules=1      >> "%ADV_DIR%\autodivert.cfg"
    echo clean_skip_system_dupes=1   >> "%ADV_DIR%\autodivert.cfg"
)
start "" notepad "%ADV_DIR%\autodivert.cfg"
goto autodivert_menu


:autodivert_edit_blocklist
cls
if not exist "%ADV_DIR%\blocklist-ips.txt" (
    echo # AutoDivert IP blocklist (wildcards allowed) > "%ADV_DIR%\blocklist-ips.txt"
    echo # 213.180.204.*  ^= /24,  213.180.*.*  ^= /16,  213.*.*.*  ^= /8 >> "%ADV_DIR%\blocklist-ips.txt"
)
start "" notepad "%ADV_DIR%\blocklist-ips.txt"
goto autodivert_menu


:autodivert_edit_filter
cls
if not exist "%ADV_DIR%\filter-domains.txt" (
    echo # AutoDivert domain filter - affects CLEAN hosts only > "%ADV_DIR%\filter-domains.txt"
    echo # Patterns: *.example.com, ads.*, exact.domain >> "%ADV_DIR%\filter-domains.txt"
)
start "" notepad "%ADV_DIR%\filter-domains.txt"
goto autodivert_menu


:: COLORA ============================================

:PrintGreen
powershell -NoProfile -Command "Write-Host \"%~1\" -ForegroundColor Green"
exit /b

:PrintRed
powershell -NoProfile -Command "Write-Host \"%~1\" -ForegroundColor Red"
exit /b

:PrintYellow
powershell -NoProfile -Command "Write-Host \"%~1\" -ForegroundColor Yellow"
exit /b

:PrintWhiteGreen
powershell -NoProfile -Command "Write-Host '%~1' -ForegroundColor White -NoNewline; Write-Host '%~2' -ForegroundColor Green"
exit /b

:PrintWhiteRed
powershell -NoProfile -Command "Write-Host '%~1' -ForegroundColor White -NoNewline; Write-Host '%~2' -ForegroundColor Red"
exit /b

:PrintWhiteYellow
powershell -NoProfile -Command "Write-Host '%~1' -ForegroundColor White -NoNewline; Write-Host '%~2' -ForegroundColor Yellow"
exit /b