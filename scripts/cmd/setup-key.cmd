@echo off
setlocal EnableExtensions
cd /d "%~dp0..\.."

set "DEFAULT_BASE=https://gateway.karpov.cn"

echo LX Music source gateway setup
echo.
set /p BASE_URL=Gateway URL, press Enter for %DEFAULT_BASE%: 
if "%BASE_URL%"=="" set "BASE_URL=%DEFAULT_BASE%"
set /p API_KEY=Input your API Key: 
if "%API_KEY%"=="" (
  echo API Key cannot be empty.
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\write-local-config.ps1"
if errorlevel 1 exit /b 1

call scripts\cmd\build-source.cmd
if errorlevel 1 exit /b 1

echo.
echo LX import file: dist\karpov-lx-source.user.js
set "STATUS=%ERRORLEVEL%"
endlocal & exit /b %STATUS%
