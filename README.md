[![友链 LINUX DO](https://img.shields.io/badge/%E5%8F%8B%E9%93%BE-LINUX%20DO-0969da?style=flat-square)](https://linux.do/)
[![新的理想型社区](https://img.shields.io/badge/%E6%96%B0%E7%9A%84%E7%90%86%E6%83%B3%E5%9E%8B%E7%A4%BE%E5%8C%BA-yes-2ea44f?style=flat-square)](https://linux.do/)

# LX Music Source Gateway

这是一个给 LX Music Desktop 使用的自定义源生成器，主入口只保留一个：

```bat
lx-source-gateway.cmd
```

双击后会打开统一菜单，用来配置 Karpov API Key、启用或关闭音源、配置妖狐音乐 API、启动本地后端，并生成 LX 可导入的：

```text
dist/karpov-lx-source.user.js
```

## 效果图

![LX Music Source Gateway 菜单效果图](docs/assets/gateway-menu-preview.svg)

## 适合谁用

- 想把 Karpov Gateway、GD Studio、妖狐音乐、本地 Meting、1Music.cc 聚合到 LX Music Desktop。
- 想用一个菜单完成配置，不想在根目录面对一堆 `.cmd`。
- 只需要基础生成时，不想安装 npm 或 Node.js。

## 当前支持的 LX 源

LX Music Desktop 可用的源 ID 只有这几个，本项目也只暴露这些：

| LX 源 | 名称 | 默认 | 后端顺序 |
| --- | --- | --- | --- |
| `tx` | QQ 音乐 | 开启 | Karpov QQ -> 妖狐 QQ -> 本地 Meting 酷我严格匹配 -> 1Music 严格匹配 |
| `wy` | 网易云音乐 | 开启 | Karpov 网易 -> GD Studio 网易 -> 妖狐网易 -> 本地 Meting 酷我严格匹配 -> 1Music 严格匹配 |
| `kw` | 酷我音乐 | 开启 | GD Studio 酷我 -> 本地 Meting 酷我 -> 妖狐酷我 -> 1Music 严格匹配 |
| `kg` | 酷狗音乐 | 关闭 | 本地 Meting 酷狗 -> 妖狐酷狗 -> 1Music 严格匹配 |
| `mg` | 咪咕音乐 | 关闭 | 妖狐咪咕 -> 1Music 严格匹配 |

`kg` 和 `mg` 默认关闭，需要在菜单里手动开启。

## 开启酷狗和咪咕音源

双击：

```bat
lx-source-gateway.cmd
```

进入菜单后选择：

```text
[2] 切换默认音源
```

然后输入要开启的源 ID：

```text
kg
mg
```

每次切换后脚本会自动重新生成：

```text
dist/karpov-lx-source.user.js
```

重新生成后，在 LX Music Desktop 重新导入这个 JS 文件。`kg` 依赖本地 Meting 或妖狐酷狗 fallback，`mg` 依赖妖狐咪咕 fallback；需要妖狐时，继续在菜单里选择 **[A] 配置妖狐音乐 API**，然后选择 **[6] 启动本地后端**。

## 快速开始

1. 双击根目录的：

   ```bat
   lx-source-gateway.cmd
   ```

2. 选择 **[1] 配置 Karpov API**，输入 Karpov API Key。Key 通常以 `mk_` 开头。

   菜单会显示并使用这个接口地址：

   ```text
   https://gateway.karpov.cn
   ```

   输入 Key 后，脚本会自动请求 Karpov 搜索接口测试 Key 是否可用；测试通过后才会保存配置并生成 JS。

3. 菜单会生成：

   ```text
   dist/karpov-lx-source.user.js
   ```

4. 打开 LX Music Desktop：

   ```text
   设置 -> 自定义源管理 -> 本地导入
   ```

5. 选择 `dist/karpov-lx-source.user.js`。

基础配置和生成使用 PowerShell 脚本，不需要 npm 或 Node.js。

## 配置妖狐音乐 API

菜单选择：

```text
[A] 配置妖狐音乐 API
```

菜单会显示并使用这个接口地址：

```text
https://api.yaohud.cn
```

输入妖狐 key 即可。妖狐 key 通常是短数字 key。输入后，脚本会自动请求妖狐酷我接口测试 key 是否可用；测试通过后才会保存配置并生成 JS。

会写入本地配置：

```text
config/local.json
```

已接入的妖狐免费音乐接口：

| LX 源 | 妖狐接口 |
| --- | --- |
| `tx` | `/api/music/qq` |
| `wy` | `/api/music/wy` |
| `kw` | `/api/music/kuwo` |
| `kg` | `/api/music/kg` |
| `mg` | `/api/music/migu` |

妖狐 `key` 和平台 Cookie 不会写进仓库，也不会直接写进 LX 自定义源 JS。妖狐走本地后端，所以配置后需要在菜单选择：

```text
[6] 启动本地后端
```

后端窗口需要保持打开。

## 可选：启用本地后端

本地后端用于这些增强能力：

- 本地 Meting 直链与严格匹配 fallback。
- 妖狐音乐接口 fallback。
- 1Music.cc 严格匹配 fallback。

这部分需要 Node.js 18 或更新版本。

菜单选择：

```text
[4] 切换本地后端
[6] 启动本地后端
```

默认服务地址：

```text
http://127.0.0.1:47632
```

本地后端提供的常用接口：

```text
GET /health
GET /url?platform=kuwo&id=228908&quality=320k
GET /match-url?platform=kuwo&name=晴天&artist=周杰伦&album=叶惠美&quality=320k
GET /search?platform=kuwo&keyword=周杰伦%20晴天&page=1&limit=10
GET /yaohud/{platform}/search?keyword=周杰伦%20晴天&limit=12
GET /yaohud/{platform}/match-url?name=晴天&artist=周杰伦&album=叶惠美&quality=flac
GET /1music/search?keyword=周杰伦%20晴天
GET /1music/match-url?name=晴天&artist=周杰伦&album=叶惠美&quality=flac
```

其中 `{platform}` 支持：`tx`、`wy`、`kw`、`kg`、`mg`。

## 可选：启用 1Music.cc fallback

菜单选择：

```text
[5] 启用/刷新 1Music
```

脚本会打开独立浏览器资料目录，读取页面里的 `cf-turnstile-response` token，并写入：

```text
config/local.json
```

浏览器资料目录：

```text
config/browser-profile/
```

1Music.cc 不作为独立 LX 源展示，只作为严格匹配 fallback 使用。匹配要求歌名和歌手一致；专辑存在时也要匹配，避免误播翻唱或搬运条目。

## 文件说明

根目录现在只保留一个普通用户入口：

```text
lx-source-gateway.cmd
```

常用文件：

| 路径 | 说明 |
| --- | --- |
| `lx-source-gateway.cmd` | 统一配置菜单，普通用户入口 |
| `config/local.example.json` | 配置示例，不含真实 key |
| `config/local.json` | 本地配置，包含 key，不提交 |
| `dist/karpov-lx-source.user.js` | 生成后的 LX 自定义源，不提交 |
| `server/local-meting-server.mjs` | 可选本地后端 |
| `src/karpov-lx-source.user.template.js` | LX 自定义源模板 |

## 隐私和提交范围

这些文件已写入 `.gitignore`：

```text
config/local.json
config/browser-profile/
dist/*.js
```

`config/local.json` 可能包含 Karpov API Key、妖狐 key、平台 Cookie、1Music token。当前不做加密，原因是 LX 自定义源和本地后端需要直接读取这些值。`dist/*.js` 是生成产物，也可能包含本地配置内容。不要把这些文件发到论坛或提交到仓库。

密钥写入范围：

- Karpov API Key：写入 `config/local.json`，生成 JS 时也会写入 `dist/karpov-lx-source.user.js`，因为 LX 自定义源需要直接调用 Karpov Gateway。
- 妖狐 key、平台 Cookie、1Music token：只写入 `config/local.json`，不写入生成的 JS；LX 通过本地后端使用这些值。
- 1Music 刷新 token 时会临时打开 Edge/Chrome 独立资料目录；刷新完成或超时后，脚本会尝试自动关闭这个浏览器窗口。

## 开源协议

本项目使用 MIT License 开源，详见 `LICENSE`。

## 开发者命令

PowerShell 版构建：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build.ps1
```

Node 版构建：

```bash
npm run build
```

抽样验证网关接口和音频直链：

```bash
npm run verify
```

启动本地后端：

```bash
npm run local
```

## 出处与致谢

- Karpov Gateway：`https://gateway.karpov.cn`
- GD Studio Music API：`https://music-api.gdstudio.xyz/api.php`
- Meting-Agent：`https://github.com/ELDment/Meting-Agent`
- 1Music.cc：`https://1music.cc`
- 妖狐数据开放 API：`https://api.yaohud.cn/doc/`

GD Studio 接口页面要求调用方注明出处，所以 README 和生成后的 LX 自定义源元信息都会保留 `GD Studio Music API` 与接口地址。Meting-Agent 基于 MIT License，相关 provider 文件放在 `vendor/meting/`，并保留 `vendor/meting/LICENSE`。
