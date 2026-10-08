$ErrorActionPreference = 'Stop'
# Invoke-WebRequest draws a blue progress banner over the top of the console (over the logo) - turn it off.
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Security
$e = [char]27
# Macros are stored with Windows DPAPI (current user + this machine) plus app-specific entropy.
$ent = [Text.Encoding]::UTF8.GetBytes('zerotrace-rbx/v1')
$script:cur = 0

function ConvertTo-KeyName($k) {
    $kn = $k.Key.ToString()
    $named = @{ Spacebar='Space'; LeftArrow='Left'; RightArrow='Right'; UpArrow='Up'; DownArrow='Down';
                Enter='Enter'; Tab='Tab'; Delete='Delete'; Insert='Insert'; Home='Home'; End='End';
                PageUp='PageUp'; PageDown='PageDown' }
    if     ($kn -match '^D([0-9])$')       { return $matches[1] }
    elseif ($kn -match '^NumPad([0-9])$')  { return 'Num' + $matches[1] }
    elseif ($kn -match '^F\d{1,2}$')       { return $kn }
    elseif ($kn -match '^[A-Z]$')          { return $kn }
    elseif ($named.ContainsKey($kn))       { return $named[$kn] }
    return $null
}

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
            if ($x.Count -lt 2 -or $x.Count -gt 3) { continue }
            $g = $x[0].Trim(); $f = $x[1].Trim()
            $nm = ''
            if ($x.Count -eq 3) {
                $nm = $x[2].Trim()
                if ($nm -notmatch "^[A-Za-z0-9][A-Za-z0-9 .,()+_'-]*$") { $nm = '' }
            }
            if ($g -notmatch '^[A-Za-z0-9][\w .-]*$') { continue }
            if ($f -notmatch '^[A-Za-z0-9][\w .-]*\.(ps1|py|bat|cmd)$') { continue }
            if ($g.Contains('..') -or $f.Contains('..')) { continue }
            $items += ,@($g, $f, $nm)
        }
        if ($items.Count -eq 0) { To 1000; exit 2 }

        if (Test-Path $new) { Remove-Item $new -Recurse -Force }
        New-Item -ItemType Directory -Path $new -Force | Out-Null
        $i = 0
        foreach ($it in $items) {
            $url = "$base/" + [uri]::EscapeDataString($it[0]) + '/' + [uri]::EscapeDataString($it[1]) + $bust
            $tmp = Join-Path $new ([guid]::NewGuid().ToString('N') + '.tmp')
            try {
                Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $tmp -TimeoutSec 30
                $bytes = [IO.File]::ReadAllBytes($tmp)
            } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
            $enc = [Security.Cryptography.ProtectedData]::Protect($bytes, $ent, 'CurrentUser')
            $gd = Join-Path $new $it[0]
            New-Item -ItemType Directory -Path $gd -Force | Out-Null
            $zt = Join-Path $gd ($it[1] + '.zt')
            [IO.File]::WriteAllBytes($zt, $enc)
            [IO.File]::AppendAllText((Join-Path $gd 'order.txt'), $it[1] + "`r`n", [Text.Encoding]::ASCII)
            if ($it[2]) { [IO.File]::WriteAllText("$zt.name", $it[2], [Text.Encoding]::ASCII) }
            # default keybind (from a "# Key: F2" header line) is kept as plain metadata
            $txt = [Text.Encoding]::UTF8.GetString($bytes)
            $ol = @()
            foreach ($om in [regex]::Matches($txt, '(?m)^#\s*Option:\s*(\w+)\s*\|\s*([^|\r\n]+?)\s*\|\s*(\S+)\s*$')) {
                $ol += ($om.Groups[1].Value + '|' + $om.Groups[2].Value + '|' + $om.Groups[3].Value)
            }
            if ($ol.Count -gt 0) { [IO.File]::WriteAllLines("$zt.opts", [string[]]$ol, (New-Object Text.UTF8Encoding($false))) }
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
        if ($env:ZT_CFG -and $env:ZT_ID -and (Test-Path $env:ZT_CFG)) {
            $pre = "$($env:ZT_ID)|"
            foreach ($cl in (Get-Content $env:ZT_CFG)) {
                if ($cl.StartsWith($pre)) {
                    $kv = $cl.Substring($pre.Length).Split('=', 2)
                    if ($kv.Count -eq 2 -and $kv[0] -match '^[A-Za-z0-9]+$') {
                        [Environment]::SetEnvironmentVariable("ZT_OPT_$($kv[0])", $kv[1], 'Process')
                    }
                }
            }
        }
        if ($env:ZT_LAUNCH -eq 'ps1') {
            # background, hidden, so several macros can run at once
            $mp = Start-Process -FilePath powershell.exe -WindowStyle Hidden -WorkingDirectory $env:TEMP -PassThru `
                -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$($env:ZT_OUT)`"")
            # watcher: if the launcher window is closed, stop this macro too
            try {
                $par = (Get-CimInstance Win32_Process -Filter "ProcessId=$PID").ParentProcessId
                if ($par -and $env:ZT_RUN) {
                    $head = "`$par=$par;`$mac=$($mp.Id);`$run='$($env:ZT_RUN -replace "'","''")';"
                    $body = @'
while ($true) {
    Start-Sleep -Milliseconds 500
    $m = Get-Process -Id $mac -ErrorAction SilentlyContinue
    if (-not $m -or $m.HasExited) { exit }
    $q = Get-Process -Id $par -ErrorAction SilentlyContinue
    if (-not $q -or $q.HasExited) { break }
}
try { $c = (Get-Content -LiteralPath $run -ErrorAction Stop | Select-Object -First 1).Trim() } catch { exit }
if ($c -eq "$mac") {
    Stop-Process -Id $mac -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $run -Force -ErrorAction SilentlyContinue
}
'@
                    $enc2 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($head + $body))
                    Start-Process -FilePath powershell.exe -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $enc2)
                }
            } catch {}
        }
        exit 0
    } catch { exit 1 }
}

