param(
  [switch]$StatusOnly
)

$ErrorActionPreference = 'Stop'
$Root = Resolve-Path (Join-Path $PSScriptRoot '..')
$ConfigDir = Join-Path $Root 'config'
$ConfigPath = Join-Path $ConfigDir 'local.json'
$ExampleConfigPath = Join-Path $ConfigDir 'local.example.json'
$DistPath = Join-Path $Root 'dist\karpov-lx-source.user.js'
$DefaultKarpovBaseUrl = 'https://gateway.karpov.cn'
$DefaultYaohudApiBaseUrl = 'https://api.yaohud.cn'

$SourceDefinitions = @(
  [pscustomobject]@{ Key = 'tx'; Name = 'QQ音乐'; Default = $true; Chain = 'Karpov QQ -> 妖狐QQ -> Meting kw -> 1Music' },
  [pscustomobject]@{ Key = 'wy'; Name = '网易云音乐'; Default = $true; Chain = 'Karpov WY -> GD WY -> 妖狐WY -> Meting kw -> 1Music' },
  [pscustomobject]@{ Key = 'kw'; Name = '酷我音乐'; Default = $true; Chain = 'GD KW -> Meting kw -> 妖狐KW -> 1Music' },
  [pscustomobject]@{ Key = 'kg'; Name = '酷狗音乐'; Default = $false; Chain = 'Meting kg -> 妖狐KG -> 1Music' },
  [pscustomobject]@{ Key = 'mg'; Name = '咪咕音乐'; Default = $false; Chain = '妖狐MG -> 1Music' }
)

$YaohudSourceDefinitions = @(
  [pscustomobject]@{ Key = 'tx'; Name = 'QQ音乐'; Endpoint = '/api/music/qq'; Quality = '320' },
  [pscustomobject]@{ Key = 'wy'; Name = '网易云音乐'; Endpoint = '/api/music/wy'; Quality = '' },
  [pscustomobject]@{ Key = 'kw'; Name = '酷我音乐'; Endpoint = '/api/music/kuwo'; Quality = 'lossless' },
  [pscustomobject]@{ Key = 'kg'; Name = '酷狗音乐'; Endpoint = '/api/music/kg'; Quality = 'flac' },
  [pscustomobject]@{ Key = 'mg'; Name = '咪咕音乐'; Endpoint = '/api/music/migu'; Quality = '' }
)

function Read-JsonFile {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  $raw = (Get-Content -LiteralPath $Path -Raw -Encoding UTF8).TrimStart([char]0xFEFF)
  if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
  return $raw | ConvertFrom-Json
}

function Read-Config {
  $config = Read-JsonFile $ConfigPath
  if ($null -ne $config) { return $config }
  $example = Read-JsonFile $ExampleConfigPath
  if ($null -ne $example) { return $example }
  return [pscustomobject]@{}
}

