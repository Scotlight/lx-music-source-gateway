param(
  [ValidateSet('true', 'false')]
  [string]$Enabled = 'true'
)

$ErrorActionPreference = 'Stop'
$Root = Resolve-Path (Join-Path $PSScriptRoot '..')
$ConfigPath = Join-Path $Root 'config\local.json'

if (-not (Test-Path -LiteralPath $ConfigPath)) {
  throw 'Missing config/local.json. Run lx-source-gateway.cmd first.'
}

$config = (Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8).TrimStart([char]0xFEFF) | ConvertFrom-Json
if ($null -eq $config.localBackend) {
  $config | Add-Member -NotePropertyName localBackend -NotePropertyValue ([pscustomobject]@{})
}
$config.localBackend | Add-Member -Force -NotePropertyName enabled -NotePropertyValue ([bool]::Parse($Enabled))
$config.localBackend | Add-Member -Force -NotePropertyName baseUrl -NotePropertyValue 'http://127.0.0.1:47632'
$config.localBackend | Add-Member -Force -NotePropertyName matchFallback -NotePropertyValue ([bool]::Parse($Enabled))
$config.localBackend | Add-Member -Force -NotePropertyName defaultMatchPlatform -NotePropertyValue 'kuwo'
$config.localBackend | Add-Member -Force -NotePropertyName searchLimit -NotePropertyValue 10

$json = $config | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText($ConfigPath, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
Write-Host "Updated: $ConfigPath"
