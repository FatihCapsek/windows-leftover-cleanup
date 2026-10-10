<#
  Sends approved folders/files to the Recycle Bin (never a permanent delete).
  Input: a UTF-8 text file, one path per line. Prefix a line with "contents:" to recycle
  everything INSIDE that folder but keep the folder (use for Temp, CrashDumps).
  Lines starting with # are ignored.
  If any path needs admin rights (Program Files, ProgramData) and this shell is not elevated,
  the script re-launches itself elevated once (the user sees a UAC prompt) and waits.
  Usage: powershell -NoProfile -ExecutionPolicy Bypass -File recycle.ps1 -ListFile <list.txt> [-LogFile <log.txt>]
#>
param([Parameter(Mandatory)][string]$ListFile, [string]$LogFile = "$ListFile.log", [switch]$Elevated)

Add-Type -AssemblyName Microsoft.VisualBasic
$FS = [Microsoft.VisualBasic.FileIO.FileSystem]
$UI = [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs
$RB = [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin

# Never touch Claude's own working files that live under Temp.
$protect = @('claude')

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$lines = Get-Content $ListFile -Encoding UTF8 | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') }
$lines = $lines | ForEach-Object { [Environment]::ExpandEnvironmentVariables($_) }

$needsAdmin = $lines | Where-Object { ($_ -replace '^contents:', '') -match '^(C:\\Program Files|C:\\ProgramData)' }
if ($needsAdmin -and -not $isAdmin -and -not $Elevated) {
  $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-ListFile', "`"$ListFile`"", '-LogFile', "`"$LogFile`"", '-Elevated')
  Start-Process powershell.exe -Verb RunAs -ArgumentList $argList -Wait
  Get-Content $LogFile -Encoding UTF8
  return
}

function SizeMB($p) { [math]::Round(((Get-ChildItem $p -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum) / 1MB, 1) }
function ErrMsg($e) { if ($e.Exception.InnerException) { $e.Exception.InnerException.Message } else { $e.Exception.Message } }

$out = New-Object System.Collections.Generic.List[string]
$total = 0.0
foreach ($line in $lines) {
  $contentsOnly = $line.StartsWith('contents:')
  $p = $line -replace '^contents:', ''
  if (-not (Test-Path -LiteralPath $p)) { $out.Add("SKIP (not found)`t$p"); continue }
  $before = SizeMB $p
  if ($contentsOnly) {
    $skipped = 0
    Get-ChildItem -LiteralPath $p -Force | Where-Object { $protect -notcontains $_.Name } | ForEach-Object {
      try { if ($_.PSIsContainer) { $FS::DeleteDirectory($_.FullName, $UI, $RB) } else { $FS::DeleteFile($_.FullName, $UI, $RB) } }
      catch { $skipped++ }
    }
    $freed = [math]::Round($before - (SizeMB $p), 1); $total += $freed
    $out.Add("OK`t$p\*`t$freed MB`t$skipped item(s) in use, skipped")
  } else {
    try {
      if ((Get-Item -LiteralPath $p -Force).PSIsContainer) { $FS::DeleteDirectory($p, $UI, $RB) } else { $FS::DeleteFile($p, $UI, $RB) }
      $total += $before; $out.Add("OK`t$p`t$before MB")
    } catch { $out.Add("FAIL`t$p`t$before MB`t$(ErrMsg $_)") }
  }
}
$out.Add("TOTAL`t{0:N1} GB sent to Recycle Bin" -f ($total / 1024))
$out | Set-Content -Encoding UTF8 $LogFile
$out
