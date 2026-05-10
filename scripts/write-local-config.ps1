param()

$ErrorActionPreference = 'Stop'
$Root = Resolve-Path (Join-Path $PSScriptRoot '..')
$ConfigDir = Join-Path $Root 'config'
$ConfigPath = Join-Path $ConfigDir 'local.json'

$baseUrl = $env:BASE_URL
$apiKey = $env:API_KEY

if ([string]::IsNullOrWhiteSpace($baseUrl)) { throw 'BASE_URL is empty.' }
if ([string]::IsNullOrWhiteSpace($apiKey)) { throw 'API_KEY is empty.' }

New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null
$config = [ordered]@{
  baseUrl = $baseUrl
  apiKey = $apiKey
  gdstudio = [ordered]@{
    enabled = $true
    baseUrl = 'https://music-api.gdstudio.xyz/api.php'
  }
  localBackend = [ordered]@{
    enabled = $false
    baseUrl = 'http://127.0.0.1:47632'
    matchFallback = $false
    defaultMatchPlatform = 'kuwo'
    searchLimit = 10
    cookies = [ordered]@{}
  }
  yaohud = [ordered]@{
    enabled = $false
    apiBaseUrl = 'https://api.yaohud.cn'
    key = ''
    kugouCookie = ''
    defaultQuality = 'flac'
    qualities = [ordered]@{
      tx = '320'
      kw = 'lossless'
      kg = 'flac'
    }
    cookies = [ordered]@{
      tx = ''
      kg = ''
    }
  }
  oneMusic = [ordered]@{
    enabled = $false
    siteUrl = 'https://1music.cc'
    apiBaseUrl = 'https://api.1music.cc'
    backendBaseUrl = 'https://backend.1music.cc'
    turnstileToken = ''
    requestFormat = 'webm'
  }
  enableProbe = $true
  strictMatch = $true
  sources = [ordered]@{
    tx = $true
    wy = $true
    kw = $true
    kg = $false
  }
}
$json = $config | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText($ConfigPath, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
Write-Host "Wrote: $ConfigPath"
Write-Host 'Warning: this file contains your API Key and is ignored by git.'
