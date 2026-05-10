import http from 'node:http'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'
import Meting from '../vendor/meting/meting.js'
import { getOneMusicConfig, oneMusicSearch, oneMusicMatchUrl } from './one-music-client.mjs'
import { getYaohudConfig, yaohudMusicSearch, yaohudMusicMatchUrl } from './yaohud-client.mjs'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const root = path.resolve(__dirname, '..')
const configPath = path.join(root, 'config', 'local.json')
const DEFAULT_PORT = 47632
const DEFAULT_HOST = '127.0.0.1'
const SUPPORTED_PLATFORMS = new Set(Meting.getSupportedPlatforms())

function readConfig() {
  try {
    return JSON.parse(fs.readFileSync(configPath, 'utf8').replace(/^\uFEFF/, ''))
  } catch (_) {
    return {}
  }
}

function getConfig() {
  const config = readConfig()
  return {
    cookies: config.localBackend?.cookies || {},
    defaultMatchPlatform: config.localBackend?.defaultMatchPlatform || 'kuwo',
    searchLimit: Number(config.localBackend?.searchLimit || 10),
    oneMusic: getOneMusicConfig(config),
    yaohud: getYaohudConfig(config),
  }
}

function writeJson(res, statusCode, data) {
  const body = JSON.stringify(data)
  res.writeHead(statusCode, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(body),
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Cache-Control': 'no-store',
  })
  res.end(body)
}

function normalize(value) {
  return String(value || '')
    .toLowerCase()
    .replace(/[\s·.\-_/()（）【】\[\]《》<>「」『』]/g, '')
}

function splitArtists(value) {
  if (Array.isArray(value)) return value.map(item => String(item).trim()).filter(Boolean)
  return String(value || '')
    .split(/[/,&，、;；]+/)
    .map(item => item.trim())
    .filter(Boolean)
}

function hasArtistMatch(localArtist, remoteArtists) {
  const locals = splitArtists(localArtist).map(normalize).filter(Boolean)
  const remotes = splitArtists(remoteArtists).map(normalize).filter(Boolean)
  if (!locals.length || !remotes.length) return false
  return locals.some(local => remotes.some(remote => remote.includes(local) || local.includes(remote)))
}

function isSameSong(query, item) {
  const localName = normalize(query.name)
  const remoteName = normalize(item.name)
  if (!localName || !remoteName || localName !== remoteName) return false
  if (!hasArtistMatch(query.artist, item.artist)) return false

  const localAlbum = normalize(query.album)
  const remoteAlbum = normalize(item.album)
  if (localAlbum && remoteAlbum && localAlbum !== remoteAlbum) return false

  return true
}

function pickBestMatch(query, list) {
  const exactAlbum = []
  const looseAlbum = []

  for (const item of list) {
    if (!isSameSong(query, item)) continue
    const localAlbum = normalize(query.album)
    const remoteAlbum = normalize(item.album)
    if (localAlbum && remoteAlbum && localAlbum === remoteAlbum) exactAlbum.push(item)
    else looseAlbum.push(item)
  }

  return exactAlbum[0] || looseAlbum[0] || null
}

function getCookie(platform) {
  const config = getConfig()
  const envName = `METING_${platform.toUpperCase()}_COOKIE`
  return process.env[envName] || process.env.METING_COOKIE || config.cookies[platform] || ''
}

function createMeting(platform) {
  if (!SUPPORTED_PLATFORMS.has(platform)) throw new Error(`不支持的平台：${platform}`)
  const meting = new Meting(platform).format(true)
  const cookie = getCookie(platform)
  if (cookie) meting.cookie(cookie)
  return meting
}

function parseJsonResult(raw, fallback) {
  if (typeof raw !== 'string') return raw
  try {
    return JSON.parse(raw)
  } catch (_) {
    return fallback
  }
}

function mapQualityToBr(quality, br) {
  if (br) return Number(br)
  const map = {
    '128k': 128,
    '320k': 320,
    flac: 999,
    flac24bit: 999,
  }
  return map[quality] || 320
}

async function getUrl(platform, id, br) {
  const meting = createMeting(platform)
  const result = parseJsonResult(await meting.url(id, br), {})
  if (!result || !result.url) throw new Error(`${platform} 没有返回播放直链`)
  return result
}

async function search(platform, keyword, page, limit) {
  const meting = createMeting(platform)
  const result = parseJsonResult(await meting.search(keyword, { page, limit }), [])
  return Array.isArray(result) ? result : []
}

