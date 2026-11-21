# Builds Hashcat Launcher.exe next to this script.
# The exe uses Windows PowerShell and .NET Framework, which are already part of Windows 10 and 11.
# Keep the exe in this folder so it can find hashcat-6.2.5 and icons.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$here = Split-Path -Parent $PSCommandPath
$inputFile = Join-Path $here "hashcat_gui.ps1"
$sourceFile = Join-Path $here "HashcatLauncher.cs"
$outputFile = Join-Path $here "Hashcat Launcher.exe"
$iconFile = Join-Path $here "icons\hashcat_gui_cat_icon.ico"

if (-not (Test-Path -LiteralPath $inputFile)) {
    throw "Cannot find $inputFile"
}
if (-not (Test-Path -LiteralPath $sourceFile)) {
    throw "Cannot find $sourceFile"
}
if (-not (Test-Path -LiteralPath $iconFile)) {
    throw "Cannot find $iconFile"
}

if (Test-Path -LiteralPath $outputFile) {
    Remove-Item -LiteralPath $outputFile -Force
}

Add-Type -AssemblyName Microsoft.CSharp

$provider = New-Object Microsoft.CSharp.CSharpCodeProvider
$parameters = New-Object System.CodeDom.Compiler.CompilerParameters
$parameters.GenerateExecutable = $true
$parameters.OutputAssembly = $outputFile
$parameters.CompilerOptions = "/target:winexe /platform:anycpu /win32icon:`"$iconFile`""
[void]$parameters.ReferencedAssemblies.Add("System.dll")
[void]$parameters.ReferencedAssemblies.Add("System.Windows.Forms.dll")

$source = Get-Content -LiteralPath $sourceFile -Raw
$result = $provider.CompileAssemblyFromSource($parameters, $source)
if ($result.Errors.HasErrors) {
    foreach ($errorItem in $result.Errors) {
        Write-Error ("{0}({1},{2}): {3}" -f $errorItem.FileName, $errorItem.Line, $errorItem.Column, $errorItem.ErrorText)
    }
    exit 1
}

Write-Host "Built $outputFile"
