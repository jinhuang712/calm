# Ghostty patches

`scripts/ghosttykit.sh` applies these to the upstream Ghostty commit pinned in
`scripts/ghostty.env`, in name order, before building GhosttyKit. They give Calm smooth
scrolling, which upstream Ghostty doesn't have yet (see DESIGNS.md → Motion in the terminal).

They are taken unchanged from [thdxg/ghostty](https://github.com/thdxg/ghostty), the Ghostty fork
Macterm builds on, where they live in `.github/downstream/`. Like Ghostty, that fork is MIT
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
