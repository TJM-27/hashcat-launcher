@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
if exist "%SCRIPT_DIR%Hashcat Launcher.exe" (
    start "" "%SCRIPT_DIR%Hashcat Launcher.exe"
) else (
    start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%SCRIPT_DIR%hashcat_gui.ps1"
)
endlocal
