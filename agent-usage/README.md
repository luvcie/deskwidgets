# agent usage

rate limit bars for codex, claude and antigravity on the desktop. each provider
reads the login its cli already keeps on disk, so no backend is needed.

## Plugin

| Field | Value |
| --- | --- |
| ID | `luvcie/agent-usage` |
| Entries | Desktop widget: `desktop` |

## Requirements

no external packages. each provider needs its own cli logged in once: `codex`
for codex, `claude` for claude, `agy` for antigravity. a provider that is not
logged in shows a hint in its section instead of bars.

## Usage

install the plugin, then add agent usage from the desktop widget editor. open
the widget inspector to choose the provider. drag the card where you want it.

## Settings

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `provider` | `select` | `all` | `all`, `codex`, `claude` or `agy` (antigravity). `all` stacks every provider. |
| `interval_seconds` | `int` | `120` | seconds between fetches, from 30 to 3600. |

## Notes

- reads these local files and never writes them: `~/.codex/auth.json` (falls
  back to the newest file under `~/.codex/sessions`),
  `$CLAUDE_CONFIG_DIR/.credentials.json` or `~/.claude/.credentials.json`,
  `~/.gemini/antigravity-cli/antigravity-oauth-token` and
  `~/.gemini/oauth_creds.json`.
- calls the codex wham usage endpoint, the anthropic oauth usage endpoint and
  the antigravity code assist quota endpoint.
- never refreshes a token. if the widget says the login expired, run the
  matching cli once so it refreshes its own token.
