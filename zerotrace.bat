@echo off
setlocal EnableExtensions EnableDelayedExpansion
title Zero Trace
mode con cols=100 lines=40
cd /d "%~dp0"
set "SELF=%~f0"
rem App build number. Bump this (and version.txt in the repo) to push an update to everyone.
set "VER=1"
set "SKIPUPD=0"
if /i "%~1"=="updated" set "SKIPUPD=1"

rem ===================== CONFIG =====================
rem Public repo the games/macros are fetched from on every launch.
set "BASE=https://raw.githubusercontent.com/0x1617/zerotrace-rbx/main"
rem Local data (encrypted macros, your keybinds, runtime files)
set "ROOT=%LOCALAPPDATA%\ZeroTrace"
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
echo.
echo   %g%Initialising%n%
echo.
set "ZT_MODE=sync"
set "ZT_BASE=%BASE%"
set "ZT_STORE=%STORE%"
set "ZT_VER=%VER%"
set "ZT_SKIPUPD=%SKIPUPD%"
call :ps
set "rc=!errorlevel!"
if "!rc!"=="10" goto doupdate
<nul set /p "=%ESC%[?25l"
echo.
if "!rc!"=="1" echo   %dim%offline or repo unreachable - using cached macros%n%
if "!rc!"=="2" echo   %dim%no games published in the repo yet%n%
call :wait 400
echo.

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
    if exist "%%~fF.meta" set /p "mk!mc!=" <"%%~fF.meta"
    for %%G in ("%%~nF") do (
        set "mn!mc!=%%~nG"
        set "mx!mc!=%%~xG"
    )
)