function Save-Config {
  param([object]$Config)
  New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null
  $json = $Config | ConvertTo-Json -Depth 12
  [System.IO.File]::WriteAllText($ConfigPath, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
}

function Ensure-ObjectProperty {
  param([object]$Object, [string]$Name, [object]$DefaultValue)
  if ($null -eq $Object.PSObject.Properties[$Name]) {
    $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $DefaultValue
  }
  if ($null -eq $Object.$Name) {
    $Object.$Name = $DefaultValue
  }
}

function Ensure-ConfigShape {
  param([object]$Config)
  Ensure-ObjectProperty $Config 'baseUrl' 'https://gateway.karpov.cn'
  Ensure-ObjectProperty $Config 'apiKey' ''
  Ensure-ObjectProperty $Config 'gdstudio' ([pscustomobject]@{})
  Ensure-ObjectProperty $Config.gdstudio 'enabled' $true
  Ensure-ObjectProperty $Config.gdstudio 'baseUrl' 'https://music-api.gdstudio.xyz/api.php'
  Ensure-ObjectProperty $Config 'localBackend' ([pscustomobject]@{})
  Ensure-ObjectProperty $Config.localBackend 'enabled' $false
  Ensure-ObjectProperty $Config.localBackend 'baseUrl' 'http://127.0.0.1:47632'
  Ensure-ObjectProperty $Config.localBackend 'matchFallback' $false
  Ensure-ObjectProperty $Config.localBackend 'defaultMatchPlatform' 'kuwo'
  Ensure-ObjectProperty $Config.localBackend 'searchLimit' 10
  Ensure-ObjectProperty $Config.localBackend 'cookies' ([pscustomobject]@{})
  Ensure-ObjectProperty $Config 'yaohud' ([pscustomobject]@{})
  Ensure-ObjectProperty $Config.yaohud 'enabled' $false
  Ensure-ObjectProperty $Config.yaohud 'apiBaseUrl' 'https://api.yaohud.cn'
  Ensure-ObjectProperty $Config.yaohud 'key' ''
  Ensure-ObjectProperty $Config.yaohud 'kugouCookie' ''
  Ensure-ObjectProperty $Config.yaohud 'defaultQuality' 'flac'
  Ensure-ObjectProperty $Config.yaohud 'qualities' ([pscustomobject]@{})
  Ensure-ObjectProperty $Config.yaohud 'cookies' ([pscustomobject]@{})
  foreach ($source in $YaohudSourceDefinitions) {
    if (-not [string]::IsNullOrWhiteSpace([string]$source.Quality)) {
      Ensure-ObjectProperty $Config.yaohud.qualities $source.Key $source.Quality
    }
    Ensure-ObjectProperty $Config.yaohud.cookies $source.Key ''
  }
  Ensure-ObjectProperty $Config 'oneMusic' ([pscustomobject]@{})
  Ensure-ObjectProperty $Config.oneMusic 'enabled' $false
  Ensure-ObjectProperty $Config.oneMusic 'siteUrl' 'https://1music.cc'
  Ensure-ObjectProperty $Config.oneMusic 'apiBaseUrl' 'https://api.1music.cc'
  Ensure-ObjectProperty $Config.oneMusic 'backendBaseUrl' 'https://backend.1music.cc'
  Ensure-ObjectProperty $Config.oneMusic 'turnstileToken' ''
  Ensure-ObjectProperty $Config.oneMusic 'requestFormat' 'webm'
  Ensure-ObjectProperty $Config 'enableProbe' $true
  Ensure-ObjectProperty $Config 'strictMatch' $true
  Ensure-ObjectProperty $Config 'sources' ([pscustomobject]@{})
  foreach ($source in $SourceDefinitions) {
    Ensure-ObjectProperty $Config.sources $source.Key $source.Default
  }
  return $Config
}

function Get-Config {
  return Ensure-ConfigShape (Read-Config)
}

function Test-ConfiguredApiKey {
  param([string]$ApiKey)
  return -not [string]::IsNullOrWhiteSpace($ApiKey) -and $ApiKey -notmatch 'API Key|请在这里填入'
}

function Mask-Secret {
  param([string]$Value)
  if (-not (Test-ConfiguredApiKey $Value)) { return '未配置' }
  if ($Value.Length -le 10) { return '已配置' }
  return "$($Value.Substring(0, 4))****$($Value.Substring($Value.Length - 4))"
}

function Get-JsonProperty {
  param([AllowNull()][object]$Object, [string]$Name)
  if ($null -eq $Object) { return $null }
  $prop = $Object.PSObject.Properties[$Name]
  if ($null -eq $prop) { return $null }
  return $prop.Value
}

function Assert-ApiBodyOk {
  param([AllowNull()][object]$Body, [string]$ServiceName)
  if ($null -eq $Body) { throw "$ServiceName API 测试失败：返回为空。" }
  $code = Get-JsonProperty $Body 'code'
  if ($null -ne $code -and [string]$code -notin @('0', '200')) {
    $message = Get-JsonProperty $Body 'message'
    if ([string]::IsNullOrWhiteSpace([string]$message)) { $message = Get-JsonProperty $Body 'msg' }
    if ([string]::IsNullOrWhiteSpace([string]$message)) { $message = "code=$code" }
    throw "$ServiceName API 测试失败：$message"
  }
}

function Test-KarpovApi {
  param([string]$BaseUrl, [string]$ApiKey)
  $url = "$($BaseUrl.TrimEnd('/'))/api/proxy/qqmusic/search/songs?q=$([uri]::EscapeDataString('周杰伦'))&page=1&page_size=1"
  Write-Host "正在测试 Karpov API：$BaseUrl" -ForegroundColor Cyan
  try {
    $body = Invoke-RestMethod -Method Get -Uri $url -TimeoutSec 15 -Headers @{
      Accept = 'application/json'
      'X-Client-App' = 'LX Music Source Gateway Setup'
      'X-API-Key' = $ApiKey
    }
    Assert-ApiBodyOk $body 'Karpov'
    Write-Host 'Karpov API Key 测试通过。' -ForegroundColor Green
  } catch {
    throw "Karpov API Key 测试不通过：$($_.Exception.Message)"
  }
}

function Test-YaohudApi {
  param([string]$ApiBaseUrl, [string]$Key)
  $url = "$($ApiBaseUrl.TrimEnd('/'))/api/music/kuwo?key=$([uri]::EscapeDataString($Key))&msg=$([uri]::EscapeDataString('周杰伦'))&g=1"
  Write-Host "正在测试妖狐音乐 API：$ApiBaseUrl" -ForegroundColor Cyan
  try {
    $body = Invoke-RestMethod -Method Get -Uri $url -TimeoutSec 15 -Headers @{ Accept = 'application/json' }
    Assert-ApiBodyOk $body '妖狐音乐'
    Write-Host '妖狐 key 测试通过。' -ForegroundColor Green
  } catch {
    throw "妖狐 key 测试不通过：$($_.Exception.Message)"
  }
}

function Get-StateLabel {
  param([bool]$Enabled)
  if ($Enabled) { return '启用' }
  return '关闭'
}

function Get-TextWidth {
  param([AllowNull()][string]$Text)
  if ($null -eq $Text) { return 0 }
  $width = 0
  foreach ($ch in $Text.ToCharArray()) {
    $code = [int][char]$ch
    if (($code -ge 0x2E80 -and $code -le 0xA4CF) -or ($code -ge 0xAC00 -and $code -le 0xD7A3) -or ($code -ge 0xF900 -and $code -le 0xFAFF) -or ($code -ge 0xFF01 -and $code -le 0xFF60) -or ($code -ge 0xFFE0 -and $code -le 0xFFE6)) {
      $width += 2
    } else {
      $width += 1
    }
  }
  return $width
}

function Fit-Text {
  param([AllowNull()][string]$Text, [int]$Width)
  $textValue = if ($null -eq $Text) { '' } else { [string]$Text }
  if ((Get-TextWidth $textValue) -le $Width) { return $textValue }
  $result = ''
  $widthUsed = 0
  foreach ($ch in $textValue.ToCharArray()) {
    $charWidth = Get-TextWidth ([string]$ch)
    if ($widthUsed + $charWidth + 1 -gt $Width) { break }
    $result += $ch
    $widthUsed += $charWidth
  }
  return $result + '…'
}

function Pad-Text {
  param([AllowNull()][string]$Text, [int]$Width)
  $fitted = Fit-Text $Text $Width
  $padding = $Width - (Get-TextWidth $fitted)
  if ($padding -gt 0) { return $fitted + (' ' * $padding) }
  return $fitted
}

function New-Border {
  param([string]$Left, [string]$Middle, [string]$Right, [int[]]$Widths)
  $parts = foreach ($width in $Widths) { '─' * ($width + 2) }
  return $Left + ($parts -join $Middle) + $Right
}

function Write-TableRow {
  param([string[]]$Values, [int[]]$Widths, [ConsoleColor]$Color = [ConsoleColor]::White)
  $cells = for ($i = 0; $i -lt $Widths.Count; $i++) {
    " " + (Pad-Text $Values[$i] $Widths[$i]) + " "
  }
  Write-Host ('│' + ($cells -join '│') + '│') -ForegroundColor $Color
}

function Write-InfoBox {
  param([object[]]$Rows)
  $widths = @(12, 70)
  Write-Host (New-Border '┌' '┬' '┐' $widths)
  foreach ($row in $Rows) {
    Write-TableRow @([string]$row[0], [string]$row[1]) $widths
  }
  Write-Host (New-Border '└' '┴' '┘' $widths)
}

function Write-Title {
  Clear-Host
  Write-Host ''
  Write-Host '  LX Music Source Gateway' -ForegroundColor Cyan
  Write-Host '  统一配置 / 音源状态 / 本地后端 / 1Music token' -ForegroundColor DarkGray
  Write-Host ''
}

function Show-Dashboard {
  $config = Get-Config
  Write-Title

  $configExists = Test-Path -LiteralPath $ConfigPath
  $distExists = Test-Path -LiteralPath $DistPath
  $apiReady = Test-ConfiguredApiKey ([string]$config.apiKey)
  $oneMusicTokenReady = -not [string]::IsNullOrWhiteSpace([string]$config.oneMusic.turnstileToken)
  $yaohudReady = [bool]$config.yaohud.enabled -and (Test-ConfiguredApiKey ([string]$config.yaohud.key))
  Write-Host '配置状态' -ForegroundColor Cyan
  Write-InfoBox @(
    @('配置文件', $(if ($configExists) { 'config/local.json' } else { '未创建，先配置 API' })),
    @('JS音源', $(if ($distExists) { 'dist/karpov-lx-source.user.js' } else { '未生成' })),
    @('Karpov', (Mask-Secret ([string]$config.apiKey))),
    @('网关地址', ([string]$config.baseUrl))
  )
  Write-Host ''

  Write-Host '默认音源（LX 源映射）' -ForegroundColor Cyan
  $sourceWidths = @(3, 4, 12, 6, 42)
  Write-Host (New-Border '┌' '┬' '┐' $sourceWidths)
  Write-TableRow @('#', 'ID', '名称', '状态', '后端顺序') $sourceWidths
  Write-Host (New-Border '├' '┼' '┤' $sourceWidths)
  $index = 1
  foreach ($source in $SourceDefinitions) {
    $enabled = [bool]$config.sources.($source.Key)
    $color = if ($enabled) { [ConsoleColor]::White } else { [ConsoleColor]::DarkGray }
    Write-TableRow @([string]$index, $source.Key, $source.Name, (Get-StateLabel $enabled), $source.Chain) $sourceWidths $color
    $index++
  }
  Write-Host (New-Border '└' '┴' '┘' $sourceWidths)
  Write-Host ''

  Write-Host '自定义后端' -ForegroundColor Cyan
  $backendWidths = @(18, 6, 46)
  Write-Host (New-Border '┌' '┬' '┐' $backendWidths)
  Write-TableRow @('后端', '状态', '说明') $backendWidths
  Write-Host (New-Border '├' '┼' '┤' $backendWidths)
  Write-TableRow @('Karpov Gateway', (Get-StateLabel $apiReady), 'QQ / 网易主后端') $backendWidths $(if ($apiReady) { [ConsoleColor]::White } else { [ConsoleColor]::DarkGray })
  Write-TableRow @('GD Studio', (Get-StateLabel ([bool]$config.gdstudio.enabled)), '网易 / 酷我备用') $backendWidths $(if ([bool]$config.gdstudio.enabled) { [ConsoleColor]::White } else { [ConsoleColor]::DarkGray })
  Write-TableRow @('本地 Meting', (Get-StateLabel ([bool]$config.localBackend.enabled)), '酷我 / 酷狗 / 跨平台匹配') $backendWidths $(if ([bool]$config.localBackend.enabled) { [ConsoleColor]::White } else { [ConsoleColor]::DarkGray })
  Write-TableRow @('1Music.cc', (Get-StateLabel ([bool]$config.oneMusic.enabled)), $(if ($oneMusicTokenReady) { '已有 token，启动后端会刷新' } else { '缺少 token' })) $backendWidths $(if ([bool]$config.oneMusic.enabled -and $oneMusicTokenReady) { [ConsoleColor]::White } else { [ConsoleColor]::DarkGray })
  Write-TableRow @('妖狐音乐', (Get-StateLabel $yaohudReady), $(if ($yaohudReady) { 'QQ / 网易 / 酷我 / 酷狗 / 咪咕等免费 API' } else { '需配置 key' })) $backendWidths $(if ($yaohudReady) { [ConsoleColor]::White } else { [ConsoleColor]::DarkGray })
  Write-Host (New-Border '└' '┴' '┘' $backendWidths)
  Write-Host ''

  Write-Host '操作' -ForegroundColor Cyan
  Write-Host '[1] 配置 Karpov API      [2] 切换默认音源      [3] 切换 GD Studio'
  Write-Host '[4] 切换本地后端        [5] 启用/刷新 1Music  [6] 启动本地后端'
  Write-Host '[7] 重新生成 JS 音源    [8] 打开 dist 文件夹  [9] 显示导入路径'
  Write-Host '[A] 配置妖狐音乐 API    [Q] 退出'
  Write-Host ''
}

function Pause-Menu {
  Write-Host ''
  Read-Host '按 Enter 返回菜单' | Out-Null
}

function Invoke-Build {
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'scripts\build.ps1')
}

