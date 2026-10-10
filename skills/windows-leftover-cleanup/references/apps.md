# Judging installed apps (mode: Apps)

`scripts/scan_apps.ps1` lists programs, Store apps, games and startup entries with hint flags. The flags are starting points; the decision comes from the user's situation, so check usage evidence before suggesting removal.

## Usually safe to suggest (group A)

| Pattern | Why | How to remove |
|---|---|---|
| `VS-LEFTOVER`: IIS Express (+ its two "Application Compatibility Database" entries), SQL Server LocalDB, Web Deploy, `vs_*` fonts, Visual Studio Installer, Azure Functions tools — while no `devenv.exe` exists | Components of a Visual Studio that was uninstalled | `msiexec /x {GUID} /qn /norestart`; compat DBs with `sdbinst -q -u "<sdb>"`; VS Installer last: `setup.exe /uninstall` |
| `OLD-PATCH`: an older patch of a .NET runtime when a newer patch of the same major.minor and architecture is installed (10.0.7 next to 10.0.10) | Apps roll forward to the newest patch; old patches are only unpatched copies | Run the **bundle** entry's `QuietUninstallString` (`windowsdesktop-runtime-…exe /uninstall /quiet /norestart`), which also removes its child MSIs (runtime, hostfxr). Never remove the only copy of a major.minor (e.g. the single x64 8.0.x). |
| `TELEMETRY` (Intel Computing Improvement Program, vendor "customer experience" tools) | Only sends usage data | MSI uninstall |
| `WRONG-OS` (Update for Windows 10 / KB5001716 on Windows 11) | Not applicable | MSI uninstall |
| Folders of tools installed *through Steam* without a manifest (e.g. "Driver Booster for Steam") | Leftover of an uninstalled Steam app | recycle the folder |

## Ask the user (group C)

- `LAUNCHER-NO-GAME` — EA app / Rockstar / Epic with no game from that store. Check the store's game folders first: Rockstar Launcher is **required** for Red Dead Redemption 2 / GTA even when the game was bought on Epic or Steam.
- Big dev tools that were not used recently: Docker Desktop (check `%LOCALAPPDATA%\Docker\wsl\disk\*.vhdx` date and whether it auto-starts), Android emulator images (`~\.android\avd`), old SDKs. Offer "disable autostart" as a lighter alternative.
- Games: show size and LastPlayed (Steam manifests have it; Epic/Riot do not — say "unknown", don't guess from file access times, Windows often doesn't update them).
- Audio routing tools (Voicemeeter, ASIO4ALL, virtual cables) — may be part of the user's mic/streaming setup.
- Optional built-in Store apps (`OPTIONAL-INBOX`): Mixed Reality Portal, Dev Home (discontinued), old Mail & Calendar (`windowscommunicationsapps`, replaced by new Outlook), Movies & TV, Get Help. Remove with `Get-AppxPackage <name> | Remove-AppxPackage`.

## Leave alone unless the user insists

Drivers and their control panels (NVIDIA, Intel graphics/Bluetooth/DTT, Realtek, laptop vendor services like MSI Center), VC++ redistributables (old games need specific years), the only installed copy of any .NET major version, DirectX/XNA/OpenAL/PhysX (games), anti-cheat for installed games (Riot Vanguard, EasyAntiCheat), VPN/packet-filter drivers (WireSock, Windows Packet Filter — tools like SplitWire use them), peripherals' software when the device is connected (check `Get-PnpDevice -PresentOnly`, e.g. Razer Synapse for a Razer mic).

## Removing safely

- Close the app first. Prefer `QuietUninstallString`; for MSI use `/x {GUID} /qn /norestart` even if the registry shows `/I`.
- Put all admin uninstalls into **one** elevated script so the user sees one UAC prompt, and have it `Add-Content` a log line **after every step** (a log written only at the end is lost if a step hangs or the script dies). Run uninstallers one at a time with `-Wait`.
- Re-check right before removing a startup entry or shortcut: apps update themselves and a "dead" target may be valid again (a Store app moves to a new versioned folder on update).
- Verify afterwards from the Uninstall keys and the `MsiInstaller` events (IDs 1033/1034/11724) in the Application log, and report what is still installed.
