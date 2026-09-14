@echo off
set "LOCAL_VERSION=1.0"
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

:: Request UAC if not admin yet (verified by net session, not by argument)
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting admin rights...
    powershell -NoProfile -Command "Start-Process 'cmd.exe' -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b
)

set "adv_interval=120"
set "adv_loglines=60"
if exist "%ADV_DIR%\autodivert.cfg" (
    for /f "tokens=2 delims==" %%A in ('findstr /b /c:"interval=" "%ADV_DIR%\autodivert.cfg" 2^>nul') do set "adv_interval=%%A"
    for /f "tokens=2 delims==" %%A in ('findstr /b /c:"log_max_lines=" "%ADV_DIR%\autodivert.cfg" 2^>nul') do set "adv_loglines=%%A"
)


:: Get the latest version from GitHub
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
echo      4. Open hosts.txt
echo      5. Open config in Notepad
echo.
call :PrintWhiteGreen "     6. Change interval     " "[!adv_interval!s]"
call :PrintWhiteGreen "     7. Change log max lines " "[!adv_loglines!]"
echo.
echo      8. Clear log now
echo.
echo      0. Exit
if "%autoloader%"=="1" call :PrintWhiteGreen "     AL. " "Open AutoLoader menu"
echo.
if "%new_version%"=="avaible" call :PrintGreen "     upd. For update %GITHUB_VERSION%"
echo   ----------------------------------------
echo.

set /p adv_choice=   Select option: 

if "!adv_choice!"=="1" goto autodivert_install
if "!adv_choice!"=="2" goto autodivert_uninstall
if "!adv_choice!"=="3" goto autodivert_status
if "!adv_choice!"=="4" goto autodivert_open_hosts
if "!adv_choice!"=="5" goto autodivert_edit_cfg
if "!adv_choice!"=="6" goto autodivert_set_interval
if "!adv_choice!"=="7" goto autodivert_set_loglines
if "!adv_choice!"=="8" goto autodivert_clear_log
if "!adv_choice!"=="0" exit

if /i "!adv_choice!"=="upd" start "" "%GITHUB_DOWNLOAD_URL%"
if /i "!adv_choice!"=="update" start "" "%GITHUB_DOWNLOAD_URL%"

if /i "!adv_choice!"=="al" (
    if "%autoloader%"=="1" (
        call autoloader.bat
    )
)

goto autodivert_menu


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
    call :PrintYellow "Please run AutoLoader as Administrator"
    echo.
    pause
    goto autodivert_menu
)

echo.
call :PrintGreen "Installing AutoDivert daemon..."
echo.

:: Delete old task if any
schtasks /Delete /TN "AutoDivert" /F >nul 2>&1

:: Create new task
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

:: Start daemon right now
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

:: Delete scheduled task
schtasks /Delete /TN "AutoDivert" /F >nul 2>&1
call :PrintGreen "Scheduled task removed"

:: Graceful stop via flag
echo stop > "%ADV_DIR%\stop.flag"
timeout /t 5 >nul
del "%ADV_DIR%\stop.flag" >nul 2>&1

:: Kill any leftover daemon processes (exclude self)
powershell -NoProfile -Command "$self=$PID; Get-CimInstance Win32_Process -Filter \"Name='powershell.exe'\" | Where-Object { $_.ProcessId -ne $self -and $_.CommandLine -like '*daemon.ps1*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }" >nul 2>&1

call :PrintGreen "Daemon stopped"
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

:: Validate numeric
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

:: Write to cfg (preserve other values)
if not exist "%ADV_DIR%\autodivert.cfg" (
    echo interval=120        > "%ADV_DIR%\autodivert.cfg"
    echo log_max_lines=60   >> "%ADV_DIR%\autodivert.cfg"
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
call :PrintYellow " The collector.log will keep only the last N lines."
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
    echo interval=120       > "%ADV_DIR%\autodivert.cfg"
    echo log_max_lines=60  >> "%ADV_DIR%\autodivert.cfg"
)
powershell -NoProfile -Command ^
    "$f='%ADV_DIR%\autodivert.cfg'; $c=Get-Content $f; if ($c -match '^log_max_lines=') { $c = $c -replace '^log_max_lines=.*', 'log_max_lines=!new_loglines!' } else { $c += 'log_max_lines=!new_loglines!' }; $c | Set-Content $f -Encoding ASCII"

call :PrintGreen "Log max lines updated to !new_loglines! (applies next cycle)"
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

:: Scheduled task
schtasks /Query /TN "AutoDivert" >nul 2>&1
if !errorlevel! equ 0 (
    call :PrintGreen "Scheduled task:  INSTALLED"
) else (
    call :PrintRed   "Scheduled task:  NOT INSTALLED"
)

:: Running process
powershell -NoProfile -Command ^
    "$p = Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like '*daemon.ps1*' }; if ($p) { Write-Host 'Daemon process:  RUNNING (PID ' $p.ProcessId ')' -ForegroundColor Green } else { Write-Host 'Daemon process:  NOT RUNNING' -ForegroundColor Red }"

:: File sizes
if exist "%ADV_DIR%\hosts.txt" (
    for %%A in ("%ADV_DIR%\hosts.txt") do echo Hosts file:      %%A ^(%%~zA bytes^)
) else (
    echo Hosts file:      not created yet
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


:: ------------------- OPEN HOSTS -------------------

:autodivert_open_hosts
cls

if exist "%ADV_DIR%\hosts.txt" (
    start "" notepad "%ADV_DIR%\hosts.txt"
) else (
    call :PrintYellow "hosts.txt not created yet"
    timeout /t 2 >nul
)
goto autodivert_menu


:: ------------------- OPEN CONFIG -------------------

:autodivert_edit_cfg
cls

if not exist "%ADV_DIR%\autodivert.cfg" (
    echo interval=120       > "%ADV_DIR%\autodivert.cfg"
    echo log_max_lines=60  >> "%ADV_DIR%\autodivert.cfg"
)
start "" notepad "%ADV_DIR%\autodivert.cfg"
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