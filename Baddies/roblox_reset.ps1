# ZeroTrace macro: Roblox reset (Esc, R, Enter)
# Key: F3
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Threading;
public static class ZT {
    [StructLayout(LayoutKind.Sequential)] struct MOUSEINPUT { public int dx, dy; public uint mouseData, dwFlags, time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)] struct KEYBDINPUT { public ushort wVk, wScan; public uint dwFlags, time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Explicit)] struct IU { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }
    [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public IU u; }
    [StructLayout(LayoutKind.Sequential)] struct MSG { public IntPtr hwnd; public uint message; public IntPtr wParam, lParam; public uint time; public int x, y; }
    [DllImport("user32.dll")] static extern uint SendInput(uint n, INPUT[] i, int size);
    [DllImport("user32.dll")] static extern uint MapVirtualKey(uint code, uint type);
    [DllImport("user32.dll")] static extern bool PeekMessage(out MSG m, IntPtr h, uint a, uint b, uint remove);
    [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr h, int id, uint mod, uint vk);
    [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr h, int id);
    static void Send(INPUT[] i) { SendInput((uint)i.Length, i, Marshal.SizeOf(typeof(INPUT))); }
    static INPUT K(ushort vk, bool up) {
        INPUT i = new INPUT(); i.type = 1;
        i.u.ki.wVk = vk; i.u.ki.wScan = (ushort)MapVirtualKey(vk, 0);
        i.u.ki.dwFlags = up ? 2u : 0u; return i;
    }
    public static void Tap(ushort vk) { Send(new INPUT[] { K(vk, false), K(vk, true) }); }
    public static void Click() {
        INPUT d = new INPUT(); d.type = 0; d.u.mi.dwFlags = 0x2;
        INPUT u = new INPUT(); u.type = 0; u.u.mi.dwFlags = 0x4;
        Send(new INPUT[] { d, u });
    }
    public static void Wait(int ms) { Thread.Sleep(ms); }
    public static int Next() {
        MSG m;
        while (true) {
            if (PeekMessage(out m, IntPtr.Zero, 0, 0, 1)) { if (m.message == 0x312) return (int)m.wParam; }
            else Thread.Sleep(5);
        }
    }
}
"@

# "F13", "Ctrl+F5", "Alt+Shift+Q", "Num5", "Space" ... -> modifier flags + virtual-key code
function Resolve-Key([string]$s) {
    if (-not $s) { return $null }
    $mod = 0; $vk = 0
    $parts = $s -split '\+'
    for ($i = 0; $i -lt $parts.Count - 1; $i++) {
        switch ($parts[$i].Trim().ToLower()) {
            'alt'   { $mod += 1 }
            'ctrl'  { $mod += 2 }
            'shift' { $mod += 4 }
            default { return $null }
        }
    }
    $n = $parts[$parts.Count - 1].Trim()
    if     ($n -match '^f(\d{1,2})$' -and [int]$matches[1] -ge 1 -and [int]$matches[1] -le 24) { $vk = 0x6F + [int]$matches[1] }
    elseif ($n -match '^[a-z]$')    { $vk = [int][char]$n.ToUpper() }
    elseif ($n -match '^[0-9]$')    { $vk = 0x30 + [int]$n }
    elseif ($n -match '^num([0-9])$') { $vk = 0x60 + [int]$matches[1] }
    else {
        $map = @{ space=0x20; tab=0x09; enter=0x0D; delete=0x2E; insert=0x2D; home=0x24; end=0x23;
                  pageup=0x21; pagedown=0x22; left=0x25; up=0x26; right=0x27; down=0x28 }
        if ($map.ContainsKey($n.ToLower())) { $vk = $map[$n.ToLower()] }
    }
    if ($vk -eq 0) { return $null }
    return [pscustomobject]@{ Mod = $mod; Vk = $vk }
}

# The launcher passes the user's saved keybind in $env:ZT_KEY; otherwise the default below is used.
function Start-Macro([string]$Name, [string]$DefaultKey, [scriptblock]$Action) {
    $keyStr = $DefaultKey
    $k = $null
    if ($env:ZT_KEY) { $k = Resolve-Key $env:ZT_KEY; if ($k) { $keyStr = $env:ZT_KEY } }
    if (-not $k) { $k = Resolve-Key $DefaultKey }
    if (-not [ZT]::RegisterHotKey([IntPtr]::Zero, 1, [uint32]$k.Mod, [uint32]$k.Vk)) {
        Write-Host "[ZeroTrace] $keyStr is already in use by another program."; exit 1
    }
    if ($env:ZT_RUN) { Set-Content -Path $env:ZT_RUN -Value $PID -Encoding ASCII }
    # when started by the launcher, remove the decrypted temp copy as soon as it is loaded
    try {
        if ($PSCommandPath -and ($PSCommandPath -like '*\zt_*\*')) {
            $dir = Split-Path $PSCommandPath
            Remove-Item $PSCommandPath -Force
            Remove-Item $dir -Force -ErrorAction SilentlyContinue
        }
    } catch {}
    Write-Host "[ZeroTrace] $Name active.  Hotkey: $keyStr   (Ctrl+C to stop when run by hand)"
    try { while ($true) { [void][ZT]::Next(); & $Action } }
    finally {
        [void][ZT]::UnregisterHotKey([IntPtr]::Zero, 1)
        if ($env:ZT_RUN) { Remove-Item $env:ZT_RUN -Force -ErrorAction SilentlyContinue }
    }
}

# Virtual-key codes: Esc=0x1B Enter=0x0D  0-9=0x30-0x39  A-Z=0x41-0x5A

Start-Macro 'Roblox reset' 'F3' {
    [ZT]::Tap(0x1B); [ZT]::Wait(150)
    [ZT]::Tap(0x52); [ZT]::Wait(15)
    [ZT]::Tap(0x0D)
}
