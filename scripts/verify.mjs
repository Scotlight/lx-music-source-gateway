import fs from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const root = path.resolve(__dirname, '..')
const configPath = path.join(root, 'config', 'local.json')
const config = JSON.parse(await fs.readFile(configPath, 'utf8'))

const baseUrl = String(config.baseUrl || '').replace(/\/+$/, '')
const apiKey = config.apiKey
if (!baseUrl || !apiKey) throw new Error('请先配置 config/local.json')

const headers = {
  Accept: 'application/json',
  'X-Client-App': 'LX Music Custom Source Verify',
  'X-API-Key': apiKey,
}

const samples = [
  { provider: 'qqmusic', id: '0039MnYb0qxYhV', name: '周杰伦 - 晴天', quality: 'MP3_128' },
  { provider: 'netease', id: '186016', name: '周杰伦 - 晴天', quality: 'MP3_128', allowUrlFail: true },
  { provider: 'netease', id: '108914', name: '林俊杰 - 江南', quality: 'MP3_128' },
]

async function readJson(url) {
  const resp = await fetch(url, { headers })
  const text = await resp.text()
  let json
  try { json = JSON.parse(text) } catch {}
  return { resp, text, json }
}

async function probeAudio(url) {
  const resp = await fetch(url, { headers: { Range: 'bytes=0-4095' } })
  const buf = Buffer.from(await resp.arrayBuffer())
  return {
    status: resp.status,
    statusText: resp.statusText,
    contentType: resp.headers.get('content-type'),
    bytes: buf.length,
    magic: buf.subarray(0, 12).toString('hex'),
  }
}

let failed = false
for (const sample of samples) {
  const apiUrl = `${baseUrl}/api/proxy/${sample.provider}/songs/${encodeURIComponent(sample.id)}/url?quality=${encodeURIComponent(sample.quality)}`
  const result = await readJson(apiUrl)
  const audio = result.json?.data?.audio
  const song = result.json?.data?.song
  console.log('\n---')
  console.log(`${sample.provider} / ${sample.id} / ${sample.name}`)
  console.log(`url api: HTTP ${result.resp.status}, code=${result.json?.code}, message=${result.json?.message}`)
  if (song) console.log(`song: ${song.title} / ${song.artist} / ${song.album || ''}`)

  if (!audio?.url) {
    console.log('audio: no url')
    if (!sample.allowUrlFail) failed = true
    continue
  }

  const probe = await probeAudio(audio.url)
  console.log(`audio: ${audio.quality}, ${audio.format}, ${audio.sizeBytes || 0} bytes`)
  console.log(`probe: HTTP ${probe.status}, ${probe.contentType}, ${probe.bytes} bytes, magic=${probe.magic}`)
  if (!(probe.status >= 200 && probe.status < 400 && probe.bytes > 0)) failed = true
}

if (failed) process.exitCode = 1
