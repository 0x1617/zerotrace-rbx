# ZeroTrace macro: Roblox log (Esc, L, Enter)
# Hotkey: F2   |   Stop: Ctrl+Alt+Q
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

function Start-Macro([string]$Name, [string]$KeyName, [uint32]$Vk, [scriptblock]$Action) {
    if (-not [ZT]::RegisterHotKey([IntPtr]::Zero, 1, 0, $Vk)) {
        Write-Host "[ZeroTrace] $KeyName is already in use by another program."; exit 1
    }
    [void][ZT]::RegisterHotKey([IntPtr]::Zero, 2, 0x3, 0x51)   # Ctrl+Alt+Q = stop
    Write-Host "[ZeroTrace] $Name active.  Hotkey: $KeyName   Stop: Ctrl+Alt+Q"
    try { while (([ZT]::Next()) -ne 2) { & $Action } }
    finally { [void][ZT]::UnregisterHotKey([IntPtr]::Zero, 1); [void][ZT]::UnregisterHotKey([IntPtr]::Zero, 2) }
}

# Virtual-key codes: Esc=0x1B Enter=0x0D  0-9=0x30-0x39  A-Z=0x41-0x5A  F2=0x71 F3=0x72 F13=0x7C

Start-Macro 'Roblox log (Esc, L, Enter)' 'F2' 0x71 {
    [ZT]::Tap(0x1B); [ZT]::Wait(150)
    [ZT]::Tap(0x4C); [ZT]::Wait(15)
    [ZT]::Tap(0x0D)
}