function Configure-Karpov {
  $config = Get-Config
  Write-Host ''
  $baseUrl = $DefaultKarpovBaseUrl
  Write-Host "Karpov Gateway：$baseUrl" -ForegroundColor Cyan
  Write-Host 'Karpov API Key 通常以 mk_ 开头。'

  $apiKeyPrompt = if (Test-ConfiguredApiKey ([string]$config.apiKey)) { 'Karpov API Key，直接回车保持当前值' } else { 'Karpov API Key' }
  $apiKey = Read-Host $apiKeyPrompt
  if ([string]::IsNullOrWhiteSpace($apiKey)) {
    if (-not (Test-ConfiguredApiKey ([string]$config.apiKey))) { throw 'API Key 不能为空。' }
    $apiKey = [string]$config.apiKey
  }
  $apiKey = $apiKey.Trim()
  if ($apiKey -notlike 'mk_*') {
    Write-Host '这个 Key 看起来不是 mk_ 开头，仍会继续测试。' -ForegroundColor Yellow
  }

  Test-KarpovApi $baseUrl $apiKey

  $config.baseUrl = $baseUrl
  $config.apiKey = $apiKey
  Save-Config $config
  Invoke-Build
  Write-Host 'Karpov API 已保存，JS 音源已重新生成。' -ForegroundColor Green
  Pause-Menu
}

