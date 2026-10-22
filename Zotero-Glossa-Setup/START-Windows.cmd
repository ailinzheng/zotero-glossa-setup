@echo off
setlocal
chcp 65001 >nul
title Zotero Glossa Setup
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-Windows.ps1"
set "setup_result=%errorlevel%"
echo.
pause
exit /b %setup_result%
