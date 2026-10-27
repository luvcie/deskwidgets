# deskwidgets

desktop widgets for quickshell. noctalia users get drag, placement and settings
for free. bare quickshell users get a file they can point `qs` at.

## widgets

- codex usage: two bars for codex rate limits, the 5h window and the weekly
  one, with a live reset countdown

## install (noctalia)

settings > plugins > sources > add source:

    https://github.com/luvcie/deskwidgets

then install codex usage from the available tab, add it on the desktop widgets
tab, and set the command in the widget settings (the gear on the widget chip).

## install (bare quickshell)

    git clone https://github.com/luvcie/deskwidgets
    qs -p deskwidgets/codex-usage

set `usageCommand` at the top of `codex-usage/shell.qml` to the path of your
`usage` executable. drag the card to where you want it.

## usage backend

the widget runs a command with `--json` and reads one report per provider:

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


