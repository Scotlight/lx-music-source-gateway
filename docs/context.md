# 接入上下文记录

## 目标

把 Karpov Gateway 与 GD Studio 的音乐接口封装成 LX Music Desktop 可导入的自定义源脚本。

## 来源标识

当前仓库在 `README.md` 和生成后的 LX 自定义源元信息中保留：

```text
GD Studio Music API
https://music-api.gdstudio.xyz/api.php
```

## 用户交互要求

- 不把用户 API Key 写进仓库文件。
- 普通用户不应被要求安装 npm 或 Node.js。
- `lx-source-gateway.cmd` 是普通用户主入口，负责配置 API Key、切换音源、配置妖狐音乐 API、启动本地后端并生成 LX 可导入的 JS 音源。
- Karpov 与妖狐的配置菜单只显示固定接口地址，不让用户输入网关地址；用户只输入 key。
- Karpov API Key 通常以 `mk_` 开头；妖狐 key 通常是短数字 key。
- 输入 Karpov 或妖狐 key 后，菜单会先请求对应接口做可用性测试，测试通过后才保存配置并重新生成 JS 音源。
- `config/local.json` 只是本地中间配置，不给 LX 直接使用。
- LX 最终导入的是 `dist/karpov-lx-source.user.js`。
- 当前密钥不加密：Karpov API Key 会进入生成 JS，妖狐 key / 平台 Cookie / 1Music token 只保存在本地 `config/local.json` 并通过本地后端读取。

## LX 自定义源侧约束

LX 自定义源脚本通过 `window.lx` 与应用通信：

- `on(EVENT_NAMES.request, handler)` 接收请求
- `send(EVENT_NAMES.inited, {...})` 上报初始化完成
- 当前主要实现 `musicUrl`
- 直链返回值必须是 `http://` 或 `https://` 字符串
- LX 不直接导入 JSON 音源，最终文件必须是 JS

LX 源名：

```text
tx = QQ 音乐
wy = 网易云音乐
kg = 酷狗音乐
kw = 酷我音乐
mg = 咪咕音乐
```

当前启用：

```text
tx -> Karpov qqmusic -> 妖狐 QQ -> 本地 Meting kuwo -> 1Music
wy -> Karpov netease -> GD Studio netease -> 妖狐网易 -> 本地 Meting kuwo -> 1Music
kw -> GD Studio kuwo -> 本地 Meting kuwo -> 妖狐酷我 -> 1Music
kg -> 本地 Meting kugou -> 妖狐酷狗 -> 1Music
mg -> 妖狐咪咕 -> 1Music
```

## Karpov 实际行为

`openapi.yaml` 与实测实例存在差异：

```text
文档：Authorization: Bearer <api_key>
实测：X-API-Key: <api_key>

文档：/v1/{provider}/...
实测：/api/proxy/{provider}/...
```

可用搜索接口：

```text
GET /api/proxy/{provider}/search/songs?q=...&page=1&page_size=20
```

可用直链接口：

```text
GET /api/proxy/{provider}/songs/{id}/url?quality=MP3_128
GET /api/proxy/{provider}/songs/{id}/url?quality=MP3_320
GET /api/proxy/{provider}/songs/{id}/url?quality=FLAC
```

返回直链字段：

```text
data.audio.url
```

## GD Studio 实际行为

接口入口：

```text
https://music-api.gdstudio.xyz/api.php
```

文档中的稳定源：

```text
netease、kuwo、joox、bilibili
```

搜索接口：

```text
GET ?types=search&source=[SOURCE]&name=[KEYWORD]&count=[PAGE LENGTH]&pages=[PAGE NUM]
```

直链接口：

```text
GET ?types=url&source=[SOURCE]&id=[TRACK ID]&br=[128/192/320/740/999]
```

图片接口：

```text
GET ?types=pic&source=[SOURCE]&id=[PIC ID]&size=[300/500]
```

歌词接口：

```text
GET ?types=lyric&source=[SOURCE]&id=[LYRIC ID]
```

返回直链字段：

```text
url
```

