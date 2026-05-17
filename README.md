# claude-statusline

A single-line, colored statusline for [Claude Code](https://claude.com/claude-code).

```
repo [Claude Opus 4.7] (ctx:42% tokens:78.3k) [5h:31% ↻ 18:00] [week:12% ↻ 05/20 09:00] {month:4.2Mtok $63.41}
```

Segments shown (each is omitted if data is unavailable):

- `dir` — current workspace basename
- `[model]` — active model display name
- `(ctx:% tokens:N)` — context window usage from the current session
- `[5h:% ↻ HH:MM]` — 5-hour rate limit + reset time
- `[week:% ↻ MM/DD HH:MM]` — weekly rate limit + reset time
- `{month:Ntok $cost}` — month-to-date Anthropic API usage (requires `ANTHROPIC_API_KEY`)

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/fennysmith/claude-statusline/main/install.sh | sh
```

The installer downloads `statusline.sh` to `~/.claude/statusline.sh` and merges a `statusLine` entry into `~/.claude/settings.json`. Restart Claude Code to see it.

### Requirements

- `jq` (required)
- `curl` (required for monthly usage segment)
- GNU `date` (Linux) or BSD `date` (macOS) — both supported

### Optional environment variables

| Variable | Effect |
| --- | --- |
| `ANTHROPIC_API_KEY` | Enables the `{month:...}` segment via `/v1/usage` (cached 5 min) |
| `CLAUDE_STATUSLINE_NO_MONTHLY=1` | Hide monthly segment even if API key is set |
| `CLAUDE_STATUSLINE_NO_RATE=1` | Hide 5h and weekly segments |
| `CLAUDE_STATUSLINE_DEBUG=path` | Dump the raw JSON payload to `path` each render |

## Manual install

1. Copy `statusline.sh` to `~/.claude/statusline.sh` and `chmod +x` it.
2. Add to `~/.claude/settings.json`:

   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "bash ~/.claude/statusline.sh"
     }
   }
   ```

## Uninstall

Remove the `statusLine` block from `~/.claude/settings.json` and delete `~/.claude/statusline.sh`.

## License

MIT
