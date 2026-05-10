import fs from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const root = path.resolve(__dirname, '..')
const configPath = path.join(root, 'config', 'local.json')
const templatePath = path.join(root, 'src', 'karpov-lx-source.user.template.js')
const outputPath = path.join(root, 'dist', 'karpov-lx-source.user.js')

const DEFAULT_GDSTUDIO_BASE_URL = 'https://music-api.gdstudio.xyz/api.php'
const DEFAULT_LOCAL_BACKEND_BASE_URL = 'http://127.0.0.1:47632'
const DEFAULT_ONE_MUSIC_SITE_URL = 'https://1music.cc'
const DEFAULT_ONE_MUSIC_API_BASE_URL = 'https://api.1music.cc'
const DEFAULT_ONE_MUSIC_BACKEND_BASE_URL = 'https://backend.1music.cc'
const DEFAULT_YAOHUD_API_BASE_URL = 'https://api.yaohud.cn'

function escapeForSingleQuotedJsString(value) {
  return String(value)
    .replace(/\\/g, '\\\\')
    .replace(/'/g, "\\'")
    .replace(/\r/g, '\\r')
    .replace(/\n/g, '\\n')
}

async function readConfig() {
  try {
    const raw = await fs.readFile(configPath, 'utf8')
    return JSON.parse(raw.replace(/^\uFEFF/, ''))
  } catch (error) {
    throw new Error('缺少 config/local.json。请先运行 lx-source-gateway.cmd，或复制 config/local.example.json 后手动填写。')
  }
}

const config = await readConfig()
if (!config.baseUrl || !/^https?:\/\//.test(config.baseUrl)) throw new Error('config/local.json: baseUrl 必须是 http(s) URL')
if (!config.apiKey || /请在这里填入/.test(config.apiKey)) throw new Error('config/local.json: apiKey 不能为空')

const gdstudio = {
  enabled: config.gdstudio?.enabled !== false,
  baseUrl: config.gdstudio?.baseUrl || DEFAULT_GDSTUDIO_BASE_URL,
}
if (gdstudio.enabled && !/^https?:\/\//.test(gdstudio.baseUrl)) {
  throw new Error('config/local.json: gdstudio.baseUrl 必须是 http(s) URL')
}

const localBackend = {
  enabled: config.localBackend?.enabled === true,
  baseUrl: config.localBackend?.baseUrl || DEFAULT_LOCAL_BACKEND_BASE_URL,
  matchFallback: config.localBackend?.matchFallback === true,
}
if (localBackend.enabled && !/^https?:\/\//.test(localBackend.baseUrl)) {
  throw new Error('config/local.json: localBackend.baseUrl 必须是 http(s) URL')
}

const yaohud = {
  enabled: config.yaohud?.enabled === true,
  apiBaseUrl: config.yaohud?.apiBaseUrl || DEFAULT_YAOHUD_API_BASE_URL,
  qualities: {
    ...(config.yaohud?.qualities || {}),
  },
}
if (yaohud.enabled && !/^https?:\/\//.test(yaohud.apiBaseUrl)) {
  throw new Error('config/local.json: yaohud.apiBaseUrl 必须是 http(s) URL')
}

const oneMusic = {
  enabled: config.oneMusic?.enabled === true,
  siteUrl: config.oneMusic?.siteUrl || DEFAULT_ONE_MUSIC_SITE_URL,
  apiBaseUrl: config.oneMusic?.apiBaseUrl || DEFAULT_ONE_MUSIC_API_BASE_URL,
  backendBaseUrl: config.oneMusic?.backendBaseUrl || DEFAULT_ONE_MUSIC_BACKEND_BASE_URL,
  requestFormat: config.oneMusic?.requestFormat || 'webm',
}
if (oneMusic.enabled && ![oneMusic.siteUrl, oneMusic.apiBaseUrl, oneMusic.backendBaseUrl].every(value => /^https?:\/\//.test(value))) {
  throw new Error('config/local.json: oneMusic 地址必须是 http(s) URL')
}

const sources = {
  tx: config.sources?.tx !== false,
  wy: config.sources?.wy !== false,
  kw: config.sources?.kw !== false,
  kg: config.sources?.kg === true,
  mg: config.sources?.mg === true,
}

let script = await fs.readFile(templatePath, 'utf8')
script = script
  .replace('__KARPOV_BASE_URL__', escapeForSingleQuotedJsString(config.baseUrl))
  .replace('__KARPOV_API_KEY__', escapeForSingleQuotedJsString(config.apiKey))
  .replace('__GDSTUDIO_CONFIG__', JSON.stringify(gdstudio))
  .replace('__LOCAL_BACKEND_CONFIG__', JSON.stringify(localBackend))
  .replace('__ONE_MUSIC_CONFIG__', JSON.stringify(oneMusic))
  .replace('__YAOHUD_CONFIG__', JSON.stringify(yaohud))
  .replace('__KARPOV_ENABLE_PROBE__', config.enableProbe === false ? 'false' : 'true')
  .replace('__KARPOV_STRICT_MATCH__', config.strictMatch === false ? 'false' : 'true')
  .replace('__KARPOV_SOURCES__', JSON.stringify(sources))

await fs.mkdir(path.dirname(outputPath), { recursive: true })
await fs.writeFile(outputPath, script, 'utf8')
console.log(`已生成：${outputPath}`)
console.log('注意：config/local.json 与 dist/*.js 会包含本地 API Key，已被 .gitignore 忽略。')
