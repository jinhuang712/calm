# Ghostty patches

`scripts/ghosttykit.sh` applies these to the upstream Ghostty commit pinned in
`scripts/ghostty.env`, in name order, before building GhosttyKit. They give Calm smooth
scrolling, which upstream Ghostty doesn't have yet (see DESIGNS.md → Motion in the terminal).

0005 and 0006 are taken unchanged from [thdxg/ghostty](https://github.com/thdxg/ghostty), a Ghostty fork,
where they live in `.github/downstream/`. Like Ghostty, that fork is MIT
licensed (Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors); the patches are the
fork's author's work. See `NOTICE`.

| Patch | What it does |
|---|---|
| `0005-smooth-scroll.patch` | The `smooth-scroll` config key. Trackpad scrolling moves scrollback by pixels; a program on the alternate screen that scrolls a region of its screen by rows (Claude Code's full-screen renderer, `less`, editors) has the region's content slide into place instead of jumping; a resize moves the content by pixels too. Clicks, selection, mouse reports and the IME position use the rows as drawn. |
| `0006-custom-shader-cursor-hidden-offscreen.patch` | A custom shader's `iCursorVisible` is 0 while the cursor is scrolled out of view or in the off phase of a blink, so Calm's cursor glide never smears from a stale position. |

Source: `thdxg/ghostty@6dffca46e3b7728fde24c61ada60c5a06c250e2d`, whose parent is upstream
`4406075a09c8ca0d83f30e8aaa710b9315ec428a`, the commit in `scripts/ghostty.env`.

```
bcd807059b18de3027528513e9952beba586be1bf0a72f8da20abafa1ac41e56  0005-smooth-scroll.patch
62a234b11f2b4482ec503c058adf19f690c3403750e4802b808d5bb82ea80ad7  0006-custom-shader-cursor-hidden-offscreen.patch
```

## Calm's own patches

Numbered from 0007, after the fork's, and applied on top of them. Each is as small as it can be,
says why in its header, and is worth offering to the fork or upstream; drop it once they cover it.

| Patch | What it does |
|---|---|
| `0007-read-text-drawn-row.patch` | `ghostty_surface_read_text` reports a row's position where smooth scrolling draws it (`tl_px_y` plus the viewport's pixel shift), as 0005 does for the IME position. Calm's link marks and cell hit-testing (Copy Cell, the link tag) place things on rows from it. |
| `0008-region-scroll-pinned-rows.patch` | A region scroll animation leaves an edge row that the program repainted in place where it is, and moves only the rows between. Claude Code redraws its "Jump to bottom" hint on its transcript's last row after every scroll while you scroll back; 0005 animated that row with the rest, so the old copy slid away as a ghost while the new one slid in, and each scroll showed the hint two or three times. A row counts as repainted in place when a run of at least 8 cells with a background color and some text is unchanged in the same cells, and mostly isn't what the scroll moved in (`repaintedInPlace`). Plain text never counts, since consecutive lines often share long runs. Zig tests: `zig build test -Dtest-filter=EdgeRows -Dtest-filter=repaintedInPlace -Dtest-filter=PinnedEdges`. |
| `0009-extend-padding-only-runs.patch` | With `window-padding-color = extend`, the padding beside a row takes its edge cell's color only when the row's first (or last) three cells share a background. A program's own cursor drawn as a reverse-video cell (pi's, at column 0 of an empty prompt) used to grow out into the padding as a block twice a cell's size; it is at most two cells wide, so it stays a cell, while a background painted out to the edge still extends. The neighbors are looked up like the edge cell, through 0005's shift and region animations (`cell_bg_at`). Metal is checked with `xcrun -sdk macosx metal -c`; the GLSL twin isn't built on macOS. Self-test: `scripts/fixtures/edge-cursor.sh`. |
| `0010-infer-redraw-scroll.patch` | A program that moves its content by repainting rows rather than scrolling them (pi's full-screen view rewrites every changed row in place, for each streamed line and wheel step) gives 0005 no scroll to animate. On the alternate screen, when the terminal recorded no scroll, the renderer compares each row's hash with the previous frame's; when at least half of the rows that changed, and at least three, are the old ones moved by the same number of rows, that span (between rows drawn the same in both frames, such as a header or a prompt) is animated as a region scroll of it. Zig tests: `-Dtest-filter=inferScroll`. |

After moving to a newer Ghostty, re-check that these still apply; one that doesn't is updated
here, by hand, against the new 0005.

## Moving to a newer Ghostty

The fork keeps its patches rebased onto upstream `main`, one commit on top of a pristine
upstream commit. So instead of rebasing them here:

1. Pick a fork commit on `main` (`gh api 'repos/thdxg/ghostty/commits?per_page=5'`). Its first
   parent is the upstream commit to pin.
2. Download both patches at that commit:
   `gh api "repos/thdxg/ghostty/contents/.github/downstream/<file>?ref=<fork sha>" -H "Accept: application/vnd.github.raw"`.
3. Update `GHOSTTY_REF`, `GHOSTTY_COMMIT` and `GHOSTTY_PATCHES_FROM` together, and the
   checksums above. Check `minimum_zig_version` in that commit's `build.zig.zon` against `mise.toml`.
4. Read the patches' diff against the previous ones, then run `mise run setup`, the tests and the
   `smooth-scroll` self-test (DESIGNS.md → Motion in the terminal).

A patch that doesn't apply stops `ghosttykit.sh` with an error; it never builds a half-patched
engine. If the fork ever stops following upstream, pin the last commit it supports, or delete
the patch: without it `smooth-scroll` isn't a key the engine knows, and Calm leaves it out and
scrolls by whole rows as before.
