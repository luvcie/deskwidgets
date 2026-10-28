# deskwidgets

desktop widgets for noctalia 5.

## widgets

- agent-usage: codex, claude and antigravity rate limit bars. see
  [agent-usage/README.md](agent-usage/README.md).

## agent-usage: how it gets data

it reads the login files the provider clis already keep on disk and calls each
provider's usage endpoint. it only reads these files, never writes them and
never refreshes a token. codex falls back to the newest session log under
`~/.codex/sessions`, which needs `find` on `PATH`.

the exact files, urls and process are listed in
[agent-usage/README.md](agent-usage/README.md), with the settings.

## install

add the git source in settings > plugins > add source:

    https://github.com/luvcie/deskwidgets

or from the command line:

    noctalia msg plugins source add deskwidgets git https://github.com/luvcie/deskwidgets

then enable a widget in settings > plugins, or:

    noctalia msg plugins enable luvcie/agent-usage

to place it, open the desktop widgets editor (settings > desktop > toggle
editor, or `noctalia msg desktop-widgets-edit`). switch to an empty workspace so
the editor is visible. pick agent usage from the type picker and drag it where
you want it.
