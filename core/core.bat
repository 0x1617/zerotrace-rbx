@echo off
setlocal EnableExtensions EnableDelayedExpansion
rem Zero Trace core. Downloaded from the repo by zerotrace.bat on every launch.

rem ===================== CONFIG =====================
rem Public repo the games/macros are fetched from on every launch.
set "BASE=https://raw.githubusercontent.com/0x1617/zerotrace-rbx/main"
rem Local data (encrypted macros, your keybinds, runtime files)
set "ROOT=%LOCALAPPDATA%\ZeroTrace"
set "CORE=%ROOT%\core"
set "STORE=%ROOT%\store"
set "CFG=%ROOT%\config.ini"
set "RUNDIR=%ROOT%\run"
set "ART=%ROOT%\art.txt"
rem ==================================================

if not exist "%RUNDIR%" md "%RUNDIR%" >nul 2>&1

rem --- get an ESC character for ANSI colours / cursor control ---
for /f "delims=#" %%E in ('"prompt #$E# & echo on & for %%b in (1) do rem"') do set "ESC=%%E"
set "w=%ESC%[97m"
set "g=%ESC%[37m"
set "r=%ESC%[91m"
set "d=%ESC%[31m"
set "gr=%ESC%[92m"
set "dim=%ESC%[90m"
set "n=%ESC%[0m"

rem --- clean leftovers from a previous session ---
call :stopall
for /d %%D in ("%TEMP%\zt_*") do rd /s /q "%%D" >nul 2>&1

rem --- pre-render the art to a file so it is drawn in one write (no flashing) ---
call :art >"%ART%"

rem ===================== SPLASH =====================
cls
<nul set /p "=%ESC%[?25l"
type "%ART%"
call :dosync "Initialising"
if "!rc!"=="1" (
    echo   %dim%offline or repo unreachable - using cached macros%n%
    call :wait 400
    echo.
)
if "!rc!"=="2" (
    echo   %dim%no games published in the repo yet%n%
    call :wait 400
    echo.
)

rem --- build the game list from what is in the store ---
set /a gcount=0
for /d %%D in ("%STORE%\*") do (
    set /a gcount+=1
    set "game!gcount!=%%~nxD"
)
if !gcount!==0 (
    set "gcount=1"
    set "game1=Baddies"
)
goto gamelist_first

rem ===================== GAME LIST =====================
:gamelist_back
cls
type "%ART%"
echo.
:gamelist_first
call :gamelist

:gamepick
<nul set /p "=%ESC%[?25h"
set "pick="
set /p "pick=  %r%>%n% "
if not defined pick goto gamepick
if "!pick!"=="0" goto quit
for /l %%i in (1,1,!gcount!) do (
    if /i "!pick!"=="%%i" set "sel=%%i"
    if /i "!pick!"=="!game%%i!" set "sel=%%i"
)
if not defined sel (
    echo   %d%Invalid choice.%n%
    goto gamepick
)
set "gsel=!sel!"
set "sel="
goto macrolist

rem ===================== MACRO LIST =====================
:macrolist
set "game=!game%gsel%!"
set "sdir=%STORE%\!game!"
cls
type "%ART%"
echo.
echo   %dim%game:%n% %w%!game!%n%
echo.

rem --- scan macros (name shown without file type) ---
set /a mc=0
for %%F in ("!sdir!\*.zt") do (
    set /a mc+=1
    set "mf!mc!=%%~fF"
    set "mk!mc!="
    set "mo!mc!="
    if exist "%%~fF.meta" set /p "mk!mc!=" <"%%~fF.meta"
    if exist "%%~fF.opts" set "mo!mc!=1"
    for %%G in ("%%~nF") do (
        set "mn!mc!=%%~nG"
        set "mx!mc!=%%~xG"
    )
)

rem --- apply saved keybinds + detect which macros are running ---
if exist "%RUNDIR%\*.run" (
    set "ZT_MODE=runs"
    set "ZT_ACT=prune"
    set "ZT_RUNDIR=%RUNDIR%"
    call :ps
)
for /l %%i in (1,1,!mc!) do (
    set "mr%%i="
    set "mu%%i="
    set "ou%%i="
    if exist "%CFG%" for /f "usebackq tokens=1,* delims==" %%A in ("%CFG%") do (
        if /i "%%A"=="!game!|!mn%%i!" (
            set "mk%%i=%%B"
            set "mu%%i=1"
        )
        if /i "%%A"=="!game!|!mn%%i!|_opts" set "ou%%i=1"
    )
    set "rf%%i=%RUNDIR%\!game!__!mn%%i!!mx%%i!.run"
    if exist "!rf%%i!" set "mr%%i=1"
)

