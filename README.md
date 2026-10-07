# zerotrace-rbx

Macro + app repo for the Zero Trace launcher. The launcher reads this repo on every start.

## Layout
- `zerotrace.bat` - the small launcher users download once. It fetches the latest core from `core/` and runs it.
- `core/core.bat` and `core/core.ps1` - the actual app (menus, fetching, encryption, keybinds).
- `manifest.txt` lists every macro as `Game|file`.
- `<Game>/<file>` are the macros. Supported types: `.ps1` (built into Windows), `.py`, `.bat`, `.cmd`.

## Updating the app
Edit `core/core.bat` or `core/core.ps1` and push. Every launcher picks up the change the next time it starts
(it keeps a cached copy for offline use). `zerotrace.bat` itself rarely needs to change.

## Macros
- The menu shows macro names without the file extension.
- A `.ps1` macro declares its default hotkey with a `# Key: F2` line near the top.
- The first time a user starts a macro, the launcher asks which key to press. Choices are saved locally in
  `%LOCALAPPDATA%\ZeroTrace\config.ini` and can be changed any time with `K<number>`.
- `.ps1` macros run hidden in the background, so several can run at once.

To add a macro: drop the file in the game's folder and add a line to `manifest.txt`.
