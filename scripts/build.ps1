param()

$ErrorActionPreference = 'Stop'
$Root = Resolve-Path (Join-Path $PSScriptRoot '..')
$ConfigPath = Join-Path $Root 'config\local.json'
$TemplatePath = Join-Path $Root 'src\karpov-lx-source.user.template.js'
$OutputDir = Join-Path $Root 'dist'
$OutputPath = Join-Path $OutputDir 'karpov-lx-source.user.js'
$DefaultGdstudioBaseUrl = 'https://music-api.gdstudio.xyz/api.php'
$DefaultLocalBackendBaseUrl = 'http://127.0.0.1:47632'
$DefaultOneMusicSiteUrl = 'https://1music.cc'
$DefaultOneMusicApiBaseUrl = 'https://api.1music.cc'
$DefaultOneMusicBackendBaseUrl = 'https://backend.1music.cc'
$DefaultYaohudApiBaseUrl = 'https://api.yaohud.cn'

function ConvertTo-JsSingleQuotedContent {
  param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)
  return $Value.Replace('\', '\\').Replace("'", "\'").Replace("`r", '\r').Replace("`n", '\n')
}

function Get-OptionalBoolean {
  param($Object, [string]$Name, [bool]$DefaultValue)
  if ($null -eq $Object) { return $DefaultValue }
  $prop = $Object.PSObject.Properties[$Name]
  if ($null -eq $prop) { return $DefaultValue }
  return [bool]$prop.Value
}

if (-not (Test-Path -LiteralPath $ConfigPath)) {
  throw 'Missing config/local.json. Run lx-source-gateway.cmd first, or copy config/local.example.json and edit it manually.'
}

$config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $config.baseUrl -or [string]$config.baseUrl -notmatch '^https?://') {
  throw 'config/local.json: baseUrl must be an http(s) URL.'
}
if (-not $config.apiKey -or [string]$config.apiKey -match 'API Key|请在这里填入') {
  throw 'config/local.json: apiKey is empty.'
}

$gdstudioEnabled = $true
$gdstudioBaseUrl = $DefaultGdstudioBaseUrl
if ($null -ne $config.gdstudio) {
  $gdstudioEnabled = Get-OptionalBoolean $config.gdstudio 'enabled' $true
  if (-not [string]::IsNullOrWhiteSpace([string]$config.gdstudio.baseUrl)) {
    $gdstudioBaseUrl = [string]$config.gdstudio.baseUrl
  }
}
if ($gdstudioEnabled -and $gdstudioBaseUrl -notmatch '^https?://') {
  throw 'config/local.json: gdstudio.baseUrl must be an http(s) URL.'
}

$localBackendEnabled = $false
$localBackendBaseUrl = $DefaultLocalBackendBaseUrl
$localBackendMatchFallback = $false
if ($null -ne $config.localBackend) {
  $localBackendEnabled = Get-OptionalBoolean $config.localBackend 'enabled' $false
  $localBackendMatchFallback = Get-OptionalBoolean $config.localBackend 'matchFallback' $false
  if (-not [string]::IsNullOrWhiteSpace([string]$config.localBackend.baseUrl)) {
    $localBackendBaseUrl = [string]$config.localBackend.baseUrl
  }
}
if ($localBackendEnabled -and $localBackendBaseUrl -notmatch '^https?://') {
  throw 'config/local.json: localBackend.baseUrl must be an http(s) URL.'
}

$yaohudEnabled = $false
$yaohudApiBaseUrl = $DefaultYaohudApiBaseUrl
$yaohudQualities = [ordered]@{}
if ($null -ne $config.yaohud) {
  $yaohudEnabled = Get-OptionalBoolean $config.yaohud 'enabled' $false
  if (-not [string]::IsNullOrWhiteSpace([string]$config.yaohud.apiBaseUrl)) { $yaohudApiBaseUrl = [string]$config.yaohud.apiBaseUrl }
  if ($null -ne $config.yaohud.qualities) {
    foreach ($prop in $config.yaohud.qualities.PSObject.Properties) {
      $yaohudQualities[$prop.Name] = [string]$prop.Value
    }
  }
}
if ($yaohudEnabled -and $yaohudApiBaseUrl -notmatch '^https?://') {
  throw 'config/local.json: yaohud.apiBaseUrl must be an http(s) URL.'
}

