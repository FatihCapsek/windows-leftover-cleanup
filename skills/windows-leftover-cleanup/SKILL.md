---
name: windows-leftover-cleanup
description: Find and clean leftovers of uninstalled apps on Windows (AppData, LocalLow, ProgramData, Program Files folders, dead startup entries and shortcuts, caches/temp) and properly uninstall programs, always showing the list first and sending approved items to the Recycle Bin. Use this whenever the user wants to free disk space, clean junk / gereksiz dosyalar / kalıntılar, remove an app "completely", uninstall something (e.g. "FACEIT'i kaldır", "Java'yı kaldır", "Krisp sürücülerini sil"), asks what old programs left behind, or says the PC is full or slow because of clutter — even if they don't say "leftover" or "cleanup".
---

# Windows leftover cleanup

This skill captures a cleanup workflow that worked well in practice: scan → explain → let the user choose → recycle → verify. The user's trust depends on two things: **nothing disappears that they did not approve**, and **everything removed can be brought back** until they empty the Recycle Bin themselves.

Talk to the user in their own language (often Turkish). Use plain words: "Geri Dönüşüm Kutusu", "yönetici izni", not jargon.

## Ground rules (and why)

- **Recycle, never hard-delete.** Use `scripts/recycle.ps1` (it uses `Microsoft.VisualBasic.FileIO.FileSystem` with `SendToRecycleBin`). `Remove-Item` is permanent; one wrong guess about a folder (a game save, a project) would be unrecoverable. Never empty the Recycle Bin yourself — tell the user they can do it after a few days once everything still works.
- **Show first, act after approval.** Present the grouped list with sizes, then ask (AskUserQuestion with multiSelect works well, one option per group plus big individual items). Only act on what was approved. If the user's follow-up is ambiguous ("onları da gönder"), say which items you understood, inspect them, then act.
- **Look inside before you call something junk.** Folder names lie. Before proposing a folder, peek at its top-level contents. Personal data changes the decision: call recordings, game saves (`LocalLow`, `*.sav`, studio-named folders in Roaming), Minecraft worlds, documents, VM disks, SSH keys. Mention them and leave them unless the user explicitly chooses them — and if a folder you were going to remove turns out to hold such data, check whether it is empty before proceeding.
- **Uninstall properly, don't just delete program folders.** A program that still has drivers, services or an uninstall entry should go through its own uninstaller first; deleting its folder leaves drivers running and broken registry entries.
- **Don't touch Windows or shared runtimes**: `Microsoft`, `Packages`, `WindowsApps`, `dotnet`, VC++ redistributables, `Common Files`, Docker/WSL data, browser profiles of installed browsers, anything belonging to an installed program. Never touch `%LOCALAPPDATA%\Temp\claude` (Claude's own working files).

## Step 1 — Scan (read-only) — start immediately