实测限制：

```text
source=tencent 不支持
source=netease&id=186016 返回空 url
source=kuwo&id=228908 可返回周杰伦《晴天》原版直链
```

## 重要验证记录

### 网易云原版《晴天》

```text
provider: netease
id: 186016
title: 晴天
artist: 周杰伦
album: 叶惠美
durationSeconds: 269
```

Karpov 详情接口可用，但直链接口返回：

```json
{"code":40300,"message":"该歌曲暂无此品质资源"}
```

GD Studio `source=netease&id=186016` 返回：

```json
{"url":"","br":0,"size":0,"from":"music.gdstudio.xyz"}
```

### QQ 音乐原版《晴天》

```text
provider: qqmusic
id: 0039MnYb0qxYhV
title: 晴天
artist: 周杰伦
album: 叶惠美
durationSeconds: 269
```

Karpov 直链接口可返回 `data.audio.url`，抽样验证可读取音频头。

### 酷我原版《晴天》

GD Studio `source=kuwo` 搜索 `周杰伦 晴天 叶惠美` 可以命中：

```json
{
  "id":"228908",
  "name":"晴天",
  "artist":["周杰伦"],
  "album":"叶惠美",
  "source":"kuwo"
}
```

GD Studio `source=kuwo&id=228908` 的 `br=128`、`br=320`、`br=740`、`br=999` 均可返回直链，抽样验证可读取音频头。

### 错误匹配案例

关键词：

```text
周杰伦 晴天
```

网易云搜索首个可播放条目曾命中：

```text
id: 3344811140
title: 晴天(正式版)
artist: 周杰伦. / 溺死的鱼
durationSeconds: 86
```

这个条目能下载，但不是周杰伦原版。后续脚本不能主动搜索后按可播放状态替代。

## 当前设计决策

- 不在仓库文件中保存真实 API Key。
- `lx-source-gateway.cmd` 写入本地 `config/local.json` 后立即生成 `dist/karpov-lx-source.user.js`。
- `scripts/build.ps1` 是默认构建路径，不依赖 npm/Node。
- `scripts/build.mjs` 保留给开发者使用。
- `config/local.json` 与 `dist/*.js` 都被 `.gitignore` 忽略。
- 自定义源优先基于 LX 当前歌曲 ID 请求直链；跨平台 fallback 只走本地后端严格匹配。
- `wy` 的后端顺序是 Karpov `netease`，失败后尝试 GD Studio `netease`。
- `kw` 直接走 GD Studio `kuwo`。
- 返回给 LX 前先做直链探测，过滤过期或不可下载 URL。


## 本地 Meting 后端

新增可选 Node.js 后端：

```text
server/local-meting-server.mjs
scripts/start-local-backend.ps1
```

代码来源：`https://github.com/ELDment/Meting-Agent`，provider 文件复制到 `vendor/meting/`，并保留 MIT License。

本地服务默认监听：

```text
http://127.0.0.1:47632
```

接口：

```text
GET /health
GET /url?platform=kuwo&id=228908&quality=320k
GET /match-url?platform=kuwo&name=晴天&artist=周杰伦&album=叶惠美&quality=320k
GET /search?platform=kuwo&keyword=周杰伦%20晴天&page=1&limit=10
```

配置开关写在 `config/local.json`：

```json
"localBackend": {
  "enabled": false,
  "baseUrl": "http://127.0.0.1:47632",
  "matchFallback": false,
  "defaultMatchPlatform": "kuwo",
  "searchLimit": 10,
  "cookies": {}
}
```

`lx-source-gateway.cmd` 的“切换本地后端”会把 `enabled` 和 `matchFallback` 打开或关闭，并重新生成 JS 音源。

当前策略：

- `kw`：GD Studio `kuwo` 失败后尝试本地 Meting `kuwo` 直链。
- `tx` / `wy`：前置后端失败后，可通过本地 Meting `kuwo` 做严格匹配 fallback。
- `kg`：本地 Meting `kugou`，默认关闭。
- `mg`：通过妖狐咪咕提供，默认关闭。
- 严格匹配要求歌曲名和歌手匹配；专辑存在时也必须匹配。


