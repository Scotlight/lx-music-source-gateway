param(
  [int]$Port = 47633,
  [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$Root = Resolve-Path (Join-Path $PSScriptRoot '..')
$ProfileDir = Join-Path $Root 'config\browser-profile'
$SiteUrl = 'https://1music.cc/zh-CN'

function Find-Browser {
  $candidates = @(
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles(x86)\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "$env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe"
  )
  foreach ($item in $candidates) {
    if ($item -and (Test-Path -LiteralPath $item)) { return $item }
  }
  throw 'Cannot find Edge or Chrome.'
}

function Receive-CdpMessage {
  param([System.Net.WebSockets.ClientWebSocket]$Socket)
  $buffer = New-Object byte[] 65536
  $chunks = New-Object System.Collections.Generic.List[byte]
  do {
    $segment = [ArraySegment[byte]]::new($buffer)
    $result = $Socket.ReceiveAsync($segment, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
    if ($result.Count -gt 0) {
      for ($i = 0; $i -lt $result.Count; $i++) { $chunks.Add($buffer[$i]) }
    }
  } while (-not $result.EndOfMessage)
  return [Text.Encoding]::UTF8.GetString($chunks.ToArray()) | ConvertFrom-Json
}

function Invoke-CdpEvaluate {
  param([string]$WebSocketDebuggerUrl, [string]$Expression)
  $socket = [System.Net.WebSockets.ClientWebSocket]::new()
  $socket.ConnectAsync([Uri]$WebSocketDebuggerUrl, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
  try {
    $payload = @{
      id = 1
      method = 'Runtime.evaluate'
      params = @{
        expression = $Expression
        returnByValue = $true
        awaitPromise = $true
      }
    } | ConvertTo-Json -Depth 8 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($payload)
    $socket.SendAsync([ArraySegment[byte]]::new($bytes), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
    while ($true) {
      $message = Receive-CdpMessage $socket
      if ($message.id -eq 1) { return $message.result.result.value }
    }
  } finally {
    if ($socket.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
      $socket.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, 'done', [Threading.CancellationToken]::None).GetAwaiter().GetResult()
    }
    $socket.Dispose()
  }
}

function Invoke-CdpCommand {
  param([string]$WebSocketDebuggerUrl, [string]$Method, [object]$Params = @{})
  $socket = [System.Net.WebSockets.ClientWebSocket]::new()
  $socket.ConnectAsync([Uri]$WebSocketDebuggerUrl, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
  try {
    $payload = @{
      id = 1
      method = $Method
      params = $Params
    } | ConvertTo-Json -Depth 8 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($payload)
    $socket.SendAsync([ArraySegment[byte]]::new($bytes), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
    while ($true) {
      $message = Receive-CdpMessage $socket
      if ($message.id -eq 1) { return $message }
    }
  } finally {
    if ($socket.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
      $socket.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, 'done', [Threading.CancellationToken]::None).GetAwaiter().GetResult()
    }
    $socket.Dispose()
  }
}

function Close-StartedBrowser {
  param([AllowNull()][System.Diagnostics.Process]$BrowserProcess, [int]$Port)
  try {
    $version = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/json/version" -TimeoutSec 3
    if ($version.webSocketDebuggerUrl) {
      Invoke-CdpCommand -WebSocketDebuggerUrl $version.webSocketDebuggerUrl -Method 'Browser.close' | Out-Null
      Start-Sleep -Milliseconds 800
    }
  } catch {
    Write-Host "关闭浏览器调试窗口失败，将尝试结束启动进程：$($_.Exception.Message)" -ForegroundColor Yellow
  }
  try {
    if ($null -ne $BrowserProcess -and -not $BrowserProcess.HasExited) {
      Stop-Process -Id $BrowserProcess.Id -Force -ErrorAction SilentlyContinue
    }
  } catch {
    Write-Host "结束浏览器进程失败：$($_.Exception.Message)" -ForegroundColor Yellow
  }
}

New-Item -ItemType Directory -Force -Path $ProfileDir | Out-Null
$browser = Find-Browser
$args = @(
  "--remote-debugging-port=$Port",
  "--user-data-dir=$ProfileDir",
  '--no-first-run',
  '--new-window',
  $SiteUrl
)
$browserProcess = Start-Process -FilePath $browser -ArgumentList $args -PassThru
Write-Host 'Browser opened. Wait for 1Music page and Cloudflare challenge to finish.'

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$endpoint = "http://127.0.0.1:$Port/json"
$expression = '(() => { const input = document.querySelector("input[name=\"cf-turnstile-response\"]"); return input && input.value && input.value.length > 100 ? input.value : ""; })()'
$captured = $false

try {
  while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 2
    try {
      $pages = Invoke-RestMethod -Uri $endpoint -TimeoutSec 3
      $page = @($pages) | Where-Object { $_.url -like '*1music.cc*' -and $_.webSocketDebuggerUrl } | Select-Object -First 1
      if ($null -eq $page) { continue }
      $token = Invoke-CdpEvaluate -WebSocketDebuggerUrl $page.webSocketDebuggerUrl -Expression $expression
      if (-not [string]::IsNullOrWhiteSpace($token)) {
        $env:ONE_MUSIC_TOKEN = $token
        & (Join-Path $PSScriptRoot 'set-1music.ps1') -Enabled true
        & (Join-Path $PSScriptRoot 'set-local-backend.ps1') -Enabled true
        Write-Host '1Music token captured and local backend enabled.'
        $captured = $true
        break
      }
    } catch {
      Write-Host "Waiting: $($_.Exception.Message)"
    }
  }
  if (-not $captured) { throw 'Timed out while waiting for 1Music Turnstile token.' }
} finally {
  Close-StartedBrowser -BrowserProcess $browserProcess -Port $Port
}
