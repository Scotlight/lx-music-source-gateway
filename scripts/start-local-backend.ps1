param(
  [int]$Port = $(if ($env:LX_SOURCE_GATEWAY_PORT) { [int]$env:LX_SOURCE_GATEWAY_PORT } else { 47632 })
)

$ErrorActionPreference = 'Stop'
$Root = Resolve-Path (Join-Path $PSScriptRoot '..')
$ConfigPath = Join-Path $Root 'config\local.json'
$ServerPath = Join-Path $Root 'server\local-meting-server.mjs'

function Read-Config {
  if (-not (Test-Path -LiteralPath $ConfigPath)) { return $null }
  $raw = (Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8).TrimStart([char]0xFEFF)
  if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
  return $raw | ConvertFrom-Json
}

function Test-Node {
  $cmd = Get-Command node -ErrorAction SilentlyContinue
  return $null -ne $cmd
}

function Test-OneMusicEnabled {
  param($Config)
  return $null -ne $Config -and $null -ne $Config.oneMusic -and $Config.oneMusic.enabled -eq $true
}

function Test-OneMusicTokenReady {
  param($Config)
  return $null -ne $Config -and $null -ne $Config.oneMusic -and -not [string]::IsNullOrWhiteSpace([string]$Config.oneMusic.turnstileToken)
}

if (-not (Test-Node)) {
  Write-Host 'Node.js is required for the optional local backend.' -ForegroundColor Red
  Write-Host 'Install Node.js 18 or newer, then run this file again.' -ForegroundColor Yellow
  Read-Host 'Press Enter to exit' | Out-Null
  exit 1
}

$config = Read-Config
if (Test-OneMusicEnabled $config) {
  Write-Host '1Music.cc 已启用，启动后端前刷新 Turnstile token。' -ForegroundColor Cyan
  try {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'refresh-1music-token.ps1')
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'build.ps1')
    $config = Read-Config
  } catch {
    $config = Read-Config
    if (-not (Test-OneMusicTokenReady $config)) {
      Write-Host $_.Exception.Message -ForegroundColor Red
      Write-Host '1Music 没有可用 token，后端不启动。' -ForegroundColor Red
      Read-Host 'Press Enter to exit' | Out-Null
      exit 1
    }
    Write-Host "1Music token 刷新失败，将继续使用当前 token：$($_.Exception.Message)" -ForegroundColor Yellow
  }
}

$env:LX_SOURCE_GATEWAY_PORT = [string]$Port
Write-Host "Starting LX Music local backend on http://127.0.0.1:$Port" -ForegroundColor Cyan
Write-Host 'Keep this window open while using LX Music.' -ForegroundColor Yellow
Write-Host ''
& node $ServerPath $Port