rem --- apply saved keybinds + detect which macros are running ---
for /l %%i in (1,1,!mc!) do (
    set "mr%%i="
    set "mu%%i="
    if exist "%CFG%" for /f "usebackq tokens=1,* delims==" %%A in ("%CFG%") do if /i "%%A"=="!game!|!mn%%i!" (
        set "mk%%i=%%B"
        set "mu%%i=1"
    )
    set "rf%%i=%RUNDIR%\!game!__!mn%%i!!mx%%i!.run"
    if exist "!rf%%i!" call :checkrun %%i
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
echo   %r%[#]%n% Start   %r%[K#]%n% Set key   %r%[S#]%n% Stop   %r%[SA]%n% Stop all
echo   %r%[R]%n% Refresh   %r%[B]%n% Back   %r%[0]%n% Exit
echo.

:macropick
<nul set /p "=%ESC%[?25h"
set "pick="
set /p "pick=  %r%>%n% "
if not defined pick goto macropick
if "!pick!"=="0" goto quit
if /i "!pick!"=="b" goto gamelist_back
if /i "!pick!"=="r" goto macrolist
if /i "!pick!"=="sa" (
    call :stopall
    goto macrolist
)
set "c1=!pick:~0,1!"
set "rest=!pick:~1!"
if /i "!c1!"=="k" goto dobind
if /i "!c1!"=="s" goto dostop
goto dolaunch

:badpick
echo   %d%Invalid choice.%n%
goto macropick

rem ---------- rebind a key ----------
:dobind
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

rem ---------- stop one macro ----------
:dostop
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
set "mfile=!mf%pn%!"
set "mname=!mn%pn%!"
set "mext=!mx%pn%!"
set "tdir=%TEMP%\zt_%random%%random%"
md "!tdir!" >nul 2>&1
set "ZT_MODE=run"
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

rem ---------- self-update ----------
:doupdate
echo.
echo   %w%Updating Zero Trace to the latest build...%n%
start "" /min cmd /c "ping -n 3 127.0.0.1 >nul & copy /y "%ROOT%\update.bat" "%SELF%" >nul & del "%ROOT%\update.bat" & start "" "%SELF%" updated"
exit /b 0

:quit
call :stopall
cls
<nul set /p "=%ESC%[?25h"
exit /b 0

rem ===================== SUBROUTINES =====================
:ps
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText('%SELF%'); $i=$s.IndexOf('#PS'+'-BEGIN'); Invoke-Expression $s.Substring($i)"
exit /b %errorlevel%

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

:checkrun
set "pid="
set /p "pid=" <"!rf%1!"
tasklist /fi "pid eq !pid!" /nh 2>nul | find /i "powershell" >nul
if errorlevel 1 (del "!rf%1!" >nul 2>&1) else set "mr%1=1"
exit /b

:killrf
set "pid="
set /p "pid=" <"!rf%1!"
if defined pid taskkill /f /fi "pid eq !pid!" /fi "imagename eq powershell.exe" >nul 2>&1
del "!rf%1!" >nul 2>&1
exit /b

:stopall
for %%R in ("%RUNDIR%\*.run") do (
    set "pid="
    set /p "pid=" <"%%~fR"
    if defined pid taskkill /f /fi "pid eq !pid!" /fi "imagename eq powershell.exe" >nul 2>&1
    del "%%~fR" >nul 2>&1
)
exit /b

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

#PS-BEGIN
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Security
$e = [char]27
# Macros are stored with Windows DPAPI (current user + this machine) plus app-specific entropy.
$ent = [Text.Encoding]::UTF8.GetBytes('zerotrace-rbx/v1')
$script:cur = 0

function Bar([int]$p) {
    $f = [int][math]::Floor($p * 40 / 1000)
    $b = '#' * $f
    $d = '-' * (40 - $f)
    $w = [math]::Floor($p / 10)
    $fr = $p % 10
    [Console]::Write("$e[?25l$e[1G  $e[91m$b$e[90m$d $e[97m($w.$fr%)$e[0m   ")
}
function To([int]$t) {
    while ($script:cur -lt $t) {
        $script:cur = [math]::Min($t, $script:cur + 9)
        Bar $script:cur
        Start-Sleep -Milliseconds 12
    }
}

if ($env:ZT_MODE -eq 'sync') {
    $base  = $env:ZT_BASE
    $store = $env:ZT_STORE
    $new   = "$store.new"
    [Console]::Write("$e[?25l")
    try {
        # ---- check for a newer app build ----
        if ($env:ZT_SKIPUPD -ne '1') {
            try {
                $rv = (Invoke-WebRequest -UseBasicParsing -Uri "$base/version.txt" -TimeoutSec 10).Content
                if ($rv -is [byte[]]) { $rv = [Text.Encoding]::UTF8.GetString($rv) }
                $rv = ([string]$rv).Trim().TrimStart([char]0xFEFF)
                if ($rv -match '^\d+$' -and [int]$rv -gt [int]$env:ZT_VER) {
                    $upd = Join-Path (Split-Path $store) 'update.bat'
                    Invoke-WebRequest -UseBasicParsing -Uri "$base/zerotrace.bat" -OutFile $upd -TimeoutSec 30
                    $c = [IO.File]::ReadAllText($upd)
                    $c = $c -replace "(?<!\r)\n", "`r`n"          # make sure line endings are CRLF
                    if ($c.StartsWith('@echo off') -and $c.Contains('#PS' + '-BEGIN') -and $c.Contains("set `"VER=$rv`"")) {
                        [IO.File]::WriteAllText($upd, $c, [Text.Encoding]::ASCII)
                        exit 10
                    }
                    Remove-Item $upd -Force -ErrorAction SilentlyContinue
                }
            } catch {}
        }
        To 20
        $m = (Invoke-WebRequest -UseBasicParsing -Uri "$base/manifest.txt" -TimeoutSec 15).Content
        if ($m -is [byte[]]) { $m = [Text.Encoding]::UTF8.GetString($m) }
        $m = $m.TrimStart([char]0xFEFF)
        To 100

        $items = @()
        foreach ($l in ($m -split "\r?\n")) {
            $l = $l.Trim()
            if ($l -eq '' -or $l.StartsWith('#')) { continue }
            $x = $l.Split('|')
            if ($x.Count -ne 2) { continue }
            $g = $x[0].Trim(); $f = $x[1].Trim()
            if ($g -notmatch '^[A-Za-z0-9][\w .-]*$') { continue }
            if ($f -notmatch '^[A-Za-z0-9][\w .-]*\.(ps1|py|bat|cmd)$') { continue }
            if ($g.Contains('..') -or $f.Contains('..')) { continue }
            $items += ,@($g, $f)
        }
        if ($items.Count -eq 0) { To 1000; exit 2 }

        if (Test-Path $new) { Remove-Item $new -Recurse -Force }
        New-Item -ItemType Directory -Path $new -Force | Out-Null
        $i = 0
        foreach ($it in $items) {
            $url = "$base/" + [uri]::EscapeDataString($it[0]) + '/' + [uri]::EscapeDataString($it[1])
            $tmp = [IO.Path]::GetTempFileName()
            try {
                Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $tmp -TimeoutSec 30
                $bytes = [IO.File]::ReadAllBytes($tmp)
            } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
            $enc = [Security.Cryptography.ProtectedData]::Protect($bytes, $ent, 'CurrentUser')
            $gd = Join-Path $new $it[0]
            New-Item -ItemType Directory -Path $gd -Force | Out-Null
            $zt = Join-Path $gd ($it[1] + '.zt')
            [IO.File]::WriteAllBytes($zt, $enc)
            # default keybind (from a "# Key: F2" header line) is kept as plain metadata
            $txt = [Text.Encoding]::UTF8.GetString($bytes)
            if ($txt -match '(?m)^#\s*Key:\s*(\S+)') {
                [IO.File]::WriteAllText("$zt.meta", $matches[1], [Text.Encoding]::ASCII)
            }
            $i++
            To (100 + [int](900 * $i / $items.Count))
        }
        if (Test-Path $store) { Remove-Item $store -Recurse -Force }
        Move-Item $new $store
        To 1000
        exit 0
    } catch {
        if (Test-Path $new) { Remove-Item $new -Recurse -Force -ErrorAction SilentlyContinue }
        exit 1
    }
}

if ($env:ZT_MODE -eq 'run') {
    try {
        $enc = [IO.File]::ReadAllBytes($env:ZT_FILE)
        $dec = [Security.Cryptography.ProtectedData]::Unprotect($enc, $ent, 'CurrentUser')
        [IO.File]::WriteAllBytes($env:ZT_OUT, $dec)
        if ($env:ZT_LAUNCH -eq 'ps1') {
            # background, hidden, so several macros can run at once
            Start-Process -FilePath powershell.exe -WindowStyle Hidden -WorkingDirectory $env:TEMP `
                -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$($env:ZT_OUT)`"")
        }
        exit 0
    } catch { exit 1 }
}

if ($env:ZT_MODE -eq 'bind') {
    $id = $env:ZT_ID; $cfg = $env:ZT_CFG
    [Console]::Write("$e[?25h")
    $first = ($env:ZT_FIRST -eq '1')
    if ($first) {
        [Console]::WriteLine("  First time setup for '$($env:ZT_NAME)'.")
        [Console]::WriteLine("  Press the key (or a combo like Ctrl+F5) you want to use for it.")
        [Console]::WriteLine("  Esc = use the default ($($env:ZT_DEFAULT))")
    } else {
        [Console]::WriteLine("  Press the key (or a combo like Ctrl+F5) for '$($env:ZT_NAME)'.")
        [Console]::WriteLine("  Esc = cancel     Backspace = reset to default")
    }
    $k = [Console]::ReadKey($true)
    $kn = $k.Key.ToString()
    $lines = @()
    if (Test-Path $cfg) { $lines = @(Get-Content $cfg | Where-Object { $_ -and -not $_.StartsWith("$id=") }) }
    if ($first -and ($kn -eq 'Escape' -or $kn -eq 'Backspace')) {
        $lines += "$id=$($env:ZT_DEFAULT)"
        [IO.File]::WriteAllLines($cfg, [string[]]$lines)
        [Console]::WriteLine("  Using default: $($env:ZT_DEFAULT)")
        Start-Sleep -Milliseconds 700; exit 0
    }
    if ($kn -eq 'Escape') { exit 0 }
    if ($kn -eq 'Backspace') {
        [IO.File]::WriteAllLines($cfg, [string[]]$lines)
        [Console]::WriteLine("  Reset to default. Restart the macro to apply.")
        Start-Sleep -Milliseconds 900; exit 0
    }
    $named = @{ Spacebar='Space'; LeftArrow='Left'; RightArrow='Right'; UpArrow='Up'; DownArrow='Down';
                Enter='Enter'; Tab='Tab'; Delete='Delete'; Insert='Insert'; Home='Home'; End='End';
                PageUp='PageUp'; PageDown='PageDown' }
    if     ($kn -match '^D([0-9])$')       { $name = $matches[1] }
    elseif ($kn -match '^NumPad([0-9])$')  { $name = 'Num' + $matches[1] }
    elseif ($kn -match '^F\d{1,2}$')       { $name = $kn }
    elseif ($kn -match '^[A-Z]$')          { $name = $kn }
    elseif ($named.ContainsKey($kn))       { $name = $named[$kn] }
    else { [Console]::WriteLine("  That key can't be used."); Start-Sleep -Milliseconds 1200; exit 0 }
    $mods = ''
    if ($k.Modifiers -band [ConsoleModifiers]::Control) { $mods += 'Ctrl+' }
    if ($k.Modifiers -band [ConsoleModifiers]::Alt)     { $mods += 'Alt+' }
    if ($k.Modifiers -band [ConsoleModifiers]::Shift)   { $mods += 'Shift+' }
    $val = $mods + $name
    $lines += "$id=$val"
    [IO.File]::WriteAllLines($cfg, [string[]]$lines)
    [Console]::WriteLine("  Saved: $val   (restart the macro to apply)")
    Start-Sleep -Milliseconds 1000
    exit 0
}
