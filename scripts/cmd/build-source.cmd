@echo off
setlocal
cd /d "%~dp0..\.."
powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\build.ps1"
set "STATUS=%ERRORLEVEL%"
endlocal & exit /b %STATUS%
