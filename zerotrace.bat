@echo off
setlocal EnableExtensions
title Zero Trace
mode con cols=100 lines=40
cd /d "%~dp0"

rem ===================================================================
rem  Zero Trace launcher stub.
rem  This file only downloads the latest core (core.bat + core.ps1) from
rem  the repo and runs it. If you are offline it runs the cached copy.
rem ===================================================================
set "BASE=https://raw.githubusercontent.com/0x1617/zerotrace-rbx/main"
set "ROOT=%LOCALAPPDATA%\ZeroTrace"
set "CORE=%ROOT%\core"
if not exist "%CORE%" md "%CORE%" >nul 2>&1

echo.
echo   Loading...
call :get core/core.bat core.bat 1
call :get core/core.ps1 core.ps1 0

if not exist "%CORE%\core.bat" (
    echo.
    echo   Could not download the core and there is no cached copy.
    echo   Check your internet connection and try again.
    pause >nul
    exit /b 1
)
if not exist "%CORE%\core.ps1" (
    echo.
    echo   core.ps1 is missing. Check your internet connection and try again.
    pause >nul
    exit /b 1
)
call "%CORE%\core.bat"
exit /b 0

rem :get <remote path> <local name> <1 = batch file>
:get
set "tmp=%CORE%\%~2.new"
del "%tmp%" >nul 2>&1
set "url=%BASE%/%~1?r=%random%%random%"
where curl >nul 2>&1
if not errorlevel 1 (
    curl -fsSL --max-time 20 -o "%tmp%" "%url%" >nul 2>&1
) else (
    powershell -NoProfile -Command "try{(New-Object Net.WebClient).DownloadFile('%url%','%tmp%')}catch{}" >nul 2>&1
)
if not exist "%tmp%" exit /b 1
for %%F in ("%tmp%") do if %%~zF LSS 200 (
    del "%tmp%" >nul 2>&1
    exit /b 1
)
if not "%~3"=="1" (
    move /y "%tmp%" "%CORE%\%~2" >nul
    exit /b 0
)
rem batch files must have CRLF line endings; this also rewrites LF-only files
find /v "" <"%tmp%" >"%tmp%.crlf"
del "%tmp%" >nul 2>&1
set "first="
set /p first=<"%tmp%.crlf"
if not "%first%"=="@echo off" (
    del "%tmp%.crlf" >nul 2>&1
    exit /b 1
)
move /y "%tmp%.crlf" "%CORE%\%~2" >nul
exit /b 0
