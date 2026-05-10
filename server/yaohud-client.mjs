const DEFAULT_CONFIG = {
  enabled: false,
  apiBaseUrl: 'https://api.yaohud.cn',
  key: '',
  defaultQuality: 'flac',
  qualities: {},
  cookies: {},
  kugouCookie: '',
}

const PROVIDERS = {
  tx: {
    name: 'QQ',
    endpoint: '/api/music/qq',
    limitParam: 'g',
    qualityParam: 'size',
    defaultQuality: '320',
    qualityMap: { '128k': '128', '320k': '320', flac: 'flac', flac24bit: 'flac' },
    cookieKeys: ['tx', 'qq'],
  },
  wy: {
    name: '网易',
    endpoint: '/api/music/wy',
    limitParam: 'g',
  },
  kw: {
    name: '酷我',
    endpoint: '/api/music/kuwo',
    limitParam: 'g',
    qualityParam: 'size',
    defaultQuality: 'lossless',
    qualityMap: { '128k': 'Standard', '320k': 'SQ', flac: 'lossless', flac24bit: 'hires' },
  },
  kg: {
    name: '酷狗',
    endpoint: '/api/music/kg',
    limitParam: 'g',
    qualityParam: 'quality',
    defaultQuality: 'flac',
    qualityMap: {
      '128k': '128',
      '320k': '320',
      flac: 'flac',
      flac24bit: 'high',
    },
    cookieKeys: ['kg', 'kugou'],
  },
  mg: {
    name: '咪咕',
    endpoint: '/api/music/migu',
    limitParam: 'num',
  },
}

const PROVIDER_ALIASES = {
  qq: 'tx',
  tencent: 'tx',
  netease: 'wy',
  kuwo: 'kw',
  kugou: 'kg',
  migu: 'mg',
}

function trimEndSlash(value) {
  return String(value || '').replace(/\/+$/, '')
}

function normalizeProvider(provider) {
  const key = String(provider || '').trim().toLowerCase()
  return PROVIDER_ALIASES[key] || key
}

function getProvider(provider) {
  const key = normalizeProvider(provider)
  const definition = PROVIDERS[key]
  if (!definition) throw new Error(`妖狐音乐 API 不支持平台：${provider}`)
  return { key, ...definition }
}

function getYaohudConfig(config = {}) {
  const yaohud = {
    ...DEFAULT_CONFIG,
    ...(config.yaohud || {}),
  }
  yaohud.qualities = {
    ...(DEFAULT_CONFIG.qualities || {}),
    ...(yaohud.qualities || {}),
  }
  yaohud.cookies = {
    ...(DEFAULT_CONFIG.cookies || {}),
    ...(yaohud.cookies || {}),
  }
  return yaohud
}

function mapQuality(provider, quality, yaohud) {
  const definition = getProvider(provider)
  const configured = yaohud.qualities?.[definition.key]
    || yaohud[`${definition.key}Quality`]
    || (definition.key === 'kg' ? yaohud.defaultQuality : '')
  if (!definition.qualityParam) return ''
  return definition.qualityMap?.[quality] || configured || definition.defaultQuality || ''
}

