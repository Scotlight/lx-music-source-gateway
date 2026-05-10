/**
 * @name LX 聚合音源
 * @description 通过 Karpov Gateway 与 GD Studio Music API 为 LX Music 提供音乐直链
 * @version 0.3.0
 * @author local
 * @homepage https://gateway.karpov.cn
 * @source GD Studio Music API: https://music-api.gdstudio.xyz/api.php
 * @source Meting-Agent: https://github.com/ELDment/Meting-Agent
 * @source 1Music.cc: https://1music.cc
 * @source 妖狐数据开放API接口: https://api.yaohud.cn/doc/83
 */

(() => {
  const CONFIG = {
    baseUrl: '__KARPOV_BASE_URL__',
    apiKey: '__KARPOV_API_KEY__',
    gdstudio: __GDSTUDIO_CONFIG__,
    localBackend: __LOCAL_BACKEND_CONFIG__,
    oneMusic: __ONE_MUSIC_CONFIG__,
    yaohud: __YAOHUD_CONFIG__,
    enableProbe: __KARPOV_ENABLE_PROBE__,
    strictMatch: __KARPOV_STRICT_MATCH__,
    sources: __KARPOV_SOURCES__,
  }

  const { EVENT_NAMES, request, on, send } = window.lx

  const SOURCE_MAP = {
    tx: {
      name: 'QQ音乐（Karpov/本地后端）',
      backends: [
        { type: 'karpov', provider: 'qqmusic' },
        { type: 'localYaohudMatch', platform: 'tx' },
        { type: 'localMetingMatch', platform: 'kuwo' },
        { type: 'localOneMusicMatch' },
      ],
    },
    wy: {
      name: '网易云音乐（Karpov/GD Studio/本地后端）',
      backends: [
        { type: 'karpov', provider: 'netease' },
        { type: 'gdstudio', source: 'netease' },
        { type: 'localYaohudMatch', platform: 'wy' },
        { type: 'localMetingMatch', platform: 'kuwo' },
        { type: 'localOneMusicMatch' },
      ],
    },
    kw: {
      name: '酷我音乐（GD Studio/本地后端）',
      backends: [
        { type: 'gdstudio', source: 'kuwo' },
        { type: 'localMetingDirect', platform: 'kuwo' },
        { type: 'localYaohudMatch', platform: 'kw' },
        { type: 'localOneMusicMatch' },
      ],
    },
    kg: {
      name: '酷狗音乐（本地后端）',
      backends: [
        { type: 'localMetingDirect', platform: 'kugou' },
        { type: 'localYaohudMatch', platform: 'kg' },
        { type: 'localOneMusicMatch' },
      ],
    },
    mg: {
      name: '咪咕音乐（本地后端）',
      backends: [
        { type: 'localYaohudMatch', platform: 'mg' },
        { type: 'localOneMusicMatch' },
      ],
    },
  }

  const KARPOV_QUALITY_MAP = {
    '128k': 'MP3_128',
    '320k': 'MP3_320',
    flac: 'FLAC',
    flac24bit: 'FLAC',
  }

  const GDSTUDIO_QUALITY_MAP = {
    '128k': '128',
    '320k': '320',
    flac: '999',
    flac24bit: '999',
  }

  const trimEndSlash = value => String(value || '').replace(/\/+$/, '')
  const normalize = value => String(value || '')
    .toLowerCase()
    .replace(/[\s·.\-_/()（）【】\[\]《》<>]/g, '')

  const parseInterval = value => {
    if (!value) return null
    if (typeof value === 'number') return value
    const parts = String(value).split(':').map(part => Number.parseInt(part, 10))
    if (parts.some(Number.isNaN)) return null
    return parts.reduce((total, part) => total * 60 + part, 0)
  }

  const parseBody = body => {
    if (!body) return body
    if (typeof body === 'object') return body
    if (typeof body !== 'string') return body
    const text = body.trim()
    if (!text) return null
    try {
      return JSON.parse(text)
    } catch (_) {
      return body
    }
  }

  const httpRequest = (url, options = {}) => new Promise((resolve, reject) => {
    request(url, options, (err, resp, body) => {
      if (err) return reject(err)
      resolve({ resp, body: parseBody(body) })
    })
  })

  const assertHttpOk = (resp, body, backendName) => {
    if (resp && resp.statusCode >= 200 && resp.statusCode < 300) return
    const code = resp ? resp.statusCode : 'unknown'
    const message = body && typeof body === 'object' && body.message ? body.message : `HTTP ${code}`
    throw new Error(`${backendName} 请求失败：${message}`)
  }

  const gatewayRequest = async path => {
    const url = `${trimEndSlash(CONFIG.baseUrl)}${path}`
    const { resp, body } = await httpRequest(url, {
      method: 'get',
      timeout: 20000,
      headers: {
        Accept: 'application/json',
        'X-Client-App': 'LX Music Custom Source',
        'X-API-Key': CONFIG.apiKey,
      },
    })

    assertHttpOk(resp, body, 'Karpov')
    if (!body || typeof body !== 'object') throw new Error('Karpov 返回不是 JSON')
    if (body.code !== 200 && body.code !== 0) throw new Error(body.message || `Karpov 错误：${body.code}`)
    return body.data
  }

  const gdstudioRequest = async params => {
    const baseUrl = CONFIG.gdstudio && CONFIG.gdstudio.baseUrl
    if (!baseUrl) throw new Error('GD Studio 地址为空')

    const search = new URLSearchParams(params)
    const separator = String(baseUrl).includes('?') ? '&' : '?'
    const url = `${baseUrl}${separator}${search.toString()}`
    const { resp, body } = await httpRequest(url, {
      method: 'get',
      timeout: 20000,
      headers: { Accept: 'application/json' },
    })

    assertHttpOk(resp, body, 'GD Studio')
    if (!body || typeof body !== 'object' || Array.isArray(body)) throw new Error('GD Studio 返回不是 JSON')
    if (body.detail) throw new Error(`GD Studio 错误：${body.detail}`)
    return body
  }


  const localBackendRequest = async(endpoint, params) => {
    const baseUrl = CONFIG.localBackend && CONFIG.localBackend.baseUrl
    if (!baseUrl) throw new Error('本地后端地址为空')

    const search = new URLSearchParams(params)
    const url = `${trimEndSlash(baseUrl)}${endpoint}?${search.toString()}`
    const { resp, body } = await httpRequest(url, {
      method: 'get',
      timeout: 25000,
      headers: { Accept: 'application/json' },
    })

    assertHttpOk(resp, body, '本地 Meting 后端')
    if (!body || typeof body !== 'object') throw new Error('本地 Meting 后端返回不是 JSON')
    if (!body.ok) throw new Error(body.message || '本地 Meting 后端请求失败')
    return body.data
  }

  const isUsableAudioUrl = async url => {
    const checkResp = resp => {
      if (!resp || resp.statusCode < 200 || resp.statusCode >= 400) return false
      const headers = resp.headers || {}
      const contentType = String(headers['content-type'] || headers['Content-Type'] || '').toLowerCase()
      const contentLength = Number(headers['content-length'] || headers['Content-Length'] || 0)
      return contentType.startsWith('audio/') || contentLength > 0 || /\.(mp3|flac|m4a|aac|ogg)(\?|$)/i.test(url)
    }

    try {
      const { resp } = await httpRequest(url, { method: 'head', timeout: 8000 })
      if (checkResp(resp)) return true
    } catch (_) {}

    try {
      const { resp } = await httpRequest(url, {
        method: 'get',
        timeout: 10000,
        headers: { Range: 'bytes=0-4095' },
      })
      return checkResp(resp)
    } catch (_) {
      return false
    }
  }

  const assertSameSong = (musicInfo, remoteSong) => {
    if (!CONFIG.strictMatch || !remoteSong) return

    const localTitle = normalize(musicInfo.name)
    const remoteTitle = normalize(remoteSong.title)
    if (localTitle && remoteTitle && localTitle !== remoteTitle) {
      throw new Error(`歌曲名不匹配：${musicInfo.name} / ${remoteSong.title}`)
    }

    const localArtist = normalize(musicInfo.singer)
    const remoteArtist = normalize(remoteSong.artist)
    if (localArtist && remoteArtist && !remoteArtist.includes(localArtist) && !localArtist.includes(remoteArtist)) {
      throw new Error(`歌手不匹配：${musicInfo.singer} / ${remoteSong.artist}`)
    }

    const localAlbum = normalize(musicInfo.albumName)
    const remoteAlbum = normalize(remoteSong.album)
    if (localAlbum && remoteAlbum && localAlbum !== remoteAlbum) {
      throw new Error(`专辑不匹配：${musicInfo.albumName} / ${remoteSong.album}`)
    }

    const localDuration = parseInterval(musicInfo.interval)
    const remoteDuration = Number(remoteSong.durationSeconds)
    if (localDuration && remoteDuration && Math.abs(localDuration - remoteDuration) > 5) {
      throw new Error(`时长不匹配：${localDuration}s / ${remoteDuration}s`)
    }
  }

  const getQualityHash = (musicInfo, lxQuality) => {
    if (!musicInfo) return null
    const typeHash = musicInfo._types && musicInfo._types[lxQuality] && musicInfo._types[lxQuality].hash
    if (typeHash) return typeHash
    const typeInfo = Array.isArray(musicInfo.types) ? musicInfo.types.find(item => item.type === lxQuality) : null
    return typeInfo && typeInfo.hash ? typeInfo.hash : null
  }

  const getSongId = (source, musicInfo, lxQuality) => {
    if (source === 'kg') return getQualityHash(musicInfo, lxQuality) || musicInfo.hash || musicInfo.songmid || musicInfo.id || musicInfo.songId
    return musicInfo.songmid || musicInfo.id || musicInfo.songId || musicInfo.hash
  }

  const isBackendEnabled = backend => {
    if (backend.type === 'gdstudio') return !!CONFIG.gdstudio && CONFIG.gdstudio.enabled !== false
    if (backend.type === 'localMetingDirect') return !!CONFIG.localBackend && CONFIG.localBackend.enabled === true
    if (backend.type === 'localMetingMatch') {
      return !!CONFIG.localBackend && CONFIG.localBackend.enabled === true && CONFIG.localBackend.matchFallback === true
    }
    if (backend.type === 'localOneMusicMatch') {
      return !!CONFIG.localBackend && CONFIG.localBackend.enabled === true && !!CONFIG.oneMusic && CONFIG.oneMusic.enabled === true
    }
    if (backend.type === 'localYaohudMatch') {
      return !!CONFIG.localBackend && CONFIG.localBackend.enabled === true && !!CONFIG.yaohud && CONFIG.yaohud.enabled === true
    }
    return true
  }

  const getKarpovMusicUrl = async(backend, musicInfo, songId, lxQuality) => {
    const quality = KARPOV_QUALITY_MAP[lxQuality] || 'MP3_320'
    const path = `/api/proxy/${backend.provider}/songs/${encodeURIComponent(songId)}/url?quality=${encodeURIComponent(quality)}`
    const data = await gatewayRequest(path)
    const audio = data && data.audio
    if (!audio || !audio.url) throw new Error('Karpov 没有返回音频直链')

    assertSameSong(musicInfo, data.song)
    return audio.url
  }

  const getGdstudioMusicUrl = async(backend, songId, lxQuality) => {
    const data = await gdstudioRequest({
      types: 'url',
      source: backend.source,
      id: songId,
      br: GDSTUDIO_QUALITY_MAP[lxQuality] || '320',
    })

    if (!data.url) throw new Error('GD Studio 没有返回音频直链')
    return data.url
  }

  const getLocalMetingDirectUrl = async(backend, songId, lxQuality) => {
    const data = await localBackendRequest('/url', {
      platform: backend.platform,
      id: songId,
      quality: lxQuality,
    })
    if (!data.url) throw new Error('本地 Meting 后端没有返回音频直链')
    return data.url
  }

  const getLocalMetingMatchUrl = async(backend, musicInfo, lxQuality) => {
    const data = await localBackendRequest('/match-url', {
      platform: backend.platform,
      name: musicInfo.name || '',
      artist: musicInfo.singer || '',
      album: musicInfo.albumName || musicInfo.album || '',
      quality: lxQuality,
    })
    if (!data.url) throw new Error('本地 Meting 后端没有返回匹配直链')
    return data.url
  }

  const getLocalYaohudMatchUrl = async(backend, musicInfo, lxQuality) => {
    const data = await localBackendRequest(`/yaohud/${encodeURIComponent(backend.platform)}/match-url`, {
      name: musicInfo.name || '',
      artist: musicInfo.singer || '',
      album: musicInfo.albumName || musicInfo.album || '',
      quality: lxQuality,
    })
    if (!data.url) throw new Error('本地妖狐音乐后端没有返回匹配直链')
    return data.url
  }

  const getLocalOneMusicMatchUrl = async(musicInfo, lxQuality) => {
    const data = await localBackendRequest('/1music/match-url', {
      name: musicInfo.name || '',
      artist: musicInfo.singer || '',
      album: musicInfo.albumName || musicInfo.album || '',
      quality: lxQuality,
    })
    if (!data.url) throw new Error('本地 1Music 后端没有返回匹配直链')
    return data.url
  }

  const getBackendMusicUrl = (backend, musicInfo, songId, lxQuality) => {
    if (backend.type === 'karpov') return getKarpovMusicUrl(backend, musicInfo, songId, lxQuality)
    if (backend.type === 'gdstudio') return getGdstudioMusicUrl(backend, songId, lxQuality)
    if (backend.type === 'localMetingDirect') return getLocalMetingDirectUrl(backend, songId, lxQuality)
    if (backend.type === 'localMetingMatch') return getLocalMetingMatchUrl(backend, musicInfo, lxQuality)
    if (backend.type === 'localOneMusicMatch') return getLocalOneMusicMatchUrl(musicInfo, lxQuality)
    if (backend.type === 'localYaohudMatch') return getLocalYaohudMatchUrl(backend, musicInfo, lxQuality)
    throw new Error(`未知后端：${backend.type}`)
  }

  const getMusicUrl = async(source, musicInfo, lxQuality) => {
    const sourceInfo = SOURCE_MAP[source]
    if (!sourceInfo) throw new Error(`不支持的 LX 源：${source}`)

    const songId = getSongId(source, musicInfo, lxQuality)
    if (!songId) throw new Error('缺少歌曲 ID')

    const errors = []
    for (const backend of sourceInfo.backends) {
      if (!isBackendEnabled(backend)) continue

      try {
        const url = await getBackendMusicUrl(backend, musicInfo, songId, lxQuality)
        if (CONFIG.enableProbe) {
          const ok = await isUsableAudioUrl(url)
          if (!ok) throw new Error('音频直链探测失败')
        }
        return url
      } catch (error) {
        errors.push(`${backend.type}: ${error.message || error}`)
      }
    }

    throw new Error(errors.length ? errors.join('；') : '没有可用后端')
  }

  on(EVENT_NAMES.request, ({ source, action, info }) => {
    if (action !== 'musicUrl') return Promise.reject(new Error(`不支持的操作：${action}`))
    return getMusicUrl(source, info.musicInfo, info.type)
  })

  const enabledSources = {}
  for (const [source, enabled] of Object.entries(CONFIG.sources || {})) {
    if (!enabled || !SOURCE_MAP[source]) continue
    enabledSources[source] = {
      name: SOURCE_MAP[source].name,
      type: 'music',
      actions: ['musicUrl'],
      qualitys: ['128k', '320k', 'flac', 'flac24bit'],
    }
  }

  send(EVENT_NAMES.inited, {
    status: true,
    openDevTools: false,
    sources: enabledSources,
  })
})()