function Toggle-Source {
  $config = Get-Config
  Write-Host ''
  foreach ($source in $SourceDefinitions) {
    Write-Host "  [$($source.Key)] $($source.Name) 当前：$(Get-StateLabel ([bool]$config.sources.($source.Key)))"
  }
  $key = (Read-Host '输入要切换的源 ID，例如 tx / wy / kw / kg / mg').Trim().ToLowerInvariant()
  $sourceDef = $SourceDefinitions | Where-Object { $_.Key -eq $key } | Select-Object -First 1
  if ($null -eq $sourceDef) { throw '未知源 ID。' }
  $config.sources.$key = -not [bool]$config.sources.$key
  Save-Config $config
  Invoke-Build
  Write-Host "$($sourceDef.Name) 已切换为：$(Get-StateLabel ([bool]$config.sources.$key))" -ForegroundColor Green
  Pause-Menu
}

function Toggle-GdStudio {
  $config = Get-Config
  $config.gdstudio.enabled = -not [bool]$config.gdstudio.enabled
  Save-Config $config
  Invoke-Build
  Write-Host "GD Studio 已切换为：$(Get-StateLabel ([bool]$config.gdstudio.enabled))" -ForegroundColor Green
  Pause-Menu
}

function Toggle-LocalBackend {
  $config = Get-Config
  $enabled = -not [bool]$config.localBackend.enabled
  $config.localBackend.enabled = $enabled
  $config.localBackend.matchFallback = $enabled
  $config.localBackend.baseUrl = 'http://127.0.0.1:47632'
  Save-Config $config
  Invoke-Build
  Write-Host "本地后端已切换为：$(Get-StateLabel $enabled)" -ForegroundColor Green
  Pause-Menu
}

