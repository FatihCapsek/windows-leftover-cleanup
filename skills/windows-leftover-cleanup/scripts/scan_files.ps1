<#
  Read-only scan for large and likely-unneeded FILES on all fixed drives. Removes nothing.
  Prints tab-separated sections:
    [SPACE]       Drive  FreeGB  SizeGB
    [SYSTEM]      Item  GB  Note                     (Windows.old, Recycle Bin, update leftovers...)
    [INSTALLERS]  Path  MB  Modified                 (.exe/.msi/.iso/.zip etc. in Downloads/Desktop, older than -InstallerDays)
    [LARGE]       Path  MB  Modified  LastAccess     (biggest files outside Windows/program folders)
    [DUPLICATES]  Hash  MB  Path                     (identical large files, same hash)
  Usage: powershell -NoProfile -ExecutionPolicy Bypass -File scan_files.ps1 [-Top 40] [-MinMB 200] [-InstallerDays 30]
#>
param([int]$Top = 40, [int]$MinMB = 200, [int]$InstallerDays = 30)
$ErrorActionPreference = 'SilentlyContinue'

function DirGB($p) { [math]::Round(((Get-ChildItem $p -Recurse -File -Force | Measure-Object Length -Sum).Sum) / 1GB, 2) }

# Fast recursive enumeration that skips folders we may not read and never follows junctions.
function Get-Files([string]$root, [long]$minBytes, [string[]]$skip) {
  $stack = New-Object System.Collections.Generic.Stack[string]; $stack.Push($root)
  while ($stack.Count) {
    $d = $stack.Pop()
    try { $di = New-Object IO.DirectoryInfo $d } catch { continue }
    try { foreach ($f in $di.EnumerateFiles()) { if ($f.Length -ge $minBytes) { $f } } } catch {}
    try {
      foreach ($s in $di.EnumerateDirectories()) {
        if ($s.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
        if ($skip | Where-Object { $s.FullName -like $_ }) { continue }
        $stack.Push($s.FullName)
      }
    } catch {}
  }
}

$drives = Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3'
"[SPACE]`tDrive`tFreeGB`tSizeGB"
$drives | ForEach-Object { "SPACE`t{0}`t{1:N1}`t{2:N1}" -f $_.DeviceID, ($_.FreeSpace / 1GB), ($_.Size / 1GB) }

"[SYSTEM]`tItem`tGB`tNote"
foreach ($x in @(
    @('C:\Windows.old', 'previous Windows install; remove with Disk Cleanup (cleanmgr) > Previous Windows installation(s)'),
    @('C:\$Windows.~BT', 'upgrade leftovers; Disk Cleanup'),
    @('C:\$Windows.~WS', 'upgrade leftovers; Disk Cleanup'),
    @('C:\Windows\SoftwareDistribution\Download', 'downloaded Windows updates; Disk Cleanup > Windows Update Cleanup'),
    @('C:\ProgramData\Microsoft\Windows\WER', 'error reports'),
    @("$env:LOCALAPPDATA\CrashDumps", 'app crash dumps'),
    @("$env:LOCALAPPDATA\Temp", 'temp files'),
    @('C:\Windows\Temp', 'system temp files (admin)'))) {
  if (Test-Path $x[0]) { "SYSTEM`t{0}`t{1}`t{2}" -f $x[0], (DirGB $x[0]), $x[1] }
}
foreach ($d in $drives) { $rb = "$($d.DeviceID)\`$Recycle.Bin"; if (Test-Path $rb) { "SYSTEM`t{0}`t{1}`tRecycle Bin; only the user should empty it" -f $rb, (DirGB $rb) } }
$hib = Get-Item 'C:\hiberfil.sys' -Force; if ($hib) { "SYSTEM`tC:\hiberfil.sys`t{0:N1}`thibernation file; 'powercfg /h off' removes it but disables hibernate/fast startup" -f ($hib.Length / 1GB) }

"[INSTALLERS]`tPath`tMB`tModified"
$cut = (Get-Date).AddDays(-$InstallerDays)
foreach ($dir in "$env:USERPROFILE\Downloads", "$env:USERPROFILE\Desktop") {
  Get-ChildItem $dir -File -Force -Include *.exe, *.msi, *.msix, *.appx, *.iso, *.img, *.zip, *.rar, *.7z, *.tar, *.gz -Recurse -Depth 1 |
    Where-Object { $_.LastWriteTime -lt $cut -and $_.Length -ge 1MB } | Sort-Object Length -Descending | ForEach-Object {
      "INSTALLER`t{0}`t{1:N0}`t{2:yyyy-MM-dd}" -f $_.FullName, ($_.Length / 1MB), $_.LastWriteTime }
}

# Large files: everything except Windows, program folders, game libraries and package stores (those are handled by the app scan)
$skip = @('*\Windows', '*\Windows\*', '*\Program Files', '*\Program Files (x86)', '*\ProgramData', '*\$Recycle.Bin', '*\System Volume Information',
          '*\Windows.old', '*\$Windows.~*', '*\SteamLibrary', '*\steamapps', '*\Epic Games', '*\Riot Games', '*\AppData\Local\Packages',
          '*\AppData\Local\Microsoft\WindowsApps', '*\AppData\Local\Temp\claude')
$large = foreach ($d in $drives) { Get-Files "$($d.DeviceID)\" ($MinMB * 1MB) $skip }
$large = $large | Where-Object { $_.Name -notin 'pagefile.sys', 'swapfile.sys', 'hiberfil.sys', 'DumpStack.log.tmp' } | Sort-Object Length -Descending
"[LARGE]`tPath`tMB`tModified`tLastAccess"
$large | Select-Object -First $Top | ForEach-Object { "LARGE`t{0}`t{1:N0}`t{2:yyyy-MM-dd}`t{3:yyyy-MM-dd}" -f $_.FullName, ($_.Length / 1MB), $_.LastWriteTime, $_.LastAccessTime }

# Duplicates among large files: same size first, then full hash only for those
"[DUPLICATES]`tHash`tMB`tPath"
$large | Group-Object Length | Where-Object Count -gt 1 | ForEach-Object {
  $_.Group | ForEach-Object { [pscustomobject]@{ F = $_; H = (Get-FileHash $_.FullName -Algorithm SHA256).Hash } } |
    Group-Object H | Where-Object Count -gt 1 | ForEach-Object {
      $h = $_.Name.Substring(0, 12); $_.Group | ForEach-Object { "DUP`t{0}`t{1:N0}`t{2}" -f $h, ($_.F.Length / 1MB), $_.F.FullName } }
}