$oneMusicEnabled = $false
$oneMusicSiteUrl = $DefaultOneMusicSiteUrl
$oneMusicApiBaseUrl = $DefaultOneMusicApiBaseUrl
$oneMusicBackendBaseUrl = $DefaultOneMusicBackendBaseUrl
$oneMusicRequestFormat = 'webm'
if ($null -ne $config.oneMusic) {
  $oneMusicEnabled = Get-OptionalBoolean $config.oneMusic 'enabled' $false
  if (-not [string]::IsNullOrWhiteSpace([string]$config.oneMusic.siteUrl)) { $oneMusicSiteUrl = [string]$config.oneMusic.siteUrl }
  if (-not [string]::IsNullOrWhiteSpace([string]$config.oneMusic.apiBaseUrl)) { $oneMusicApiBaseUrl = [string]$config.oneMusic.apiBaseUrl }
  if (-not [string]::IsNullOrWhiteSpace([string]$config.oneMusic.backendBaseUrl)) { $oneMusicBackendBaseUrl = [string]$config.oneMusic.backendBaseUrl }
  if (-not [string]::IsNullOrWhiteSpace([string]$config.oneMusic.requestFormat)) { $oneMusicRequestFormat = [string]$config.oneMusic.requestFormat }
}
if ($oneMusicEnabled -and ($oneMusicSiteUrl -notmatch '^https?://' -or $oneMusicApiBaseUrl -notmatch '^https?://' -or $oneMusicBackendBaseUrl -notmatch '^https?://')) {
  throw 'config/local.json: oneMusic URLs must be http(s) URLs.'
}

$txEnabled = Get-OptionalBoolean $config.sources 'tx' $true
$wyEnabled = Get-OptionalBoolean $config.sources 'wy' $true
$kwEnabled = Get-OptionalBoolean $config.sources 'kw' $true
$kgEnabled = Get-OptionalBoolean $config.sources 'kg' $false
$mgEnabled = Get-OptionalBoolean $config.sources 'mg' $false

$sourcesJson = ([ordered]@{ tx = $txEnabled; wy = $wyEnabled; kw = $kwEnabled; kg = $kgEnabled; mg = $mgEnabled } | ConvertTo-Json -Compress)
$localBackendJson = ([ordered]@{ enabled = $localBackendEnabled; baseUrl = $localBackendBaseUrl; matchFallback = $localBackendMatchFallback } | ConvertTo-Json -Compress)
$gdstudioJson = ([ordered]@{ enabled = $gdstudioEnabled; baseUrl = $gdstudioBaseUrl } | ConvertTo-Json -Compress)
$oneMusicJson = ([ordered]@{ enabled = $oneMusicEnabled; siteUrl = $oneMusicSiteUrl; apiBaseUrl = $oneMusicApiBaseUrl; backendBaseUrl = $oneMusicBackendBaseUrl; requestFormat = $oneMusicRequestFormat } | ConvertTo-Json -Compress)
$yaohudJson = ([ordered]@{ enabled = $yaohudEnabled; apiBaseUrl = $yaohudApiBaseUrl; qualities = $yaohudQualities } | ConvertTo-Json -Compress)
$enableProbe = if ($config.enableProbe -eq $false) { 'false' } else { 'true' }
$strictMatch = if ($config.strictMatch -eq $false) { 'false' } else { 'true' }

$script = Get-Content -LiteralPath $TemplatePath -Raw -Encoding UTF8
$script = $script.Replace('__KARPOV_BASE_URL__', (ConvertTo-JsSingleQuotedContent ([string]$config.baseUrl)))
$script = $script.Replace('__KARPOV_API_KEY__', (ConvertTo-JsSingleQuotedContent ([string]$config.apiKey)))
$script = $script.Replace('__GDSTUDIO_CONFIG__', $gdstudioJson)
$script = $script.Replace('__LOCAL_BACKEND_CONFIG__', $localBackendJson)
$script = $script.Replace('__ONE_MUSIC_CONFIG__', $oneMusicJson)
$script = $script.Replace('__YAOHUD_CONFIG__', $yaohudJson)
$script = $script.Replace('__KARPOV_ENABLE_PROBE__', $enableProbe)
$script = $script.Replace('__KARPOV_STRICT_MATCH__', $strictMatch)
$script = $script.Replace('__KARPOV_SOURCES__', $sourcesJson)

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
[System.IO.File]::WriteAllText($OutputPath, $script, [System.Text.UTF8Encoding]::new($false))
Write-Host "Generated: $OutputPath"
Write-Host 'Warning: config/local.json and dist\*.js contain your local API Key and are ignored by git.'
