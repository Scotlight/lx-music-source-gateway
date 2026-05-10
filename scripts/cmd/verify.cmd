@echo off
setlocal
cd /d "%~dp0..\.."
where node >nul 2>nul
if errorlevel 1 (
  echo verify requires Node.js. lx-source-gateway.cmd can configure and build without Node.js.
  exit /b 1
)
node scripts\verify.mjs
set "STATUS=%ERRORLEVEL%"
endlocal & exit /b %STATUS%