As soon as this skill is triggered, start the scan in the same turn. Don't ask "shall I scan?" or ask about preferences first: the scan only reads, changes nothing, and the user expects to see results right away. Tell them in one short line that you are scanning and that nothing will be deleted without their approval, then run it. If the request names a specific app ("FACEIT'i kaldır"), still run the scan, then focus the findings on that app (its uninstall entry, processes, services/drivers, folders, Run entries, shortcuts) and mention other big leftovers only briefly.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill>/scripts/scan_leftovers.ps1"          # add -ShowInstalled to see matched folders too
```

It prints a tab-separated table: `Category  Path  MB  Modified  Hint`, takes ~20–60 s. Categories:

| Category | Meaning |
|---|---|
| `ORPHAN?` | Name matches no installed program, Store app, running process or service. A *candidate*, not a verdict. |
| `CACHE` | Temp / crash dumps / npm etc. Safe; regenerates. |
| `EMPTY` | Folder with no files. |
| `RUN` | Startup entry whose exe no longer exists. |
| `SHORTCUT` | Start-menu/desktop shortcut whose target is gone. |

The name matching is heuristic. Also compare by eye against the installed list (`Get-ItemProperty HKLM:\...\Uninstall\*, HKLM:\...\WOW6432Node\...\Uninstall\*, HKCU:\...\Uninstall\*` plus `Get-AppxPackage`), and look for things the script cannot see:
- `*-updater` folders (Squirrel/electron updaters such as `notion-updater`, `termius-updater`): if the app is gone they are pure leftovers; if the app is installed they hold an old installer copy and are cache.
- A Run entry pointing at an app folder that no longer exists (e.g. Notion uninstalled but still launched at login).
- An app removed but its **drivers/services still running** (e.g. Krisp Audio Drivers, anti-cheat): check `Get-CimInstance Win32_SystemDriver` and `Get-Service` for the name.
- Very old runtimes that are a security risk (e.g. Java 8 Update 51) — suggest a proper uninstall.
- Big SDK folders whose IDE is gone (e.g. `%LOCALAPPDATA%\Android\Sdk` without Android Studio) — the user's call.

Note: on Turkish Windows, case-insensitive regex/`ToLower()` turns `I` into `ı`, so `MSI` can become `ms`. The scanner uses `-creplace` and `ToLowerInvariant()` for this reason; do the same in any ad-hoc matching you write.

## Step 2 — Present the findings

Use this structure (translate headings to the user's language), sizes rounded, biggest first within each group:

```
## A) Kaldırılmış uygulamalardan kalanlar (güvenli) — ≈ X GB
| # | Ne | Konum | Boyut |
...
## B) Önbellek / geçici dosyalar (güvenli, yeniden oluşur) — ≈ X GB
## C) Senin karar vermen gerekenler
- item — why it might be junk, what it would break, any personal data inside
**Dokunmadıklarım:** game saves, installed apps' data, Docker, browsers, …
```

State that everything goes to the Recycle Bin and in-use files are skipped. Then ask which groups/items to remove.

## Step 3 — Remove what was approved

**Uninstall programs first** (close their processes before, `Stop-Process -Force`):
- Read `UninstallString` / `QuietUninstallString` from the Uninstall registry keys.
- MSI products (`MsiExec.exe /I{GUID}`): `Start-Process msiexec.exe -ArgumentList '/x','{GUID}','/qb','/norestart' -Wait` — Windows shows its own UAC prompt; tell the user to click **Evet/Yes**.
- Squirrel/Electron apps (`...\AppData\Local\<App>\Update.exe --uninstall`): run with `--uninstall -s`.
- Others: prefer the vendor's quiet switch if listed; otherwise launch the uninstaller and let the user click through.
- Verify afterwards: the uninstall key is gone, services/drivers are gone (`Get-Service`, `Win32_SystemDriver`), check `Get-WinEvent` MsiInstaller events if something was already removed earlier.

**Then recycle leftover folders.** Write the approved paths to a list file (one per line; prefix `contents:` to empty a folder but keep it, which is what you want for `%LOCALAPPDATA%\Temp` and `CrashDumps`), then:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill>/scripts/recycle.ps1" -ListFile <list.txt>
```

If any path is under `C:\Program Files` or `C:\ProgramData` and the shell is not elevated, the script relaunches itself elevated (one UAC prompt — warn the user before running) and prints the log. Keep the list file in your scratchpad, not in the user's folders.

**Clean startup entries and shortcuts** for removed apps: `Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name <name>` (and HKLM variants, which need admin), and recycle dead `.lnk` files / empty Start-menu folders.

Before a large batch, it is worth checking that the Recycle Bin can hold it (`HKCU:\...\Explorer\BitBucket\Volume\*\MaxCapacity`, in MB). If a batch exceeds it, Windows would offer permanent deletion instead — split the batch or tell the user.

If a tool call is blocked by the permission system, don't try to sneak around it: list the exact folders, explain how to delete them by hand (Win+R → `%LOCALAPPDATA%` → select → Delete) and offer to retry if the user approves.

## Step 4 — Report

Short and concrete, in the user's language:
- What was removed (grouped), how much space was freed in total.
- What failed or was skipped and why (in use, needs admin, not found), and what the user can do about it.
- What you deliberately left alone (personal data, game saves).
- Remind them items are in the Recycle Bin and can be restored; they can empty it themselves once everything works.
