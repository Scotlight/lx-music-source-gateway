param(
  [ValidateSet('true', 'false')]
  [string]$Enabled = 'true',
  [string]$Token = $env:ONE_MUSIC_TOKEN
)

$ErrorActionPreference = 'Stop'
$Root = Resolve-Path (Join-Path $PSScriptRoot '..')
$ConfigPath = Join-Path $Root 'config\local.json'

if (-not (Test-Path -LiteralPath $ConfigPath)) {
  throw 'Missing config/local.json. Run lx-source-gateway.cmd first.'
}

$config = (Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8).TrimStart([char]0xFEFF) | ConvertFrom-Json
if ($null -eq $config.oneMusic) {
  $config | Add-Member -NotePropertyName oneMusic -NotePropertyValue ([pscustomobject]@{})
}

$config.oneMusic | Add-Member -Force -NotePropertyName enabled -NotePropertyValue ([bool]::Parse($Enabled))
$config.oneMusic | Add-Member -Force -NotePropertyName siteUrl -NotePropertyValue 'https://1music.cc'
$config.oneMusic | Add-Member -Force -NotePropertyName apiBaseUrl -NotePropertyValue 'https://api.1music.cc'
$config.oneMusic | Add-Member -Force -NotePropertyName backendBaseUrl -NotePropertyValue 'https://backend.1music.cc'
$config.oneMusic | Add-Member -Force -NotePropertyName requestFormat -NotePropertyValue 'webm'

if (-not [string]::IsNullOrWhiteSpace($Token)) {
  $config.oneMusic | Add-Member -Force -NotePropertyName turnstileToken -NotePropertyValue $Token.Trim()
} elseif ($Enabled -eq 'true' -and [string]::IsNullOrWhiteSpace([string]$config.oneMusic.turnstileToken)) {
  throw 'ONE_MUSIC_TOKEN is empty. Run lx-source-gateway.cmd and choose 启用/刷新 1Music, or paste a token into this command.'
}

$json = $config | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText($ConfigPath, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
Write-Host "Updated: $ConfigPath"