## 1Music.cc fallback

当前页面实测：

```text
GET https://api.1music.cc/search?songs=周杰伦+晴天&token=<cf-turnstile-response>
POST https://backend.1music.cc/download/
```

搜索返回数组字段：

```json
{
  "album": "葉惠美",
  "artist": "周杰倫",
  "song_hash": "09d693...703c",
  "thumbnail": "https://pic.1music.cc/...",
  "title": "晴天",
  "videoId": "SJKoWAd5ySo"
}
```

下载请求体：

```json
{
  "title": "晴天",
  "album": "葉惠美",
  "artist": "周杰倫",
  "videoId": "SJKoWAd5ySo",
  "request_format": "webm",
  "song_hash": "09d693...703c",
  "thumbnail": "https://pic.1music.cc/..."
}
```

下载响应：

```json
{
  "detail": "下载任务已创建",
  "download_url": "https://oss.1music.cc/.../webm?salt=..."
}
```

接入策略：只放在本地后端，使用 `lx-source-gateway.cmd` 的“启用/刷新 1Music”菜单从 Edge/Chrome 页面读取 `cf-turnstile-response`，写入 `config/local.json` 的 `oneMusic.turnstileToken`。自定义源 JS 不保存 token，只调用 `http://127.0.0.1:47632/1music/match-url`。刷新脚本使用独立浏览器资料目录和 CDP，获取 token 后会发送 `Browser.close` 并回退到结束本次启动的浏览器进程。


## 统一 cmd 页面

新增入口：

```text
lx-source-gateway.cmd
```

它调用 `scripts/gateway-menu.ps1`，展示默认音源 `tx` / `wy` / `kw` / `kg` / `mg` 与自定义后端 Karpov、GD Studio、本地 Meting、1Music.cc、妖狐音乐的状态。

根目录只保留 `lx-source-gateway.cmd` 作为普通用户入口；不再保留内部 `.cmd` 副本。菜单里的“启动本地后端”会直接打开 PowerShell 窗口并执行 `scripts/start-local-backend.ps1`。当 `oneMusic.enabled=true` 时，启动后端前会先运行 `scripts/refresh-1music-token.ps1`，自动打开 Edge/Chrome 获取 `cf-turnstile-response` 并重新生成 JS。

后续维护优先修改对应 `.ps1`、`.mjs` 或菜单实现，不再维护一组转发 `.cmd`。

## 妖狐音乐 API

免费音乐文档与接口：

```text
QQ 免费：   https://api.yaohud.cn/doc/25 -> GET https://api.yaohud.cn/api/music/qq
网易免费： https://api.yaohud.cn/doc/32 -> GET https://api.yaohud.cn/api/music/wy
酷我：     https://api.yaohud.cn/doc/47 -> GET https://api.yaohud.cn/api/music/kuwo
酷狗：     https://api.yaohud.cn/doc/83 -> GET https://api.yaohud.cn/api/music/kg
咪咕：     https://api.yaohud.cn/doc/69 -> GET https://api.yaohud.cn/api/music/migu
```

通用参数：

```text
key      必填，妖狐 API key
msg      必填，搜索关键词
n        可选，单曲索引，从 1 开始；传入后返回单曲详情和播放链接
g/num    可选，返回结果数量；咪咕使用 num，其他音乐接口使用 g
size     可选，QQ / 酷我音质参数
quality  可选，酷狗音质参数
cookie   可选，平台登录 Cookie；高音质或会员资源可能需要
```

当前接入策略：

- 只放在本地后端，不把妖狐 key 或平台 Cookie 写入 LX 自定义源 JS。
- `tx` / `wy` / `kw` / `kg` / `mg` 均可通过妖狐对应接口做严格匹配 fallback。
- 本地接口：`GET /yaohud/{platform}/search`、`GET /yaohud/{platform}/match-url`。
- 匹配逻辑仍然要求歌名、歌手匹配；专辑存在时也要匹配。