function Configure-Yaohud {
  $config = Get-Config
  Write-Host ''
  $baseUrl = $DefaultYaohudApiBaseUrl
  Write-Host "妖狐音乐 API：$baseUrl" -ForegroundColor Cyan
  Write-Host '妖狐 key 通常是短数字 key。'

  $keyPrompt = if (Test-ConfiguredApiKey ([string]$config.yaohud.key)) { '妖狐 key，直接回车保持当前值' } else { '妖狐 key' }
  $key = Read-Host $keyPrompt
  if ([string]::IsNullOrWhiteSpace($key)) {
    if (-not (Test-ConfiguredApiKey ([string]$config.yaohud.key))) { throw '妖狐 key 不能为空。' }
    $key = [string]$config.yaohud.key
  }
  $key = $key.Trim()
  if ($key -notmatch '^\d{3,12}$') {
    Write-Host '这个 key 看起来不像短数字 key，仍会继续测试。' -ForegroundColor Yellow
  }

  Write-Host ''
  Write-Host '妖狐免费音乐接口：' -ForegroundColor Cyan
  foreach ($source in $YaohudSourceDefinitions) {
    $quality = [string]$config.yaohud.qualities.($source.Key)
    $note = if ([string]::IsNullOrWhiteSpace($quality)) { $source.Endpoint } else { "$($source.Endpoint)，默认音质 $quality" }
    Write-Host "  [$($source.Key)] $($source.Name) - $note"
  }

  Test-YaohudApi $baseUrl $key

  $config.yaohud.enabled = $true
  $config.yaohud.apiBaseUrl = $baseUrl
  $config.yaohud.key = $key
  $config.yaohud.defaultQuality = [string]$config.yaohud.qualities.kg
  $config.localBackend.enabled = $true
  Save-Config $config
  Invoke-Build
  Write-Host '妖狐音乐 API 已启用，本地后端已启用，JS 音源已重新生成。' -ForegroundColor Green
  Pause-Menu
}

