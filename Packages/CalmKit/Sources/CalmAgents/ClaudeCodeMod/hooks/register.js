// Calm's mod for Claude Code (FEATURES.md → F8, DESIGNS.md → Agents). It ships in the plugin Calm
// loads in its own shells (`ClaudeCodeAdapter.pluginFiles`), so sessions outside Calm never see it.
//
// - Above the prompt, a picture of each image pasted into the draft, captioned with its tag,
//   `[Image #4]`: the caption is how Calm's ⌘-hover finds which image a picture is.
// - For Calm, the folders this pane's pasted images are kept in, written to
//   `agents/claude-code-images/<CALM_SESSION_ID>.json` beside the plugin, so ⌘-hover finds an
//   image in the transcript too, from before a /clear included.
//
// Claude Code keeps a pasted image as `<tmp>/claude-<uid>/<cwd as a folder name>/<session id>/images/<n>.png`,
// `<n>` the number in its tag, while it is still in the draft (seen in 2.1.291). `CLAUDE_CODE_TMPDIR`
// stands in for `/tmp`. A /clear starts a new session id, but the numbers go on counting, so a
// number names one image across all of this process's sessions. Pasting raises no `prompt.edit`,
// so the draft is read on a timer.

const POLL_MS = 200
// A picture's rows at most, and at least before the row gives up on pictures.
const MOST_ROWS = 8
const FEWEST_ROWS = 2
// A terminal cell is about twice as tall as it is wide.
const CELL_ASPECT = 2

let tmpRoot // `<tmp>/claude-<uid>`, once known
let sessionID
let folder // the session's images folder, once it exists
let folders = [] // every session's images folder this process found, newest first
let handoff // where Calm reads `folders`, or null outside Calm
let shown = [] // { n, path, width, height } for each picture drawn
let isPolling = false
const sizes = new Map() // path → { width, height } | null

/** The tags' numbers in a draft, in order, each once. */
export function tagNumbers(text) {
  const numbers = []
  for (const match of text.matchAll(/\[Image #(\d+)\]/g)) {
    const n = Number(match[1])
    if (!numbers.includes(n)) numbers.push(n)
  }
  return numbers
}

/** `/Users/me/app` → `-Users-me-app`: Claude Code's folder name for a working directory. */
export function folderName(path) {
  return path.replace(/[^A-Za-z0-9]/g, '-')
}

/** A PNG's size from its header, or null when the bytes aren't a PNG's. */
export function pngSize(base64) {
  const bytes = Uint8Array.fromBase64(base64.slice(0, 32))
  const signature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]
  if (bytes.length < 24 || signature.some((byte, i) => bytes[i] !== byte)) return null
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength)
  return { width: view.getUint32(16), height: view.getUint32(20) }
}

/**
 * Each picture's cells in one row of framed tiles that fits `columns` and `rows`: as tall as
 * the room allows up to MOST_ROWS, each keeping its shape, all shrinking together. A tile is its
 * picture plus a frame and a caption line. Null when even the smallest row doesn't fit.
 */
export function fitRow(pictures, columns, rows) {
  const tallest = Math.min(MOST_ROWS, rows - 3)
  for (let height = tallest; height >= FEWEST_ROWS; height -= 1) {
    const tiles = pictures.map(image => {
      const aspect = image.width > 0 && image.height > 0 ? image.width / image.height : 4 / 3
      const width = Math.max(1, Math.min(255, Math.round(height * aspect * CELL_ASPECT)))
      const inner = Math.max(width, caption(image.n).length)
      return { ...image, columns: width, rows: height, inner }
    })
    const used = tiles.reduce((sum, tile) => sum + tile.inner + 2, 0) + tiles.length - 1
    if (used <= columns) return tiles
  }
  return null
}

function caption(n) {
  return `[Image #${n}]`
}

