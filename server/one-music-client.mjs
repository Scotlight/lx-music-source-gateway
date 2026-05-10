const DEFAULT_CONFIG = {
  enabled: false,
  siteUrl: 'https://1music.cc',
  apiBaseUrl: 'https://api.1music.cc',
  backendBaseUrl: 'https://backend.1music.cc',
  turnstileToken: '',
  requestFormat: 'webm',
}

function trimEndSlash(value) {
  return String(value || '').replace(/\/+$/, '')
}

function getOneMusicConfig(config = {}) {
  return {
    ...DEFAULT_CONFIG,
    ...(config.oneMusic || {}),
  }
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

function isSameSong(query, item) {
  const localName = normalize(query.name)
  const remoteName = normalize(item.name)
  if (!localName || !remoteName || localName !== remoteName) return false
  if (!hasArtistMatch(query.artist, item.artist)) return false

  const localAlbum = normalize(query.album)
  const remoteAlbum = normalize(item.album)
  return !localAlbum || !remoteAlbum || localAlbum === remoteAlbum
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

function mapOneMusicSong(item) {
  return {
    id: item.song_hash,
    url_id: item.song_hash,
    name: item.title || '',
    artist: item.artist || '',
    album: item.album || '',
    thumbnail: item.thumbnail || '',
    videoId: item.videoId || '',
    source: '1music',
    raw: item,
  }
}

async function readJsonResponse(response, serviceName) {
  const text = await response.text()
  let body
  try {
    body = JSON.parse(text)
  } catch (_) {
    throw new Error(`${serviceName} 返回不是 JSON：HTTP ${response.status}`)
  }
  if (!response.ok) {
    const message = body && (body.detail || body.message) ? (body.detail || body.message) : `HTTP ${response.status}`
    throw new Error(`${serviceName} 请求失败：${message}`)
  }
  return body
}

async function oneMusicSearch(keyword, config) {
  const oneMusic = getOneMusicConfig(config)
  if (!oneMusic.enabled) throw new Error('1Music 后端未启用')
  if (!oneMusic.turnstileToken) throw new Error('缺少 1Music Turnstile token，请运行 lx-source-gateway.cmd 后选择启用/刷新 1Music')

  const url = new URL('/search', `${trimEndSlash(oneMusic.apiBaseUrl)}/`)
  url.searchParams.set('songs', keyword)
  url.searchParams.set('token', oneMusic.turnstileToken)

  const response = await fetch(url, {
    headers: {
      Accept: 'application/json, text/plain, */*',
      Referer: `${trimEndSlash(oneMusic.siteUrl)}/`,
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36',
    },
  })

  const body = await readJsonResponse(response, '1Music 搜索')
  if (!Array.isArray(body)) throw new Error('1Music 搜索返回不是数组')
  return body.map(mapOneMusicSong).filter(item => item.id && item.videoId)
}

async function oneMusicDownloadUrl(song, config) {
  const oneMusic = getOneMusicConfig(config)
  const response = await fetch(`${trimEndSlash(oneMusic.backendBaseUrl)}/download/`, {
    method: 'POST',
    headers: {
      Accept: 'application/json, text/plain, */*',
      'Content-Type': 'application/json',
      Referer: `${trimEndSlash(oneMusic.siteUrl)}/`,
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36',
    },
    body: JSON.stringify({
      title: song.name,
      album: song.album,
      artist: Array.isArray(song.artist) ? song.artist.join('、') : song.artist,
      videoId: song.videoId,
      request_format: oneMusic.requestFormat || 'webm',
      song_hash: song.id,
      thumbnail: song.thumbnail || '',
    }),
  })

  const body = await readJsonResponse(response, '1Music 下载')
  if (!body.download_url) throw new Error('1Music 没有返回 download_url')
  return body.download_url
}

async function oneMusicMatchUrl(params, config) {
  const name = params.get('name') || ''
  const artist = params.get('artist') || ''
  const album = params.get('album') || ''
  const limit = Number(params.get('limit') || config.localBackend?.searchLimit || 10)
  if (!name || !artist) throw new Error('1music/match-url 需要 name 和 artist')

  const keyword = [artist, name, album].filter(Boolean).join(' ')
  const list = await oneMusicSearch(keyword, config)
  const match = pickBestMatch({ name, artist, album }, list.slice(0, limit))
  if (!match) throw new Error('1Music 没有找到严格匹配的歌曲')

  const url = await oneMusicDownloadUrl(match, config)
  return {
    url,
    match,
    platform: '1music',
    format: getOneMusicConfig(config).requestFormat || 'webm',
  }
}

export { getOneMusicConfig, oneMusicSearch, oneMusicDownloadUrl, oneMusicMatchUrl }
