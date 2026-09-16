# Changelog

## 0.1.0

First release.

- `sensible.toml`: tmux keymap for Herdr, prefix `ctrl+h`, plus agent rows.
- `bin/agent-labels.sh`: reports `[CC]`/`[CX]` and the working directory per
  pane, because Herdr has no cwd token and style rules cannot rewrite text.
- `bin/scrollback-search.sh`: fzf over a pane's scrollback, standing in for
  tmux's `prefix + /` reverse search.
- `bin/last-target.sh`: tmux's last-window and last-session, as last tab and
  last workspace, plus last agent which tmux had no concept of.
- `prefix+C-l` clears the screen via `send-keys`; no action drops scrollback.
- No-prefix pane switching on `ctrl+alt+j/k` and `alt+j/k`, matching M-j/M-k.
- `herdr-plugin.toml`: makes labelling event-driven and feeds focus history.
- `install.sh`: merges between markers, refuses to clobber an existing
  `[keys]` or `[ui]`, validates, rolls back on a rejected config.
