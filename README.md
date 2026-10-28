# deskwidgets

desktop widgets for noctalia and quickshell.

- agent-usage: for noctalia 5 (luau). no backend needed.
- codex-usage: for noctalia 4 and bare quickshell. needs the usage backend.

noctalia users get drag, placement and settings for free. bare quickshell users
get a file they can point `qs` at.

## widgets

- agent usage: rate limit bars for codex, claude and antigravity. codex and
  claude show their 5h and weekly windows, antigravity shows one bar per model
  family (gemini, claude/gpt). each bar has a live reset countdown. pick one
  provider or all of them in the widget settings.
- codex usage (v4): two bars for codex rate limits, the 5h window and the
  weekly one, with a live reset countdown

## install (noctalia 5)

add the git source in settings > plugins > add source:

    https://github.com/luvcie/deskwidgets

or from the command line:

    noctalia msg plugins source add deskwidgets git https://github.com/luvcie/deskwidgets

then enable agent usage in settings > plugins, or:

    noctalia msg plugins enable luvcie/agent-usage

to place it, open the desktop widgets editor (settings > desktop > toggle
editor, or `noctalia msg desktop-widgets-edit`). switch to an empty workspace so
the editor is visible. pick agent usage from the type picker and drag it where
you want it. then open the widget's inspector and choose `provider` (all, codex,
claude or antigravity) and `interval_seconds` (refresh, 30 to 3600 seconds).

## how agent usage gets data

agent usage reads the login files the provider clis already keep on disk and
calls each provider's usage endpoint. there is no backend to run.

- codex: `~/.codex/auth.json` for the access token and account id. calls the
  chatgpt wham usage endpoint. if that file is missing or the call fails, it
  reads the newest rollout under `~/.codex/sessions` instead.
- claude: `$CLAUDE_CONFIG_DIR/.credentials.json`, or
  `~/.claude/.credentials.json` when `CLAUDE_CONFIG_DIR` is unset. calls the
  anthropic oauth usage endpoint.
- antigravity: `~/.gemini/antigravity-cli/antigravity-oauth-token`, then
  `~/.gemini/oauth_creds.json`. calls the code assist quota endpoint.

it only reads these files. it never writes them and never refreshes a token.
if the widget says the login expired, run the matching cli once (`codex`,
`claude` or `agy`) so it refreshes its own token.

## install (noctalia 4)

for the old quickshell-based noctalia 4 shell.

settings > plugins > sources > add source:

    https://github.com/luvcie/deskwidgets

then install codex usage from the available tab, add it on the desktop widgets
tab, and set the command in the widget settings (the gear on the widget chip).
codex usage needs the usage backend below.

## install (bare quickshell)

    git clone https://github.com/luvcie/deskwidgets
    qs -p deskwidgets/codex-usage

codex usage needs the usage backend below. set `usageCommand` at the top of
`codex-usage/shell.qml` to the path of your `usage` executable. drag the card to
where you want it.

## usage backend (codex-usage)

codex-usage runs a command with `--json` and reads one report per provider:

    [
      {
        "provider": "codex",
        "status": "ok",
        "windows": [
          {
            "label": "primary",
            "used_percent": 100.0,
            "window_minutes": 300,
            "resets_at": "1793052675"
          }
        ]
      }
    ]

`used_percent` is usage consumed. `resets_at` is epoch seconds as a string, or
rfc 3339. only the codex report is read.

any command that prints this shape works.