if ($env:ZT_MODE -eq 'opts') {
    $id = $env:ZT_ID; $cfg = $env:ZT_CFG
    $first = ($env:ZT_FIRST -eq '1')
    [Console]::Write("$e[?25h")
    $opts = @()
    foreach ($l in [IO.File]::ReadAllLines($env:ZT_OPTS)) {
        $x = $l.Split('|')
        if ($x.Count -ge 3) { $opts += ,@($x[0], $x[1], $x[2]) }
    }
    $lines = @()
    if (Test-Path $cfg) { $lines = @(Get-Content $cfg | Where-Object { $_ }) }
    if ($first) { [Console]::WriteLine("  First time setup for '$($env:ZT_NAME)'. Press the key you use in game for each item.") }
    else        { [Console]::WriteLine("  Slot keys for '$($env:ZT_NAME)'.") }
    foreach ($o in $opts) {
        $cur = $o[2]
        foreach ($l in $lines) { if ($l.StartsWith("$id|$($o[0])=")) { $cur = $l.Substring("$id|$($o[0])=".Length) } }
        if ($first) { [Console]::WriteLine("  $($o[1])  -  Esc = default ($($o[2]))   Backspace = none") }
        else        { [Console]::WriteLine("  $($o[1])  (now: $cur)  -  Esc = keep   Backspace = none") }
        $val = $null
        while ($null -eq $val) {
            $k = [Console]::ReadKey($true)
            if ($k.Key -eq 'Escape')    { if ($first) { $val = $o[2] } else { $val = $cur } }
            elseif ($k.Key -eq 'Backspace') { $val = 'none' }
            else {
                $nm = ConvertTo-KeyName $k
                if ($nm) { $val = $nm } else { [Console]::WriteLine("  That key can't be used, try another.") }
            }
        }
        [Console]::WriteLine("    -> $val")
        $lines = @($lines | Where-Object { -not $_.StartsWith("$id|$($o[0])=") })
        $lines += "$id|$($o[0])=$val"
    }
    $lines = @($lines | Where-Object { -not $_.StartsWith("$id|_opts=") })
    $lines += "$id|_opts=1"
    [IO.File]::WriteAllLines($cfg, [string[]]$lines)
    Start-Sleep -Milliseconds 500
    exit 0
}

if ($env:ZT_MODE -eq 'runs') {
    $files = @()
    if ($env:ZT_ACT -eq 'stop') { $files = @($env:ZT_TARGET) }
    else { $files = @(Get-ChildItem -Path $env:ZT_RUNDIR -Filter '*.run' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }) }
    foreach ($f in $files) {
        $id = 0
        try { $id = [int](Get-Content -LiteralPath $f -ErrorAction Stop | Select-Object -First 1) } catch {}
        $alive = $false
        if ($id -gt 0) {
            $p = Get-Process -Id $id -ErrorAction SilentlyContinue
            if ($p -and -not $p.HasExited -and $p.ProcessName -eq 'powershell') { $alive = $true }
        }
        if ($alive -and $env:ZT_ACT -ne 'prune') {
            Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
            $alive = $false
        }
        if (-not $alive) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
    }
    exit 0
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
