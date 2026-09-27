# Zips a Windows release build into something a person can unzip and run.
#
#   ./tool/package_windows.ps1 -Name vanguard-simulator-v1.0.0-windows-x64
#
# Flutter leaves the app as a folder: the .exe, the Flutter DLL, the plugin
# DLLs and a data folder, all of which have to travel together. This copies
# that folder, adds the Visual C++ runtime DLLs and a readme, and zips it.
param([Parameter(Mandatory = $true)][string]$Name)

$ErrorActionPreference = 'Stop'

$built = 'build/windows/x64/runner/Release'
if (-not (Test-Path "$built/vanguard_simulator.exe")) {
  throw "No build at $built -- run 'flutter build windows --release' first."
}

$staged = "dist/$Name"
New-Item -ItemType Directory -Force -Path $staged | Out-Null
Copy-Item -Path "$built/*" -Destination $staged -Recurse -Force

# The Visual C++ runtime, which a Flutter app needs and a clean install of
# Windows may not have. Copied in where the build machine has a copy, so the
# app runs without asking anyone to install anything; skipped where it does
# not, since most machines already carry it.
$crt = Get-ChildItem -Path 'C:\Program Files*\Microsoft Visual Studio\*\*\VC\Redist\MSVC\*\x64\Microsoft.VC*.CRT' `
  -Directory -ErrorAction SilentlyContinue | Select-Object -Last 1
if ($crt) {
  foreach ($dll in 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') {
    $from = Join-Path $crt.FullName $dll
    if (Test-Path $from) { Copy-Item $from -Destination $staged -Force }
  }
  Write-Host "bundled the Visual C++ runtime from $($crt.FullName)"
} else {
  Write-Host 'no Visual C++ redistributable on this machine; not bundled'
}

Copy-Item 'tool/windows_readme.txt' -Destination "$staged/READ ME FIRST.txt" -Force

$zip = "dist/$Name.zip"
if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive -Path $staged -DestinationPath $zip
Write-Host "wrote $zip"
Get-Item $zip | Select-Object Name, Length
