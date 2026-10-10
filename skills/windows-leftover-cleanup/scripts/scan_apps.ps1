<#
  Read-only inventory of installed software, to help find apps the user no longer needs. Removes nothing.
  Prints tab-separated sections:
    [PROGRAMS]  Name  Version  MB  Installed  Publisher  Flag  UninstallString
    [STORE]     Name  Removable  Flag
    [GAMES]     Store  Name  GB  LastPlayed  Path
    [STARTUP]   Key  Name  TargetExists  Command
  Flag is a hint for Claude, never a verdict:
    VS-LEFTOVER      Visual Studio component while Visual Studio itself is not installed
    OLD-PATCH        older patch of a .NET runtime whose newer patch (same major.minor) is installed
    TELEMETRY        exists only to send usage data
    WRONG-OS         Windows 10 tool on Windows 11
    LAUNCHER-NO-GAME game launcher with no game of that store found
    OPTIONAL-INBOX   built-in Store app many people never use
  Usage: powershell -NoProfile -ExecutionPolicy Bypass -File scan_apps.ps1
#>
$ErrorActionPreference = 'SilentlyContinue'
$uninst = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
          'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
          'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
$all = Get-ItemProperty $uninst | Where-Object DisplayName
$visible = $all | Where-Object { -not $_.SystemComponent -and -not $_.ParentKeyName } | Sort-Object DisplayName -Unique
$isWin11 = [int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuild -ge 22000
$vsInstalled = [bool](Get-ChildItem 'C:\Program Files\Microsoft Visual Studio', 'C:\Program Files (x86)\Microsoft Visual Studio' -Directory |
  Where-Object { $_.Name -match '^(20\d\d|1[5-9])$' } | Get-ChildItem -Directory | Where-Object { Test-Path "$($_.FullName)\Common7\IDE\devenv.exe" })

# Newest installed patch per .NET product + major.minor
$dotnet = @{}
foreach ($a in $all) {
  if ($a.DisplayName -match '^(Microsoft (?:Windows Desktop Runtime|\.NET Runtime|ASP\.NET Core)).*?(\d+)\.(\d+)\.(\d+).*?\((x64|x86)\)') {
    $k = "$($Matches[1])|$($Matches[2]).$($Matches[3])|$($Matches[5])"; $patch = [int]$Matches[4]
    if (-not $dotnet.ContainsKey($k) -or $dotnet[$k] -lt $patch) { $dotnet[$k] = $patch }
  }
}

# Games per store
$games = New-Object System.Collections.Generic.List[object]
$steamLibs = @('C:\Program Files (x86)\Steam\steamapps')
$lf = 'C:\Program Files (x86)\Steam\steamapps\libraryfolders.vdf'
if (Test-Path $lf) { [regex]::Matches((Get-Content $lf -Raw), '"path"\s+"([^"]+)"') | ForEach-Object { $steamLibs += ($_.Groups[1].Value -replace '\\\\', '\') + '\steamapps' } }
foreach ($lib in ($steamLibs | Sort-Object -Unique)) {
  Get-ChildItem $lib -Filter appmanifest_*.acf | ForEach-Object {
    $t = Get-Content $_.FullName -Raw -Encoding UTF8
    $lp = [long][regex]::Match($t, '"LastPlayed"\s+"(\d+)"').Groups[1].Value
    $games.Add([pscustomobject]@{Store='Steam'; Name=[regex]::Match($t, '"name"\s+"([^"]+)"').Groups[1].Value
      GB=[math]::Round([double][regex]::Match($t, '"SizeOnDisk"\s+"(\d+)"').Groups[1].Value / 1GB, 1)
      LastPlayed=$(if ($lp) { [DateTimeOffset]::FromUnixTimeSeconds($lp).ToString('yyyy-MM-dd') } else { 'never' })
      Path="$lib\common\" + [regex]::Match($t, '"installdir"\s+"([^"]+)"').Groups[1].Value })
  }
}
Get-ChildItem "$env:ProgramData\Epic\EpicGamesLauncher\Data\Manifests" -Filter *.item | ForEach-Object {
  $m = Get-Content $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
  if ($m.InstallLocation -and (Test-Path $m.InstallLocation)) {
    $games.Add([pscustomobject]@{Store='Epic'; Name=$m.DisplayName; GB=[math]::Round($m.InstallSize / 1GB, 1); LastPlayed='unknown'; Path=$m.InstallLocation })
  }
}
foreach ($a in $visible | Where-Object { $_.Publisher -match 'Riot Games' -and $_.DisplayName -notmatch 'Client|Vanguard' -and $_.EstimatedSize }) {
  $games.Add([pscustomobject]@{Store='Riot'; Name=$a.DisplayName; GB=[math]::Round($a.EstimatedSize / 1MB, 1); LastPlayed='unknown'; Path=$a.InstallLocation })
}
$eaGames = @(Get-ChildItem 'C:\Program Files\EA Games', 'C:\Program Files (x86)\Origin Games' -Directory)
$rockstarGames = $games | Where-Object { $_.Name -match 'Red Dead|Grand Theft|GTA|Max Payne|Bully|L\.A\. Noire' }

"[PROGRAMS]`tName`tVersion`tMB`tInstalled`tPublisher`tFlag`tUninstallString"
foreach ($a in $visible) {
  $n = $a.DisplayName; $flag = ''
  if (-not $vsInstalled -and $n -match '^(IIS 10\.0 Express|Microsoft SQL Server \d+ LocalDB|Microsoft Web Deploy|vs_|Microsoft Visual Studio Installer|IIS Express Application Compatibility)') { $flag = 'VS-LEFTOVER' }
  elseif ($n -match '^(Microsoft (?:Windows Desktop Runtime|\.NET Runtime|ASP\.NET Core)).*?(\d+)\.(\d+)\.(\d+).*?\((x64|x86)\)') {
    $k = "$($Matches[1])|$($Matches[2]).$($Matches[3])|$($Matches[5])"
    if ([int]$Matches[4] -lt $dotnet[$k]) { $flag = "OLD-PATCH (newer: $($Matches[2]).$($Matches[3]).$($dotnet[$k]))" }
  }
  elseif ($n -match 'Computing Improvement Program|Telemetry|Customer Experience|Usage Data') { $flag = 'TELEMETRY' }
  elseif ($isWin11 -and $n -match 'Update for Windows 10|Windows 10 Update Assistant|Windows PC Health Check') { $flag = 'WRONG-OS' }
  elseif ($n -match '^EA app$|^Origin$' -and $eaGames.Count -eq 0) { $flag = 'LAUNCHER-NO-GAME' }
  elseif ($n -match '^Rockstar Games Launcher$' -and -not $rockstarGames) { $flag = 'LAUNCHER-NO-GAME' }
  elseif ($n -match '^Epic Games Launcher$' -and -not ($games | Where-Object Store -eq 'Epic')) { $flag = 'LAUNCHER-NO-GAME' }
  $mb = [math]::Round($a.EstimatedSize / 1024, 0)
  "PROGRAM`t{0}`t{1}`t{2}`t{3}`t{4}`t{5}`t{6}" -f $n, $a.DisplayVersion, $mb, $a.InstallDate, $a.Publisher, $flag, $(if ($a.QuietUninstallString) { $a.QuietUninstallString } else { $a.UninstallString })
}

"[STORE]`tName`tRemovable`tFlag"
$optional = 'MixedReality\.Portal|Windows\.DevHome|windowscommunicationsapps|ZuneVideo|GetHelp|BingNews|BingWeather|Getstarted|MicrosoftSolitaireCollection|People|SkypeApp|Microsoft3DViewer|Print3D|MicrosoftOfficeHub|Clipchamp|Todos|PowerAutomateDesktop|549981C3F5F10|WindowsFeedbackHub|QuickAssist'
Get-AppxPackage | Where-Object { -not $_.IsFramework -and $_.SignatureKind -ne 'System' } | Sort-Object Name -Unique | ForEach-Object {
  "STORE`t{0}`t{1}`t{2}" -f $_.Name, (-not $_.NonRemovable), $(if ($_.Name -match $optional) { 'OPTIONAL-INBOX' } else { '' })
}

"[GAMES]`tStore`tName`tGB`tLastPlayed`tPath"
$games | Sort-Object GB -Descending | ForEach-Object { "GAME`t{0}`t{1}`t{2}`t{3}`t{4}" -f $_.Store, $_.Name, $_.GB, $_.LastPlayed, $_.Path }

"[STARTUP]`tKey`tName`tTargetExists`tCommand"
foreach ($k in 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run') {
  (Get-ItemProperty $k).PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object {
    $cmd = [string]$_.Value
    $exe = [Environment]::ExpandEnvironmentVariables($(if ($cmd -match '^"([^"]+)"') { $Matches[1] } else { ($cmd -split ' (?=-|/)')[0] }))
    "STARTUP`t{0}`t{1}`t{2}`t{3}" -f $k, $_.Name, (Test-Path $exe), $cmd
  }
}
