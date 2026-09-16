---
name: tmux2herdr
description: Map tmux habits onto Herdr, and label Herdr agent rows with an agent tag and directory. Use when configuring Herdr keybindings, when a sidebar row shows the wrong name, when OSC 4 colour codes leak into a shell under tmux, or when scripting Herdr panes and agents.
---

# tmux2herdr

Herdr config lives at `~/.config/herdr/config.toml`. There is no include
directive: everything is one file. `herdr config check` validates it and
`herdr server reload-config` applies it to a running server, which does
reach the sidebar because the server broadcasts a reload to every client.

## Facts that cost time to learn

- Sidebar tokens are a fixed set. There is **no cwd token**. Style `rules`
  recolour a token; they never rewrite its text. So `Claude` cannot become
  `[CC]` and a path cannot appear, from config alone.
- Both come from `herdr pane report-metadata <id> --source <id>
  --display-agent "[CC]" --token dir=<name>`. That command prints an
  **empty body** on success, not JSON. Do not try to parse it.
- `agent_label` resolves `display_agent` > `name` (`herdr agent rename`) >
  `agent` > `title`. Reported metadata wins.
- Reported tokens **do not survive a server restart**. Re-run the labeller
  from a plugin event hook or a tab-bar timer.
- Do not lead a sidebar row with `workspace`: at sidebar width the line
  truncates to it and every agent in a space looks identical.
- `prefix+shift+r` reloads client-side config directly.

## Choosing a prefix

`ctrl+b` collides with Claude Code (background tasks) and zsh backward-char.
`ctrl+s` collides with tmux and with terminal flow control. `ctrl+space`
collides with macOS input-source switching. `ctrl+h` is usually free; it
shadows only vim's insert-mode `^H` alias, and Backspace sends DEL anyway.

## OSC 4 leak under tmux

Symptom: `;rgb:0000/afaf/d7d7` typed into the shell when focus returns.
Cause: focus-in makes Herdr query the theme, and it then fires 256 OSC 4
palette queries; tmux forwards each to the outer terminal and the trickled
replies get flushed as keystrokes. Upstream: herdr#4025.

`focus-events off` does **not** fix it. tmux writes focus-in on pane
switches regardless. Set a 256-entry `pane-colours` palette in tmux so it
answers locally and at once.

## Scripting

```sh
herdr pane list                       # panes, cwd, agent, tokens
herdr agent list                      # agents with semantic state
herdr agent prompt <target> "<text>" --wait --until blocked --until idle
herdr agent read <target> --lines 80  # what it said, without attaching
herdr pane read <id> --source recent  # scrollback as JSON
```

Plugin hooks that exist: `pane.created`, `pane.closed`, `pane.focused`,
`pane.agent_detected`, `pane.agent_status_changed`, `workspace.focused`,
`tab.focused`, `worktree.created`. `pane.output_changed` is excluded from
plugin hooks on purpose; it fires constantly.

Plugin commands are argv, run with no shell. Use `["sh", "-c", "..."]` when
you need `$HERDR_PLUGIN_ROOT` or `$HERDR_PLUGIN_STATE_DIR` expanded.

## Copy mode

One configurable key, `copy_mode` (default `prefix+[`). The keys *inside*
copy mode are fixed: `ctrl+u`/`ctrl+d` half page, `ctrl+b`/`ctrl+f` full,
`PageUp`/`PageDown`, `/` and `?` search, `n`/`N` repeat, `v` select, `y`
copy. There is no way to enter copy mode already scrolled or already
searching, so tmux's `prefix+PageUp` and `prefix+/` cannot be reproduced
exactly. A `ctrl+b` prefix costs you `ctrl+b` page-up inside copy mode;
another prefix does not.

Scrolling a pane from outside is not available to a keybinding.
`terminal.scroll` exists only as a stdin command of
`herdr terminal session control`, which seizes exclusive control authority.

## Gaps with no workaround

No named layouts, no `synchronize-panes`, no scrollback clear (sending
`ctrl+l` clears the screen only), no `display-panes` overlay, no
pane-border titles, no rectangle selection, no repeatable keys. Do not
promise these; they are absent from the action table, not merely unbound.

## Writing scripts here

POSIX `sh`, one file, no libraries. `set -eu`, `umask 077`, version header,
`-n/-q/-h/-V`, `--help` is the documentation. Check dependencies at runtime
and fail with guidance. `shellcheck -s sh` and `dash -n` must be clean;
`t/check.sh` runs both. Note that `x=$(cmd)` aborts at the assignment under
`set -e`, so an error branch below it is dead code.
