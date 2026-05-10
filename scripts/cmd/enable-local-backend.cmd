@echo off
setlocal EnableExtensions
cd /d "%~dp0..\.."
powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\set-local-backend.ps1" -Enabled true
if errorlevel 1 exit /b 1
call scripts\cmd\build-source.cmd
if errorlevel 1 exit /b 1
echo.
echo Local backend enabled. Start it from lx-source-gateway.cmd option 6 before using LX Music.
set "STATUS=%ERRORLEVEL%"
endlocal & exit /b %STATUS%
