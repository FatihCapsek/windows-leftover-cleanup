<#
  Read-only scan for leftovers of uninstalled Windows apps. Deletes nothing.
  Output: a tab-separated report (stdout) with one row per candidate folder / entry:
    Category  Path  MB  Modified  Hint
  Categories:
    ORPHAN?   folder whose name matches no installed program, Store app or running process
    INSTALLED folder that matches an installed program (shown only with -ShowInstalled)
    CACHE     well-known cache / temp folder that regenerates by itself
    EMPTY     folder with no files at all
    RUN       startup (Run key) entry whose target exe no longer exists
    SHORTCUT  Start menu / desktop shortcut whose target no longer exists
  Usage: powershell -NoProfile -ExecutionPolicy Bypass -File scan_leftovers.ps1 [-ShowInstalled] [-MinMB 0]
#>
param([switch]$ShowInstalled, [double]$MinMB = 0)

$ErrorActionPreference = 'SilentlyContinue'
$L = $env:LOCALAPPDATA; $R = $env:APPDATA; $LL = "$env:USERPROFILE\AppData\LocalLow"
$roots = @($L, "$L\Programs", $R, $LL, $env:ProgramData, $env:ProgramFiles, ${env:ProgramFiles(x86)})

# Folders that belong to Windows itself or are shared infrastructure; never report them as orphans.
$system = @('Microsoft','Packages','Temp','Programs','Application Data','History','Temporary Internet Files','VirtualStore',
  'Comms','ConnectedDevicesPlatform','D3DSCache','Publishers','PeerDistRepub','PlaceholderTileLogoFolder','Package Cache',
  'ElevatedDiagnostics','INetHistory','ToastNotificationManagerCompat','Common Files','Common','Internet Explorer',
  'Windows Defender','Windows Defender Advanced Threat Protection','Windows Mail','Windows Media Player','Windows NT',
  'Windows Photo Viewer','Windows Sidebar','WindowsApps','WindowsPowerShell','ModifiableWindowsApps','Uninstall Information',
  'Reference Assemblies','dotnet','Microsoft.NET','MSBuild','RUXIM','USOPrivate','USOShared','SoftwareDistribution','ssh',
  'Start Menu','Templates','Desktop','Belgeler','Documents','regid.1991-06.com.microsoft','Microsoft Update Health Tools',
  'Packages','CrashReportClient','SquirrelTemp','Backup','cache','speech','Sentry','Whesvc','WindowsHolographicDevices',
  'Microsoft OneDrive','Microsoft SDKs','Microsoft_Corporation','Microsoft DevDiv','NuGet','Nuget','Unity','Temp','LocalLow',
  'Claude','Claude-3p','Claude-Data','claude-cli-nodejs','.IdentityService','IdentityNexusIntegration','NhNotifSys')

# Cache / temp folders that are safe to clear and regenerate (relative to LOCALAPPDATA unless rooted).
$caches = @("$L\Temp","$L\CrashDumps","$L\npm-cache","$L\pip\cache","$L\ms-playwright","$L\ms-playwright-go","$L\SquirrelTemp",
  "$L\D3DSCache","$L\NVIDIA\DXCache","$L\NVIDIA\GLCache","$env:ProgramData\Package Cache")

# -creplace + ToLowerInvariant: on Turkish Windows a case-insensitive [a-zA-Z] drops 'I' (MSI -> ms).
function Norm($s) { ([string]$s -creplace '[^a-zA-Z0-9]', '').ToLowerInvariant() }
function SizeMB($p) { [math]::Round(((Get-ChildItem $p -Recurse -File -Force | Measure-Object Length -Sum).Sum) / 1MB, 1) }

# ---- Build the "installed" vocabulary ----
$uninst = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
          'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
          'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