async function matchUrl(params) {
  const platform = params.get('platform') || getConfig().defaultMatchPlatform
  const name = params.get('name') || ''
  const artist = params.get('artist') || ''
  const album = params.get('album') || ''
  const quality = params.get('quality') || '320k'
  const br = mapQualityToBr(quality, params.get('br'))
  const limit = Number(params.get('limit') || getConfig().searchLimit || 10)
  const keyword = [artist, name, album].filter(Boolean).join(' ')

  if (!name || !artist) throw new Error('match-url 需要 name 和 artist')

  const list = await search(platform, keyword, 1, limit)
  const match = pickBestMatch({ name, artist, album }, list)
  if (!match) throw new Error(`${platform} 没有找到严格匹配的歌曲`)

  const urlInfo = await getUrl(platform, match.url_id || match.id, br)
  return { ...urlInfo, match, platform }
}

async function handleRequest(req, res) {
  if (req.method === 'OPTIONS') {
    writeJson(res, 204, {})
    return
  }

  const url = new URL(req.url, `http://${req.headers.host || `${DEFAULT_HOST}:${DEFAULT_PORT}`}`)

  try {
    if (url.pathname === '/health') {
      writeJson(res, 200, {
        ok: true,
        service: 'lx-music-source-local-meting',
        platforms: Meting.getSupportedPlatforms(),
        oneMusic: {
          enabled: getConfig().oneMusic.enabled === true,
          hasToken: !!getConfig().oneMusic.turnstileToken,
        },
        yaohud: {
          enabled: getConfig().yaohud.enabled === true,
          hasKey: !!getConfig().yaohud.key,
        },
      })
      return
    }

    if (url.pathname === '/url') {
      const platform = url.searchParams.get('platform') || 'kuwo'
      const id = url.searchParams.get('id')
      const quality = url.searchParams.get('quality') || '320k'
      if (!id) throw new Error('url 接口需要 id')
      const data = await getUrl(platform, id, mapQualityToBr(quality, url.searchParams.get('br')))
      writeJson(res, 200, { ok: true, data: { ...data, platform } })
      return
    }

    if (url.pathname === '/search') {
      const platform = url.searchParams.get('platform') || 'kuwo'
      const keyword = url.searchParams.get('keyword') || ''
      if (!keyword) throw new Error('search 接口需要 keyword')
      const page = Number(url.searchParams.get('page') || 1)
      const limit = Number(url.searchParams.get('limit') || 10)
      const data = await search(platform, keyword, page, limit)
      writeJson(res, 200, { ok: true, data })
      return
    }

    if (url.pathname === '/match-url') {
      const data = await matchUrl(url.searchParams)
      writeJson(res, 200, { ok: true, data })
      return
    }

    const yaohudSearchMatch = url.pathname.match(/^\/yaohud\/([^/]+)\/search$/)
    if (yaohudSearchMatch) {
      const provider = yaohudSearchMatch[1]
      const keyword = url.searchParams.get('keyword') || ''
      if (!keyword) throw new Error(`yaohud/${provider}/search 需要 keyword`)
      const limit = Number(url.searchParams.get('limit') || getConfig().searchLimit || 10)
      const data = await yaohudMusicSearch(provider, keyword, readConfig(), limit)
      writeJson(res, 200, { ok: true, data })
      return
    }

    const yaohudMatch = url.pathname.match(/^\/yaohud\/([^/]+)\/match-url$/)
    if (yaohudMatch) {
      const data = await yaohudMusicMatchUrl(yaohudMatch[1], url.searchParams, readConfig())
      writeJson(res, 200, { ok: true, data })
      return
    }

    if (url.pathname === '/1music/search') {
      const keyword = url.searchParams.get('keyword') || ''
      if (!keyword) throw new Error('1music/search 需要 keyword')
      const data = await oneMusicSearch(keyword, readConfig())
      writeJson(res, 200, { ok: true, data })
      return
    }

    if (url.pathname === '/1music/match-url') {
      const data = await oneMusicMatchUrl(url.searchParams, readConfig())
      writeJson(res, 200, { ok: true, data })
      return
    }

    writeJson(res, 404, { ok: false, message: 'Not found' })
  } catch (error) {
    writeJson(res, 500, { ok: false, message: error instanceof Error ? error.message : String(error) })
  }
}

function startServer() {
  const port = Number(process.env.LX_SOURCE_GATEWAY_PORT || process.argv[2] || DEFAULT_PORT)
  const server = http.createServer((req, res) => {
    void handleRequest(req, res)
  })

  server.listen(port, DEFAULT_HOST, () => {
    console.log(`LX Music local Meting backend listening on http://${DEFAULT_HOST}:${port}`)
    console.log('Press Ctrl+C to stop.')
  })
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  startServer()
}

export { search, getUrl, matchUrl, handleRequest }
