# Builds Hashcat Launcher.exe next to this script.
# The exe uses Windows PowerShell and .NET Framework, which are already part of Windows 10 and 11.
# Keep the exe in this folder so it can find hashcat-6.2.5 and icons.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$here = Split-Path -Parent $PSCommandPath
$inputFile = Join-Path $here "hashcat_gui.ps1"
$outputFile = Join-Path $here "Hashcat Launcher.exe"
$iconFile = Join-Path $here "icons\hashcat_gui_cat_icon.ico"

if (-not (Test-Path -LiteralPath $inputFile)) {
    throw "Cannot find $inputFile"
}
if (-not (Test-Path -LiteralPath $iconFile)) {
    throw "Cannot find $iconFile"
}

if (-not (Get-Command Invoke-ps2exe -ErrorAction SilentlyContinue)) {
    Write-Host "Installing ps2exe for the current user (build machine only)..."
    if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
    }
    Install-Module ps2exe -Scope CurrentUser -Force -AllowClobber
    Import-Module ps2exe -Force
}

Invoke-ps2exe `
    -inputFile $inputFile `
    -outputFile $outputFile `
    -iconFile $iconFile `
    -noConsole `
    -sta `
    -title "Hashcat launcher" `
    -description "Portable launcher for hashcat" `
    -product "Hashcat launcher" `
    -version "1.0.0.0" `
    -noConfigFile

Write-Host "Built $outputFile"
