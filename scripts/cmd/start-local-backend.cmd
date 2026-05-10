@echo off
setlocal EnableExtensions
chcp 65001 >nul
cd /d "%~dp0..\.."
powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\start-local-backend.ps1"
set "STATUS=%ERRORLEVEL%"
endlocal & exit /b %STATUS%
