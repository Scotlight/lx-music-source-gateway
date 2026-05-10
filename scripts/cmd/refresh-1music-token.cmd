@echo off
setlocal EnableExtensions
cd /d "%~dp0..\.."
powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\refresh-1music-token.ps1"
if errorlevel 1 exit /b 1
call scripts\cmd\build-source.cmd
if errorlevel 1 exit /b 1
echo.
echo 1Music token refreshed. Start local backend from lx-source-gateway.cmd option 6 before using LX Music.
set "STATUS=%ERRORLEVEL%"
endlocal & exit /b %STATUS%
