import { describe, expect, mock, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'
import type { On } from 'claude-code'

import { fitRow, folderName, pngSize, tagNumbers } from '../hooks/register.js'

/** A PNG's first 24 bytes: the signature, then IHDR with the size. */
function pngHeader(width: number, height: number): string {
  const bytes = new Uint8Array(24)
  bytes.set([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52])
  const view = new DataView(bytes.buffer)
  view.setUint32(16, width)
  view.setUint32(20, height)
  return bytes.toBase64()
}

const ROOT = '/scratch/claude-501'
const folderOf = (session: string, cwd = '/Users/me/app') => `${ROOT}/${folderName(cwd)}/${session}/images`

const BAND = {
  hasSurvey: false,
  isWorking: false,
  maxRows: 20,
  bodyColumns: 100,
  scroll: { offset: 0, bodyRows: 20 },
  view: {},
}

/** A session the mod runs in: its draft, its id, and the files that exist, all changeable. */
function world(on: On) {
  const state = {
    draft: '',
    session: 'session-1',
    cwd: '/Users/me/app',
    files: new Map<string, string>(), // path → base64 of its first bytes
    folders: new Set<string>(),
    listed: [] as string[], // entries of ROOT
    writes: [] as { path: string; text: string }[],
  }
  mock.env(on, { CALM_SESSION_ID: 'pane-1', CLAUDE_CODE_TMPDIR: '/scratch' })
  on('session.start', () => ({ cwd: state.cwd }))
  on('prompt.read', () => ({ value: { text: state.draft, cursor: state.draft.length } }))
  on('session.id', () => ({ value: state.session }))
  on('session.cwd', () => ({ value: state.cwd }))
  on('process.run', () => ({ value: { exitCode: 0, stdout: '501\n', stderr: '' } }))
  on('fs.exists', ($, e) => ({ value: state.files.has(e.path) || state.folders.has(e.path) }))
  on('fs.read', ($, e) => ({ value: { base64: state.files.get(e.path) ?? '' } }))
  on('fs.list', () => ({ value: state.listed.map(name => ({ name, kind: 'dir', size: 0, mtimeMs: 0, isLink: false })) }))
  on('fs.write', ($, e) => {
    state.writes.push({ path: e.path, text: e.text })
    return { value: undefined }
  })
  on('ui.invalidate', () => ({ value: undefined }))
  // What Claude Code draws in the band when no mod does: nothing of its own here.
  on('ui.render', { component: 'AbovePrompt' }, ($, e) => $.ui.resolve(e).Box({ key: 'engine', children: [] }))
  return {
    state,
    paste(n: number, session = state.session, cwd = state.cwd, size = [800, 400]) {
      const folder = folderOf(session, cwd)
      state.folders.add(folder)
      state.files.set(`${folder}/${n}.png`, pngHeader(size[0], size[1]))
    },
  }
}

async function start($: Engine, cwd: string) {
  await $.session.start({ cwd, surface: 'terminal', isInteractive: true })
}

describe('helpers', () => {
  test('tags are read in order, each once', () => {
    expect(tagNumbers('[Image #2] then [Image #10] and [Image #2] again')).toEqual([2, 10])
    expect(tagNumbers('no pictures here, [Image] #3')).toEqual([])
  })

  test('the working directory becomes the folder name Claude Code uses', () => {
    expect(folderName('/Users/me/dev/apps/calm/.claude/worktrees/a-b')).toBe('-Users-me-dev-apps-calm--claude-worktrees-a-b')
  })

  test("a PNG's size comes from its header", () => {
    expect(pngSize(pngHeader(1999, 1254))).toEqual({ width: 1999, height: 1254 })
    expect(pngSize(new Uint8Array(24).toBase64())).toBe(null)
  })

  test('tiles keep their shape and shrink together to fit', () => {
    const wide = { n: 1, path: '/a', width: 2000, height: 1000 }
    const tall = { n: 2, path: '/b', width: 500, height: 1000 }
    const roomy = fitRow([wide, tall], 200, 20)
    expect(roomy?.map(tile => [tile.columns, tile.rows])).toEqual([[32, 8], [8, 8]])
    // The tall one's tile is as wide as its caption, its picture its own width.
    expect(roomy?.[1].inner).toBe('[Image #2]'.length)
    const tight = fitRow([wide, tall], 40, 20)
    expect(tight?.[0].rows).toBeLessThan(8)
    expect(fitRow([wide, tall], 10, 20)).toBe(null)
    expect(fitRow([wide], 200, 4)).toBe(null) // no room for a frame and a caption
  })
})

describe('the band above the prompt', () => {
  test('draws a captioned picture for each image in the draft', async ($, on) => {
    const clock = mock.clock(on)
    const { state, paste } = world(on)
    paste(1)
    paste(2)
    state.draft = '[Image #1] and [Image #2] what changed?'
    await start($, state.cwd)
    await clock.advance(200)
    const band = await $.ui.mount({ plugin: 'calm', surface: 'terminal', component: 'AbovePrompt', props: BAND })
    const captions = await band.findAll({ type: 'Text', text: /^\[Image #\d+\]$/ })
    expect(captions.length).toBe(2)
    expect((await band.findAll({ type: 'Image' })).length).toBe(2)
  })

  test('draws nothing without a picture, or where pictures cannot show', async ($, on) => {
    const clock = mock.clock(on)
    const { state, paste } = world(on)
    state.draft = 'just words'
    await start($, state.cwd)
    await clock.advance(200)
    const empty = await $.ui.mount({ plugin: 'calm', surface: 'terminal', component: 'AbovePrompt', props: BAND })
    expect(await empty.find({ type: 'Image' })).toBe(undefined)

    paste(1)
    state.draft = '[Image #1]'
    await clock.advance(200)
    const desktop = await $.ui.mount({ plugin: 'calm', surface: 'desktop', component: 'AbovePrompt', props: BAND })
    expect(await desktop.find({ type: 'Text', text: '[Image #1]' })).toBe(undefined)
  })

  test('a picture whose file is not there yet shows once it is', async ($, on) => {
    const clock = mock.clock(on)
    const { state, paste } = world(on)
    state.draft = '[Image #1]'
    await start($, state.cwd)
    await clock.advance(200)
    const before = await $.ui.mount({ plugin: 'calm', surface: 'terminal', component: 'AbovePrompt', props: BAND })
    expect(await before.find({ type: 'Image' })).toBe(undefined)
    paste(1)
    await clock.advance(200)
    const after = await $.ui.mount({ plugin: 'calm', surface: 'terminal', component: 'AbovePrompt', props: BAND })
    expect(await after.find({ type: 'Image' })).not.toBe(undefined)
  })

  test('finds the folder when the working directory moved', async ($, on) => {
    const clock = mock.clock(on)
    const { state, paste } = world(on)
    paste(1, 'session-1', '/Users/me/started-here')
    state.listed = [folderName('/Users/me/elsewhere'), folderName('/Users/me/started-here')]
    state.draft = '[Image #1]'
    await start($, state.cwd)
    await clock.advance(200)
    const band = await $.ui.mount({ plugin: 'calm', surface: 'terminal', component: 'AbovePrompt', props: BAND })
    expect(await band.find({ type: 'Image' })).not.toBe(undefined)
  })
})

describe('what Calm is told', () => {
  test("each session's images folder, newest first, kept across a /clear", async ($, on) => {
    const clock = mock.clock(on)
    const { state, paste } = world(on)
    paste(1)
    state.draft = '[Image #1]'
    await start($, state.cwd)
    await clock.advance(200)
    expect(state.writes.length).toBe(1)
    expect(state.writes[0].path.endsWith('/claude-code-images/pane-1.json')).toBe(true)
    expect(JSON.parse(state.writes[0].text)).toEqual({ folders: [folderOf('session-1')] })

    // A /clear: a new session id, and the numbers go on.
    state.session = 'session-2'
    paste(2, 'session-2')
    state.draft = '[Image #2]'
    await clock.advance(200)
    expect(JSON.parse(state.writes.at(-1)?.text ?? '{}')).toEqual({ folders: [folderOf('session-2'), folderOf('session-1')] })
  })
})
