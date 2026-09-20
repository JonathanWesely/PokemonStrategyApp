<#
.SYNOPSIS
  Pull the app's last scan diagnostics off the emulator/phone into
  test\_scan_dump\live\ so a scan can be analysed off-device.

.DESCRIPTION
  Debug builds write every local team-preview scan to the app's private
  documents dir (app_flutter\last_scan): frame.jpg, overlay.jpg, panel_N.png,
  report.txt. That directory is inside the app sandbox, so it can only be read
  through `run-as`, and `run-as ... cp /sdcard/Download` is denied on this
  emulator image — hence the base64 tar pipe, which is the one route that
  works without root.

  Each scan OVERWRITES last_scan, so: scan once, pull, then scan again.

  Every pull is ALSO copied to test\_scan_dump\archive\<timestamp>\ (frame,
  overlay, report), so rig frames accumulate into a real test set instead of
  being overwritten by the next pull. Pass -Truth with the six enemy Pokemon
  top to bottom (display names as in pokemon2Dsprites\manifest.json) and it
  is saved beside them as truth.txt - that is what makes a frame usable for
  measuring the recognizer.

.EXAMPLE
  .\tool\pull_scan.ps1
  .\tool\pull_scan.ps1 -Serial emulator-5554 -Dest test\_scan_dump\run2
  .\tool\pull_scan.ps1 -Truth "Charizard,Venusaur,Kleavor,Drampa,Dragonite,Ceruledge"
#>
param(
  [string]$Serial,
  [string]$Dest = "test\_scan_dump\live",
  [string]$AppId = "com.jonwes.pokemon_strategy_app",
  [string]$Truth,
  [string]$Archive = "test\_scan_dump\archive"
)
$ErrorActionPreference = 'Stop'

# --- adb -------------------------------------------------------------------
$adb = (Get-Command adb -ErrorAction SilentlyContinue).Source
if (-not $adb) { $adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" }
if (-not (Test-Path $adb)) {
  throw "adb not found. Install Android platform-tools, or set `$adb by hand."
}
$adbArgs = @()
if ($Serial) { $adbArgs += @('-s', $Serial) }

$devices = @(& $adb devices | Select-Object -Skip 1 |
             Where-Object { $_ -match '\sdevice$' })
if ($devices.Count -eq 0) { throw "No device/emulator attached (adb devices is empty)." }
if ($devices.Count -gt 1 -and -not $Serial) {
  throw ("More than one device attached; re-run with -Serial <name>:`n  " +
         ($devices -join "`n  "))
}

# --- pull ------------------------------------------------------------------
Write-Host "pulling app_flutter/last_scan from $AppId ..."
$b64 = & $adb @adbArgs exec-out "run-as $AppId tar -cf - app_flutter/last_scan 2>/dev/null | base64"
$joined = ($b64 -join '').Trim()
if (-not $joined) {
  throw ("Nothing came back. Either the app has not scanned yet (the debug " +
         "writer only runs on a local team-preview scan in a DEBUG build), " +
         "or $AppId is not installed on this device.")
}
$tar = Join-Path $env:TEMP "last_scan.tar"
[IO.File]::WriteAllBytes($tar, [Convert]::FromBase64String($joined))

# --- extract ---------------------------------------------------------------
# Wipe first: a stale panel_6.png from a previous 6-panel scan silently
# survives a 5-panel one and gets analysed as if it were current.
if (Test-Path $Dest) { Remove-Item $Dest -Recurse -Force }
New-Item -ItemType Directory -Path $Dest -Force | Out-Null
& tar -xf $tar --strip-components=2 -C $Dest
Remove-Item $tar -Force

$files = @(Get-ChildItem $Dest -File)
Write-Host ("extracted {0} files to {1}" -f $files.Count, (Resolve-Path $Dest))

# --- archive ---------------------------------------------------------------
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$keep = Join-Path $Archive $stamp
New-Item -ItemType Directory -Path $keep -Force | Out-Null
foreach ($f in 'frame.jpg', 'overlay.jpg', 'report.txt') {
  $src = Join-Path $Dest $f
  if (Test-Path $src) { Copy-Item $src $keep }
}
if ($Truth) {
  $names = @($Truth -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  if ($names.Count -ne 6) {
    Write-Warning ("-Truth has {0} names, expected 6 (top to bottom)" -f $names.Count)
  }
  Set-Content -Path (Join-Path $keep 'truth.txt') -Value ($names -join ',')
}
Write-Host ("archived to {0}{1}" -f (Resolve-Path $keep),
            $(if ($Truth) { ' (with truth.txt)' } else { ' (no -Truth given)' }))
$report = Join-Path $Dest 'report.txt'
if (Test-Path $report) {
  Write-Host ""
  Get-Content $report
} else {
  Write-Warning "no report.txt in the dump - is this a debug build?"
}
