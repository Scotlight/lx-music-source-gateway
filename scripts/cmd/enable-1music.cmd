@echo off
setlocal EnableExtensions
cd /d "%~dp0..\.."
echo Paste 1Music cf-turnstile-response token. Leave empty to use existing token.
set /p ONE_MUSIC_TOKEN=Token: 
powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\set-1music.ps1" -Enabled true
if errorlevel 1 exit /b 1
powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\set-local-backend.ps1" -Enabled true
if errorlevel 1 exit /b 1
call scripts\cmd\build-source.cmd
if errorlevel 1 exit /b 1
echo.
echo 1Music enabled. Start local backend from lx-source-gateway.cmd option 6 before using LX Music.
set "STATUS=%ERRORLEVEL%"
endlocal & exit /b %STATUS%
