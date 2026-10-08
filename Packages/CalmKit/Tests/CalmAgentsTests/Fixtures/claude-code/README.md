# Claude Code hook payloads

Built from the fields in Claude Code's hooks documentation (code.claude.com/docs/en/hooks), checked 2026-09-27 against version 2.1.283. They are not captured from a live session yet: replace them with captured payloads during dogfooding (M1.12).

`transcript*.jsonl`, `task-*.json` and `session-*.json` are synthetic records in the shapes seen in real Claude Code 2.1.283 files on 2026-09-27 (record types, keys and value types were read; no conversation content was copied). The tests lay them out as `~/.claude/{projects,tasks,sessions}` in a temporary home.

`session-status-*.json` add the fields Claude Code 2.1.284 writes for a live process (`status`, `statusUpdatedAt` in milliseconds, `updatedAt`, `waitingFor` when it waits), read from real `~/.claude/sessions/<pid>.json` files on 2026-09-29: `busy` and `idle` were seen on disk; `waiting` is in the 2.1.283 binary but was not seen on disk, so that fixture is built from the binary's wording. No values were copied from the files except the timestamps.

`session-2.1.291.json` has the keys Claude Code 2.1.291 writes to `~/.claude/sessions/<pid>.json`, read from a real file on 2026-10-06 (its `peerFeatures` cut to one); the values are made up apart from the shape of the timestamps.

`transcript-recap.jsonl` ends with the `away_summary` record Claude Code 2.1.284 writes for its "※ recap:" line, with the keys, the records before it and the "(disable recaps in /config)" hint as seen in real files on 2026-09-30 (246 recaps in the author's history); its text is made up.

`PreCompact-*.json` and `PostCompact-*.json` are payloads captured from Claude Code 2.1.291 on 2026-10-06 (a scratch home whose hooks logged their payloads, a local stand-in for the Messages API, so no model call), with the session id, paths and summary swapped for made-up ones. `transcript-compacting.jsonl`, `transcript-compacted.jsonl` and `transcript-compact-cancelled.jsonl` are the conversation records the same runs wrote (a `/compact`, then a reply reporting ~985k tokens of context, then a compaction Claude began on its own; and a `/compact` cancelled with Esc), with paths, ids and the logging hook swapped for the fixtures' own; their text is the stand-in's.

`transcript-asleep.jsonl` follows a real conversation from 2026-10-08 (Claude Code 2.1.291): a reply cut off when the Mac slept, the stand-in Claude Code wrote for it (`model` "<synthetic>", `isApiErrorMessage`, every usage count 0; keys and error text as in the real record), Claude's recap, then the person's next prompt, which started a compaction. The record types, keys, order and timestamps are the real ones; the other text and the usage counts are made up.

`PreToolUse-*.json` and `PostToolUse-*.json` follow the hooks documentation's fields (`tool_name`, `tool_input`, `tool_use_id`, and `tool_response` after the call). Their `tool_input`s have the keys Claude Code 2.1.291 writes for those tools in real transcripts (a `tool_use` block's `input` is what the hook gets), read 2026-10-09; the values are made up. They were not captured from a live hook.