$installed = Get-ItemProperty $uninst | Where-Object DisplayName
$vocab = New-Object System.Collections.Generic.List[string]
foreach ($a in $installed) {
  foreach ($v in @($a.DisplayName, $a.Publisher)) { if ($v) { $vocab.Add((Norm $v)) } }
  foreach ($v in @($a.InstallLocation, ($a.UninstallString -replace '"', ''), ($a.DisplayIcon -replace '"|,.*$', ''))) {
    if ($v) { ($v -split '[\\/]') | Where-Object { $_.Length -ge 3 } | ForEach-Object { $vocab.Add((Norm $_)) } }
  }
}
Get-AppxPackage | ForEach-Object { $vocab.Add((Norm $_.Name)); $vocab.Add((Norm $_.Publisher)) }
Get-Process | Where-Object Path | ForEach-Object { ($_.Path -split '\\') | ForEach-Object { $vocab.Add((Norm $_)) } }
Get-CimInstance Win32_Service | Where-Object PathName | ForEach-Object { ($_.PathName -replace '"', '' -split '\\') | ForEach-Object { $vocab.Add((Norm $_)) } }
$vocab = $vocab | Where-Object { $_.Length -ge 3 } | Sort-Object -Unique

function Match($name) {
  $n = Norm ($name -replace '(-updater|updater|-local|launcher)$', '')
  if ($n.Length -lt 3) { return $null }
  foreach ($v in $vocab) { if ($v.Contains($n) -or ($v.Length -ge 4 -and $n.Contains($v))) { return $v } }
  return $null
}

$rows = New-Object System.Collections.Generic.List[object]
function Add($cat, $path, $mb, $mod, $hint) { $rows.Add([pscustomobject]@{Category=$cat; Path=$path; MB=$mb; Modified=$mod; Hint=$hint}) }

# ---- Folders ----
foreach ($root in $roots) {
  Get-ChildItem $root -Directory -Force | ForEach-Object {
    $p = $_.FullName; $name = $_.Name
    if ($root -eq $L -and $name -eq 'Programs') { return }
    $mod = $_.LastWriteTime.ToString('yyyy-MM-dd')
    if ($caches -contains $p) { Add 'CACHE' $p (SizeMB $p) $mod 'cache/temp - regenerates'; return }
    if ($system -contains $name) { return }
    $hasFile = Get-ChildItem $p -Recurse -File -Force | Select-Object -First 1
    if (-not $hasFile) { Add 'EMPTY' $p 0 $mod 'no files'; return }
    $mb = SizeMB $p
    $m = Match $name
    if ($m) { if ($ShowInstalled) { Add 'INSTALLED' $p $mb $mod "matches: $m" } }
    elseif ($mb -ge $MinMB) {
      $hint = 'no installed app / process / service matches this name'
      $save = Get-ChildItem $p -Recurse -File -Force -Include *.sav,*.save,*.sl2,*.ess,save*,*savegame*,*.dat | Select-Object -First 1
      if ($root -eq $LL -or $save -or $name -match 'save') { $hint = 'POSSIBLE GAME SAVE/SETTINGS - keep unless user decides' }
      Add 'ORPHAN?' $p $mb $mod $hint
    }
  }
}

# ---- Startup entries pointing at missing executables ----
foreach ($k in 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run','HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run') {
  $props = (Get-ItemProperty $k).PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' }
  foreach ($pr in $props) {
    $cmd = [string]$pr.Value
    $exe = if ($cmd -match '^"([^"]+)"') { $Matches[1] } else { ($cmd -split ' (?=-|/)')[0] }
    $exe = [Environment]::ExpandEnvironmentVariables($exe)
    if ($exe -and -not (Test-Path $exe)) { Add 'RUN' "$k :: $($pr.Name)" 0 '' "target missing: $exe" }
  }
}

# ---- Shortcuts pointing at missing targets ----
$sh = New-Object -ComObject WScript.Shell
foreach ($d in "$R\Microsoft\Windows\Start Menu\Programs", "$env:ProgramData\Microsoft\Windows\Start Menu\Programs", "$env:USERPROFILE\Desktop", "$env:PUBLIC\Desktop") {
  Get-ChildItem $d -Recurse -Filter *.lnk -Force | ForEach-Object {
    $t = $sh.CreateShortcut($_.FullName).TargetPath
    if ($t -and -not (Test-Path $t)) { Add 'SHORTCUT' $_.FullName 0 '' "target missing: $t" }
  }
}

"Category`tPath`tMB`tModified`tHint"
$rows | Sort-Object Category, @{e='MB';Descending=$true} | ForEach-Object {
  "{0}`t{1}`t{2}`t{3}`t{4}" -f $_.Category, $_.Path.Replace($env:USERPROFILE, '~'), $_.MB, $_.Modified, $_.Hint
}
