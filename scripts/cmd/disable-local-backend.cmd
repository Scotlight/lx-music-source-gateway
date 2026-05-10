@echo off
setlocal EnableExtensions
cd /d "%~dp0..\.."
powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\set-local-backend.ps1" -Enabled false
if errorlevel 1 exit /b 1
call scripts\cmd\build-source.cmd
set "STATUS=%ERRORLEVEL%"
endlocal & exit /b %STATUS%
