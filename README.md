# zerotrace-rbx

Macro + app repo for the Zero Trace launcher. The launcher reads this repo on every start.

## Layout
- `manifest.txt` lists every macro as `Game|file`.
- `<Game>/<file>` are the macros. Supported types: `.ps1` (built into Windows), `.py`, `.bat`, `.cmd`.
- `zerotrace.bat` is the launcher itself, and `version.txt` holds its build number.

## Macros
- The menu shows macro names without the file extension.
- A `.ps1` macro declares its default hotkey with a `# Key: F2` line near the top.
- The first time a user starts a macro, the launcher asks which key to press. Choices are saved locally in
  `%LOCALAPPDATA%\ZeroTrace\config.ini` and can be changed any time with `K<number>`.
- `.ps1` macros run hidden in the background, so several can run at once.

## Pushing an app update
1. Edit `zerotrace.bat` and raise the number in the `set "VER=..."` line.
2. Put the same number in `version.txt`.
3. Commit and push. Every launcher updates itself the next time it starts.

If the two numbers don't match, the update is ignored.
