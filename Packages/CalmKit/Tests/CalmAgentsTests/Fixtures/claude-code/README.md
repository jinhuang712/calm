# Claude Code hook payloads

Built from the fields in Claude Code's hooks documentation (code.claude.com/docs/en/hooks), checked 2026-09-27 against version 2.1.283. They are not captured from a live session yet: replace them with captured payloads during dogfooding (M1.12).

`transcript*.jsonl`, `task-*.json` and `session-*.json` are synthetic records in the shapes seen in real Claude Code 2.1.283 files on 2026-09-27 (record types, keys and value types were read; no conversation content was copied). The tests lay them out as `~/.claude/{projects,tasks,sessions}` in a temporary home.

`session-status-*.json` add the fields Claude Code 2.1.284 writes for a live process (`status`, `statusUpdatedAt` in milliseconds, `updatedAt`, `waitingFor` when it waits), read from real `~/.claude/sessions/<pid>.json` files on 2026-09-29: `busy` and `idle` were seen on disk; `waiting` is in the 2.1.283 binary but was not seen on disk, so that fixture is built from the binary's wording. No values were copied from the files except the timestamps.
