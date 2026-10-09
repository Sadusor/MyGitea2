@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0MyGitea-Control.ps1" -Action Stop
endlocal