async function findTmpRoot($) {
  if (tmpRoot !== undefined) return tmpRoot
  const tmp = (await $.env.get('CLAUDE_CODE_TMPDIR')) || '/tmp'
  const uid = (await $.process.run(['id', '-u'])).stdout.trim()
  tmpRoot = `${tmp.replace(/\/$/, '')}/claude-${uid}`
  return tmpRoot
}

/** The session's images folder: under its working directory's folder, or wherever it went. */
async function findFolder($) {
  const id = await $.session.id()
  if (id !== sessionID) {
    sessionID = id
    folder = undefined
  }
  if (folder !== undefined) return folder
  const root = await findTmpRoot($)
  const named = `${root}/${folderName(await $.session.cwd())}/${id}/images`
  if (await $.fs.exists(named)) {
    folder = named
  } else {
    // The working directory may have moved since the session started.
    const entries = (await $.fs.list(root).catch(() => [])).filter(entry => entry.kind === 'dir')
    const candidates = entries.map(entry => `${root}/${entry.name}/${id}/images`)
    const there = await Promise.all(candidates.map(candidate => $.fs.exists(candidate)))
    folder = candidates[there.indexOf(true)]
  }
  if (folder !== undefined && !folders.includes(folder)) {
    folders = [folder, ...folders]
    await tellCalm($)
  }
  return folder
}

async function tellCalm($) {
  if (handoff === undefined) {
    const pane = await $.env.get('CALM_SESSION_ID')
    const agents = $.plugin.root.replace(/\/[^/]+\/?$/, '')
    handoff = pane ? `${agents}/claude-code-images/${pane}.json` : null
  }
  if (handoff === null) return
  await $.fs.write(handoff, JSON.stringify({ folders }) + '\n').catch(() => {})
}

async function picture($, dir, n) {
  const path = `${dir}/${n}.png`
  if (!(await $.fs.exists(path))) return null
  if (!sizes.has(path)) {
    // A file over what one read may copy draws all the same, at a guessed shape.
    const size = await $.fs.read(path, { as: 'bytes' }).then(({ base64 }) => pngSize(base64), () => undefined)
    if (size === null) return null
    sizes.set(path, size ?? { width: 0, height: 0 })
  }
  return { n, path, ...sizes.get(path) }
}

async function poll($) {
  if (isPolling) return
  isPolling = true
  try {
    const numbers = tagNumbers((await $.prompt.read()).text)
    // The folder first, once, so the lookups below don't each look for it and record it twice.
    const dir = numbers.length > 0 ? await findFolder($) : undefined
    const found = dir === undefined ? [] : await Promise.all(numbers.map(n => picture($, dir, n)))
    const pictures = found.filter(Boolean)
    if (JSON.stringify(pictures) !== JSON.stringify(shown)) {
      shown = pictures
      $.ui.invalidate('ui.render')
    }
  } finally {
    isPolling = false
  }
}

export function register(on) {
  on('session.start', async ($, e, next) => {
    $.clock.every(POLL_MS, () => {
      poll($).catch(() => {})
    })
    return next(e)
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (shown.length === 0 || e.surface !== 'terminal' || e.props.hasSurvey) return next(e)
    const tiles = fitRow(shown, e.props.bodyColumns, e.props.maxRows)
    if (tiles === null) return next(e)
    const { Box, Text, Image } = $.ui.resolve(e)
    const row = Box({
      flexDirection: 'row',
      columnGap: 1,
      children: tiles.map(tile =>
        Box({
          key: `image-${tile.n}`,
          flexDirection: 'column',
          alignItems: 'center',
          width: tile.inner + 2,
          borderStyle: 'round',
          borderDimColor: true,
          children: [
            Image({
              key: `picture-${tile.n}`,
              source: { file: tile.path, format: 'png' },
              columns: tile.columns,
              rows: tile.rows,
              // Where the terminal can't draw it (inside tmux, say), the caption under it says it all.
              alt: ' ',
            }),
            Text({ dimColor: true, children: [caption(tile.n)] }),
          ],
        }),
      ),
    })
    const theirs = await next(e)
    return theirs ? Box({ flexDirection: 'column', children: [row, theirs] }) : row
  })
}