function Refresh-OneMusic {
  $config = Get-Config
  $config.oneMusic.enabled = $true
  $config.localBackend.enabled = $true
  $config.localBackend.matchFallback = $true
  Save-Config $config
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'scripts\refresh-1music-token.ps1')
  Invoke-Build
  Write-Host '1Music 已启用，token 已刷新，JS 音源已重新生成。' -ForegroundColor Green
  Pause-Menu
}

function Start-BackendWindow {
  $script = Join-Path $Root 'scripts\start-local-backend.ps1'
  Start-Process -FilePath 'powershell' -ArgumentList @('-NoExit', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$script`"") | Out-Null
  Write-Host '已打开本地后端窗口。1Music 启用时会先自动刷新 token。' -ForegroundColor Green
  Pause-Menu
}

function Open-DistFolder {
  $distDir = Join-Path $Root 'dist'
  New-Item -ItemType Directory -Force -Path $distDir | Out-Null
  Invoke-Item $distDir
}

function Show-ImportPath {
  Write-Host ''
  Write-Host 'LX 导入文件：' -ForegroundColor Cyan
  Write-Host "  $DistPath"
  Write-Host ''
  Write-Host 'LX Music Desktop：设置 -> 自定义源管理 -> 本地导入'
  Pause-Menu
}

if ($StatusOnly) {
  Show-Dashboard
  exit 0
}

while ($true) {
  try {
    Show-Dashboard
    $choice = (Read-Host '选择操作').Trim().ToLowerInvariant()
    switch ($choice) {
      '1' { Configure-Karpov }
      '2' { Toggle-Source }
      '3' { Toggle-GdStudio }
      '4' { Toggle-LocalBackend }
      '5' { Refresh-OneMusic }
      '6' { Start-BackendWindow }
      '7' { Invoke-Build; Pause-Menu }
      '8' { Open-DistFolder }
      '9' { Show-ImportPath }
      'a' { Configure-Yaohud }
      'q' { break }
      default { Write-Host '未知操作。' -ForegroundColor Yellow; Pause-Menu }
    }
  } catch {
    Write-Host ''
    Write-Host $_.Exception.Message -ForegroundColor Red
    Pause-Menu
  }
}
