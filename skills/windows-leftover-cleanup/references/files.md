# Judging files (mode: Files)

`scripts/scan_files.ps1` scans every fixed drive (≈2–5 min) and reports free space, Windows/system clutter, old installers and archives in Downloads/Desktop, the largest files outside Windows/program/game folders, and identical large files. Parameters: `-Top 40 -MinMB 200 -InstallerDays 30`.

Files are the user's own data, so the bar is higher than for app leftovers: **nothing in this mode is "safe" by default except caches and system clutter**. Always list files individually (path, size, date) and let the user pick.

## Typical findings and what to say

| Finding | Suggest |
|---|---|
| `SYSTEM` Windows.old, `$Windows.~BT`, SoftwareDistribution\Download | Disk Cleanup (`cleanmgr`) → "Clean up system files". Don't delete these folders by hand. |
| `SYSTEM` Recycle Bin size | Tell the user the size; only they should empty it. |
| `hiberfil.sys` | Mention only if space is tight; `powercfg /h off` disables hibernate and Fast Startup. User's call. |
| Old installers / archives in Downloads (`.exe .msi .iso .zip .rar`) | Usually safe once the program is installed; list them. Skip files inside project folders (`node_modules`, build output) — those belong to a project. |
| Videos/photos (GoPro, phone backups, recordings) | Personal media: **never** suggest deleting. Suggest moving to an external disk or cloud if space is short. |
| Docker `docker_data.vhdx`, WSL `ext4.vhdx`, Android `~\.android\avd\*` | Belongs to a tool; handle in Apps mode (prune/uninstall the tool), never delete the disk image directly. |
| Browser model files (`OptGuideOnDeviceModel`), GPU shader caches (`NVIDIA\DXCache`) | Regenerate automatically; deleting them frees space only temporarily. Mention, don't push. |
| `DUP` identical files | Show both paths; usually keep the one in the more sensible place. Tool binaries (`codex.exe`, `claude.exe` copies) are managed by their tools — leave them. |
| Unknown big folders on data drives (e.g. a cracked/repack game folder) | Ask what it is; don't assume. |

Recycle approved files with `scripts/recycle.ps1` (one path per line). Large media can exceed the Recycle Bin quota — check `MaxCapacity` and warn the user, or suggest moving instead of deleting.