if !mc!==0 if not defined ztfix (
    set "ztfix=1"
    call :dosync "Repairing macro files"
    goto macrolist
)

echo   %w%[ MACROS ]%n%
echo.
if !mc!==0 (
    echo   %dim%No macros for this game yet.%n%
) else (
    for /l %%i in (1,1,!mc!) do (
        set "nm=!mn%%i!                              "
        set "ky=!mk%%i!            "
        set "st="
        if defined mr%%i set "st=%gr%running%n%"
        echo   %r%[%%i]%n% !nm:~0,26! %dim%!ky:~0,12!%n% !st!
    )
)
echo.
echo   %r%[#]%n% Start   %r%[K]%n% Set key   %r%[S]%n% Stop   %r%[SA]%n% Stop all
echo   %r%[O]%n% Slot keys   %r%[R]%n% Refresh   %r%[B]%n% Back   %r%[0]%n% Exit
echo.

:macropick
<nul set /p "=%ESC%[?25h"
set "pick="
set /p "pick=  %r%>%n% "
if not defined pick goto macropick
if "!pick!"=="0" goto quit
if /i "!pick!"=="b" goto gamelist_back
if /i "!pick!"=="r" (
    set "ztfix="
    goto macrolist
)
if /i "!pick!"=="sa" (
    call :stopall
    goto macrolist
)
set "c1=!pick:~0,1!"
set "rest=!pick:~1!"
if /i "!c1!"=="k" goto dobind
if /i "!c1!"=="s" goto dostop
if /i "!c1!"=="o" goto doopt
goto dolaunch

:badpick
echo   %d%Invalid choice.%n%
goto macropick

rem ---------- rebind a key ----------
:dobind
if not defined rest set /p "rest=  Macro number %r%>%n% "
if not defined rest goto macropick
call :getnum "!rest!"
if errorlevel 1 goto badpick
if "!mk%pn%!"=="" (
    echo   %d%This macro has no keybind.%n%
    goto macropick
)
set "ZT_MODE=bind"
set "ZT_CFG=%CFG%"
set "ZT_ID=!game!|!mn%pn%!"
set "ZT_NAME=!mn%pn%!"
set "ZT_FIRST="
echo.
call :ps
<nul set /p "=%ESC%[?25l"
goto macrolist

rem ---------- set slot keys (rpg, hoverboard ...) ----------
:doopt
if not defined rest set /p "rest=  Macro number %r%>%n% "
if not defined rest goto macropick
call :getnum "!rest!"
if errorlevel 1 goto badpick
if not defined mo!pn! (
    echo   %dim%This macro has no slot keys.%n%
    goto macropick
)
call :runopts !pn!
goto macrolist

rem ---------- stop one macro ----------
:dostop
if not defined rest set /p "rest=  Macro number %r%>%n% "
if not defined rest goto macropick
call :getnum "!rest!"
if errorlevel 1 goto badpick
if not defined mr!pn! (
    echo   %dim%That macro is not running.%n%
    goto macropick
)
call :killrf !pn!
goto macrolist

rem ---------- start a macro ----------
:dolaunch
call :getnum "!pick!"
if errorlevel 1 goto badpick
if defined mr!pn! (
    echo   %dim%That macro is already running.%n%
    goto macropick
)
rem --- first time this macro is used: ask which key to press ---
if not "!mk%pn%!"=="" if not defined mu!pn! (
    set "ZT_MODE=bind"
    set "ZT_CFG=%CFG%"
    set "ZT_ID=!game!|!mn%pn%!"
    set "ZT_NAME=!mn%pn%!"
    set "ZT_FIRST=1"
    set "ZT_DEFAULT=!mk%pn%!"
    echo.
    call :ps
    set "ZT_FIRST="
    call :loadkey !pn!
    <nul set /p "=%ESC%[?25l"
)
if defined mo!pn! if not defined ou!pn! call :runopts !pn! 1
set "mfile=!mf%pn%!"
set "mname=!mn%pn%!"
set "mext=!mx%pn%!"
set "tdir=%TEMP%\zt_%random%%random%"
md "!tdir!" >nul 2>&1
set "ZT_MODE=run"
set "ZT_CFG=%CFG%"
set "ZT_ID=!game!|!mn%pn%!"
set "ZT_FILE=!mfile!"
set "ZT_OUT=!tdir!\!mname!!mext!"
set "ZT_KEY=!mk%pn%!"
set "ZT_RUN=!rf%pn%!"
set "ZT_LAUNCH="
if /i "!mext!"==".ps1" set "ZT_LAUNCH=ps1"
echo.
echo   %w%Starting%n% !mname! ...
call :ps
if errorlevel 1 (
    echo   %d%Could not open macro. Re-launch to re-fetch it.%n%
    rd /s /q "!tdir!" >nul 2>&1
    echo   %dim%Press any key...%n%
    pause >nul
    goto macrolist
)
if /i "!mext!"==".ps1" goto waitrun
set "runner=python"
where py >nul 2>&1
if not errorlevel 1 set "runner=py"
if /i "!mext!"==".py" start "ZT !mname!" /d "!tdir!" cmd /c "!runner! "!ZT_OUT!" & rd /s /q "!tdir!""
if /i "!mext!"==".bat" start "ZT !mname!" /d "!tdir!" cmd /c "call "!ZT_OUT!" & rd /s /q "!tdir!""
if /i "!mext!"==".cmd" start "ZT !mname!" /d "!tdir!" cmd /c "call "!ZT_OUT!" & rd /s /q "!tdir!""
goto macrolist

:waitrun
set /a tries=0
:waitrun2
if exist "!ZT_RUN!" goto macrolist
set /a tries+=1
if !tries! GEQ 24 goto runfail
call :wait 250
goto waitrun2

:runfail
echo   %d%Macro did not start - its hotkey is probably in use by another program.%n%
rd /s /q "!tdir!" >nul 2>&1
echo   %dim%Press any key...%n%
pause >nul
goto macrolist

:quit
call :stopall
cls
<nul set /p "=%ESC%[?25h"
exit /b 0

rem ===================== SUBROUTINES =====================
:ps
call :psquick || call :ensureps
if errorlevel 1 (
    echo   %d%core.ps1 is missing and could not be repaired.%n%
    exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%CORE%\core.ps1"
exit /b %errorlevel%

:runopts
set "ZT_MODE=opts"
set "ZT_CFG=%CFG%"
set "ZT_ID=!game!|!mn%1!"
set "ZT_NAME=!mn%1!"
set "ZT_OPTS=!mf%1!.opts"
set "ZT_FIRST=%~2"
echo.
call :ps
set "ZT_FIRST="
set "ou%1=1"
<nul set /p "=%ESC%[?25l"
exit /b

:dosync
echo.
echo   %g%%~1%n%
echo.
set "ZT_MODE=sync"
set "ZT_BASE=%BASE%"
set "ZT_STORE=%STORE%"
call :ps
set "rc=!errorlevel!"
<nul set /p "=%ESC%[2A%ESC%[1G%ESC%[0J%ESC%[?25l"
exit /b

:psquick
if not exist "%CORE%\core.ps1" exit /b 1
for %%F in ("%CORE%\core.ps1") do if %%~zF LSS 200 exit /b 1
exit /b 0

:psvalid
if not exist "%~1" exit /b 1
for %%F in ("%~1") do if %%~zF LSS 200 exit /b 1
powershell -NoProfile -Command "$source=[IO.File]::ReadAllText('%~1');if(-not $source.Contains('$env:ZT_MODE -eq ''sync''') -or -not $source.Contains('$env:ZT_MODE -eq ''run''') -or -not $source.Contains('$env:ZT_MODE -eq ''bind''')){exit 1};$tokens=$null;$errors=$null;[System.Management.Automation.Language.Parser]::ParseFile('%~1',[ref]$tokens,[ref]$errors)>$null;if($errors.Count -gt 0){exit 1}" >nul 2>&1
exit /b %errorlevel%

:ensureps
if not exist "%CORE%" md "%CORE%" >nul 2>&1
echo   %dim%core.ps1 is missing or damaged - repairing...%n%
set "pstmp=%CORE%\core.ps1.new"
for %%T in (1 2 3) do (
    del "!pstmp!" >nul 2>&1
    set "psurl=%BASE%/core/core.ps1?r=!random!!random!"
    where curl >nul 2>&1
    if not errorlevel 1 (
        curl -fsSL --max-time 20 -o "!pstmp!" "!psurl!" >nul 2>&1
    ) else (
        powershell -NoProfile -Command "try{(New-Object Net.WebClient).DownloadFile('!psurl!','!pstmp!')}catch{}" >nul 2>&1
    )
    call :psvalid "!pstmp!"
    if not errorlevel 1 (
        move /y "!pstmp!" "%CORE%\core.ps1" >nul
        exit /b 0
    )
)
del "!pstmp!" >nul 2>&1
exit /b 1

:loadkey
if exist "%CFG%" for /f "usebackq tokens=1,* delims==" %%A in ("%CFG%") do if /i "%%A"=="!game!|!mn%1!" (
    set "mk%1=%%B"
    set "mu%1=1"
)
exit /b

:getnum
set "pn="
echo %~1| findstr /r "^[1-9][0-9]*$" >nul || exit /b 1
set /a pn=%~1
if !pn! GTR !mc! exit /b 1
exit /b 0

:killrf
set "ZT_MODE=runs"
set "ZT_ACT=stop"
set "ZT_RUNDIR=%RUNDIR%"
set "ZT_TARGET=!rf%1!"
call :ps
del "!rf%1!" >nul 2>&1
exit /b

:stopall
if not exist "%RUNDIR%\*.run" exit /b 0
set "ZT_MODE=runs"
set "ZT_ACT=stopall"
set "ZT_RUNDIR=%RUNDIR%"
call :ps
exit /b 0

:gamelist
echo   %w%[ SELECT GAME ]%n%
echo.
for /l %%i in (1,1,!gcount!) do (
    echo   %r%[%%i]%n% !game%%i!
    call :wait 90
)
echo   %r%[0]%n% Exit
echo.
exit /b

:wait
ping -n 1 -w %1 192.0.2.1 >nul 2>&1
exit /b

:art
echo %w%8888%g%88888%r%8P%g%                           %w%88%g%8
echo %g%      d8%r%8P%g%                            %w%8%g%88
echo %g%     %w%d%g%8%r%8P%g%                             88%r%8
echo %g%    %w%d%g%88%r%P%g%     %w%.d%g%88b.  %w%88%g%8d8%r%8%d%8%g%  %w%.d%g%88%r%b.%g%  8%r%888%d%88%g% %w%88%g%8d8%r%8%d%8%g%  %w%88%g%88b.   %w%.d%g%88%r%88%d%b%g%  %w%.d%g%88b.
echo %g%   d8%r%8P%g%     %w%d%g%8P  Y%r%8%d%b%g% %w%8%g%88P%r%"%g%   %w%d%g%88""8%r%8b%g% %r%888%g%    %w%8%g%88P%r%"%g%       "88%r%b%g% %w%d%g%88P%r%"%g%    %w%d%g%8P  Y%r%8%d%b
echo %g%  %r%d88%d%P%g%      88%r%8888%d%88%g% 88%r%8%g%     88%r%8%g%  %r%88%d%8%g% %r%88%d%8%g%    88%r%8%g%     .%w%d%g%888%r%888%g% 88%r%8%g%      88%r%8888%d%88
echo %g% %r%d88%d%P%g%       Y%r%8b.%g%     8%r%8%d%8%g%     Y%r%88..8%d%8P%g% %r%Y88%d%b.%g%  8%r%8%d%8%g%     88%r%8%g%  %r%88%d%8%g% Y%r%88b.%g%    Y%r%8b.
echo %r%d888888%d%8888%g%  %r%"Y888%d%88%g% %r%8%d%88%g%      %r%"Y88%d%P"%g%   %r%"Y8%d%88%g% %r%8%d%88%g%     %r%"Y8888%d%88%g%  %r%"Y888%d%8P%g%  %r%"Y888%d%88
echo %n%
exit /b

