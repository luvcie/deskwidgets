# Agent Usage Desktop Widget

rate limit bars for codex, claude and antigravity on the desktop. each provider
reads the login file its cli already keeps on disk.

## Plugin

| Field | Value |
| --- | --- |
| ID | `luvcie/agent-usage` |
| Entries | Desktop widget: `desktop` |

## Requirements

- `find` on `PATH`. only the codex fallback uses it, to locate the newest
  session log when the live codex call is not usable.
- each provider needs its own cli logged in once: `codex` for codex, `claude`
  for claude, `agy` for antigravity. a provider that is not logged in shows a
  hint in its section instead of bars.

## Usage

install the plugin, then add the agent usage desktop widget from the desktop
widget editor. open the widget inspector to choose the provider. drag the card
where you want it.

## Settings

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `provider` | `select` | `all` | `all`, `codex`, `claude` or `agy` (antigravity). `all` stacks every provider. |
| `interval_seconds` | `int` | `120` | seconds between fetches, from 30 to 3600. |

## Notes

- reads these local files. nothing is written.
  - `~/.codex/auth.json`: codex access token and account id.
  - `~/.codex/sessions/*.jsonl`: codex fallback only. the newest file by mtime
    is read and only its `rate_limits` fields are used.
  - `$CLAUDE_CONFIG_DIR/.credentials.json` or `~/.claude/.credentials.json`:
    claude oauth access token.
  - `~/.gemini/antigravity-cli/antigravity-oauth-token`, then
    `~/.gemini/oauth_creds.json`: antigravity access token.
- network calls, each sent with the provider's bearer token:
  - `GET https://chatgpt.com/backend-api/wham/usage` (codex)
  - `GET https://api.anthropic.com/api/oauth/usage` (claude)
  - `POST https://daily-cloudcode-pa.sandbox.googleapis.com/v1internal:retrieveUserQuota`
    with an empty json body (antigravity)
- processes spawned: only `find`, only on the codex fallback, run directly
  without a shell. argv is `find <HOME>/.codex/sessions -name *.jsonl -printf`
  with the format `%T@ %p` followed by a newline, with a 10 second timeout.
- tokens are never refreshed, never written and never logged. if the widget says
  the login expired, run the matching cli once to refresh its token.
