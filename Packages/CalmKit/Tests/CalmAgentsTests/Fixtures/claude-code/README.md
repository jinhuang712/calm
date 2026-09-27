# Claude Code hook payloads

Built from the fields in Claude Code's hooks documentation (code.claude.com/docs/en/hooks), checked 2026-09-27 against version 2.1.283. They are not captured from a live session yet: replace them with captured payloads during dogfooding (M1.12).

`transcript*.jsonl`, `task-*.json` and `session-*.json` are synthetic records in the shapes seen in real Claude Code 2.1.283 files on 2026-09-27 (record types, keys and value types were read; no conversation content was copied). The tests lay them out as `~/.claude/{projects,tasks,sessions}` in a temporary home.
