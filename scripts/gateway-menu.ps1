param(
  [switch]$StatusOnly
)

$ErrorActionPreference = 'Stop'
$Root = Resolve-Path (Join-Path $PSScriptRoot '..')
$ConfigDir = Join-Path $Root 'config'
$ConfigPath = Join-Path $ConfigDir 'local.json'
$ExampleConfigPath = Join-Path $ConfigDir 'local.example.json'
$DistPath = Join-Path $Root 'dist\karpov-lx-source.user.js'

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
  $currentBase = if ([string]::IsNullOrWhiteSpace([string]$config.baseUrl)) { 'https://gateway.karpov.cn' } else { [string]$config.baseUrl }
  $baseUrl = Read-Host "网关地址，直接回车保持 [$currentBase]"
  if ([string]::IsNullOrWhiteSpace($baseUrl)) { $baseUrl = $currentBase }

  $apiKeyPrompt = if (Test-ConfiguredApiKey ([string]$config.apiKey)) { 'API Key，直接回车保持当前值' } else { 'API Key' }
  $apiKey = Read-Host $apiKeyPrompt
  if ([string]::IsNullOrWhiteSpace($apiKey)) {
    if (-not (Test-ConfiguredApiKey ([string]$config.apiKey))) { throw 'API Key 不能为空。' }
    $apiKey = [string]$config.apiKey
  }

  $config.baseUrl = $baseUrl.TrimEnd('/')
  $config.apiKey = $apiKey.Trim()
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
  $currentBase = if ([string]::IsNullOrWhiteSpace([string]$config.yaohud.apiBaseUrl)) { 'https://api.yaohud.cn' } else { [string]$config.yaohud.apiBaseUrl }
  $baseUrl = Read-Host "妖狐 API 地址，直接回车保持 [$currentBase]"
  if ([string]::IsNullOrWhiteSpace($baseUrl)) { $baseUrl = $currentBase }

  $keyPrompt = if (Test-ConfiguredApiKey ([string]$config.yaohud.key)) { '妖狐 key，直接回车保持当前值' } else { '妖狐 key' }
  $key = Read-Host $keyPrompt
  if ([string]::IsNullOrWhiteSpace($key)) {
    if (-not (Test-ConfiguredApiKey ([string]$config.yaohud.key))) { throw '妖狐 key 不能为空。' }
    $key = [string]$config.yaohud.key
  }

  Write-Host ''
  Write-Host '妖狐免费音乐接口：' -ForegroundColor Cyan
  foreach ($source in $YaohudSourceDefinitions) {
    $quality = [string]$config.yaohud.qualities.($source.Key)
    $note = if ([string]::IsNullOrWhiteSpace($quality)) { $source.Endpoint } else { "$($source.Endpoint)，默认音质 $quality" }
    Write-Host "  [$($source.Key)] $($source.Name) - $note"
  }

  $kgQuality = Read-Host "酷狗默认音质，直接回车保持 [$($config.yaohud.qualities.kg)]"
  if (-not [string]::IsNullOrWhiteSpace($kgQuality)) { $config.yaohud.qualities.kg = $kgQuality.Trim() }
  $kwQuality = Read-Host "酷我默认音质，直接回车保持 [$($config.yaohud.qualities.kw)]"
  if (-not [string]::IsNullOrWhiteSpace($kwQuality)) { $config.yaohud.qualities.kw = $kwQuality.Trim() }
  $txQuality = Read-Host "QQ默认音质，直接回车保持 [$($config.yaohud.qualities.tx)]"
  if (-not [string]::IsNullOrWhiteSpace($txQuality)) { $config.yaohud.qualities.tx = $txQuality.Trim() }

  $config.yaohud.enabled = $true
  $config.yaohud.apiBaseUrl = $baseUrl.TrimEnd('/')
  $config.yaohud.key = $key.Trim()
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
  $cmd = Join-Path $Root 'scripts\cmd\start-local-backend.cmd'
  Start-Process -FilePath $env:ComSpec -ArgumentList @('/k', "`"$cmd`"") | Out-Null
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
