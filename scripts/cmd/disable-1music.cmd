@echo off
setlocal EnableExtensions
cd /d "%~dp0..\.."
powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\set-1music.ps1" -Enabled false
if errorlevel 1 exit /b 1
call scripts\cmd\build-source.cmd
if errorlevel 1 exit /b 1
echo.
echo 1Music disabled.
set "STATUS=%ERRORLEVEL%"
endlocal & exit /b %STATUS%