function getCookie(provider, yaohud) {
  const definition = getProvider(provider)
  if (definition.key === 'kg' && yaohud.kugouCookie) return yaohud.kugouCookie
  for (const key of definition.cookieKeys || []) {
    const value = yaohud.cookies?.[key] || yaohud[`${key}Cookie`]
    if (value) return value
  }
  return ''
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

function hasArtistMatch(localArtist, remoteArtist) {
  const locals = splitArtists(localArtist).map(normalize).filter(Boolean)
  const remotes = splitArtists(remoteArtist).map(normalize).filter(Boolean)
  if (!locals.length || !remotes.length) return false
  return locals.some(local => remotes.some(remote => remote.includes(local) || local.includes(remote)))
}

function getSongName(item) {
  return item?.name || item?.title || item?.song || item?.songname || ''
}

function getSongArtist(item) {
  return item?.singer || item?.artist || item?.author || item?.artists || ''
}

function getSongAlbum(item) {
  return item?.album || item?.albumName || item?.album_name || ''
}

function isSameSong(query, item) {
  const localName = normalize(query.name)
  const remoteName = normalize(getSongName(item))
  if (!localName || !remoteName || localName !== remoteName) return false
  if (!hasArtistMatch(query.artist, getSongArtist(item))) return false
  const localAlbum = normalize(query.album)
  const remoteAlbum = normalize(getSongAlbum(item))
  return !localAlbum || !remoteAlbum || localAlbum === remoteAlbum
}

function pickBestMatch(query, songs) {
  const exactAlbum = []
  const looseAlbum = []
  for (const song of songs || []) {
    if (!isSameSong(query, song)) continue
    const localAlbum = normalize(query.album)
    const remoteAlbum = normalize(getSongAlbum(song))
    if (localAlbum && remoteAlbum && localAlbum === remoteAlbum) exactAlbum.push(song)
    else looseAlbum.push(song)
  }
  return exactAlbum[0] || looseAlbum[0] || null
}

function readSongList(body) {
  const data = body?.data
  if (Array.isArray(data?.songs)) return data.songs
  if (Array.isArray(data?.list)) return data.list
  if (Array.isArray(data?.data)) return data.data
  if (Array.isArray(data)) return data
  return []
}

function readAudioUrl(data) {
  return data?.play_url
    || data?.url
    || data?.music_url
    || data?.audio_url
    || data?.link
    || data?.src
    || data?.song_url
    || ''
}

async function readJsonResponse(response) {
  const text = await response.text()
  let body
  try {
    body = JSON.parse(text)
  } catch (_) {
    throw new Error(`妖狐 API 返回不是 JSON：HTTP ${response.status}`)
  }
  if (!response.ok || body.code !== 200) {
    throw new Error(body.msg || body.message || `妖狐 API 请求失败：HTTP ${response.status}`)
  }
  return body
}

async function requestYaohudMusic(provider, params, config) {
  const yaohud = getYaohudConfig(config)
  if (!yaohud.enabled) throw new Error('妖狐音乐 API 未启用')
  if (!yaohud.key) throw new Error('缺少妖狐 API key')

  const definition = getProvider(provider)
  const url = new URL(definition.endpoint, `${trimEndSlash(yaohud.apiBaseUrl)}/`)
  url.searchParams.set('key', yaohud.key)
  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined && value !== null && String(value) !== '') url.searchParams.set(key, value)
  }

  const cookie = getCookie(definition.key, yaohud)
  if (cookie) url.searchParams.set('cookie', cookie)

  const response = await fetch(url, { headers: { Accept: 'application/json' } })
  return readJsonResponse(response)
}

async function yaohudMusicSearch(provider, keyword, config, limit = 12) {
  const definition = getProvider(provider)
  const body = await requestYaohudMusic(definition.key, {
    msg: keyword,
    [definition.limitParam || 'g']: limit,
  }, config)
  return readSongList(body)
}

async function yaohudMusicMatchUrl(provider, params, config) {
  const definition = getProvider(provider)
  const name = params.get('name') || ''
  const artist = params.get('artist') || ''
  const album = params.get('album') || ''
  const limit = Number(params.get('limit') || config.localBackend?.searchLimit || 10)
  if (!name || !artist) throw new Error(`yaohud/${definition.key}/match-url 需要 name 和 artist`)

  const yaohud = getYaohudConfig(config)
  const keyword = [artist, name, album].filter(Boolean).join(' ')
  const songs = await yaohudMusicSearch(definition.key, keyword, config, limit)
  const match = pickBestMatch({ name, artist, album }, songs)
  if (!match) throw new Error(`妖狐${definition.name} API 没有找到严格匹配的歌曲`)

  const quality = mapQuality(definition.key, params.get('quality'), yaohud)
  const requestParams = {
    msg: keyword,
    n: match.n,
    [definition.limitParam || 'g']: limit,
  }
  if (definition.qualityParam && quality) requestParams[definition.qualityParam] = quality

  const body = await requestYaohudMusic(definition.key, requestParams, config)
  const data = body.data || {}
  const url = readAudioUrl(data)
  if (!url) throw new Error(`妖狐${definition.name} API 没有返回播放直链`)
  return {
    url,
    match,
    platform: `yaohud-${definition.key}`,
    quality: data.selected_quality || data.quality || quality,
    raw: data,
  }
}

export { PROVIDERS, getYaohudConfig, yaohudMusicSearch, yaohudMusicMatchUrl }
