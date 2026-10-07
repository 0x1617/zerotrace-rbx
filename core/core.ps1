$ErrorActionPreference = 'Stop'
# Invoke-WebRequest draws a blue progress banner over the top of the console (over the logo) - turn it off.
$ProgressPreference = 'SilentlyContinue'
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
    $bust  = '?r=' + [guid]::NewGuid().ToString('N')     # skip GitHub's raw cache
    $new   = "$store.new"
    [Console]::Write("$e[?25l")
    try {
        To 20
        $m = (Invoke-WebRequest -UseBasicParsing -Uri "$base/manifest.txt$bust" -TimeoutSec 15).Content
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
            $url = "$base/" + [uri]::EscapeDataString($it[0]) + '/' + [uri]::EscapeDataString($it[1]) + $bust
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
