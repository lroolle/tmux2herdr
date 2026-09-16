# tmux2herdr

Sensible tmux config, ported to a sensible Herdr config.

[![check](https://github.com/lroolle/tmux2herdr/actions/workflows/check.yml/badge.svg)](https://github.com/lroolle/tmux2herdr/actions/workflows/check.yml)
[![MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

[Herdr](https://herdr.dev) is a terminal multiplexer that knows what an agent
is. If you arrive from tmux, most of your muscle memory already works and a
few things are missing. This is the keymap, the gaps filled in, and the part
tmux never had: agent rows that tell you who is working and where.

    ● [CC] deva-chore
         Refactoring the token parser
    ◐ [CX] cctrace
         Reviewing interface details
    ✳ [CC] my-api
         Waiting on your approval

Two lines per agent: state, which agent, which directory, and what it says
it is doing. `[CC]` is Claude Code in its brand terracotta, `[CX]` is Codex.

## Install

Requires Herdr 0.9.0 or newer, `jq`, and `fzf` for scrollback search.

```sh
git clone https://github.com/lroolle/tmux2herdr
cd tmux2herdr
./install.sh --dry-run    # look first
./install.sh
herdr server reload-config
```

The installer copies `bin/` into your Herdr config directory, merges
`sensible.toml` between `# >>> tmux2herdr >>>` markers, links the plugin, and
runs `herdr config check`. If Herdr rejects the result it restores your
backup and tells you. If your config already defines `[keys]` or `[ui]` it
stops rather than corrupt the file, because TOML has no duplicate tables.
`--force` backs up and replaces those tables; `--no-plugin` skips the plugin.

The prefix is `ctrl+h`. Change it in one line if that collides with your
setup. `ctrl+b` is taken here by Claude Code's background-task key and by
zsh's backward-char, `ctrl+s` by tmux itself, `ctrl+space` by macOS input
switching. `ctrl+h` only shadows vim's insert-mode `^H` alias; your Backspace
key sends DEL and is unaffected.

## What already works

Herdr's defaults are tmux's defaults for most of the muscle memory: `c` new
tab, `v` split right, `h/j/k/l` focus, `z` zoom, `x` close, `[` copy mode,
`1`..`9` jump, `n`/`p` cycle, `shift+h/j/k/l` swap. Copy mode searches with
`/` and `?`, repeats with `n` and `N`, selects with `v`, yanks with `y`.

## What this adds

| tmux | tmux2herdr | how |
| --- | --- | --- |
| `b` split below | `prefix+b` | binding |
| `C-c` new-session | `prefix+C-c` | binding |
| `C-n` / `C-p` session cycle | `prefix+C-n` / `prefix+C-p` | binding |
| `C-f` fzf picker | `prefix+C-f` | Herdr's built-in goto picker |
| `C-k` / `C-j` resize | `prefix+C-k` / `prefix+C-j` | binding |
| `C-S-Left` / `Right` move window | `prefix+shift+left` / `right` | binding |
| `;` last pane | `prefix+;` | binding |
| `prefix+/` reverse search | `prefix+/` | fzf over scrollback |
| `C-a` last window | `prefix+C-a` last agent | plugin focus history |
| `C-s` last session | `prefix+C-s` last workspace | plugin focus history |

## What tmux still does better

Honest list. These have no Herdr action at all, so no config can reach them.

- Named layouts. `main-vertical`, `main-horizontal`, `tiled` and
  `main-pane-width` have no equivalent. You split and drag borders.
- `synchronize-panes`. There is no broadcast-to-all-panes input mode.
- `clear-history`. No action clears a pane's scrollback.
- `display-panes`. No numbered overlay to jump straight to a pane.
- `pane-border-format`. Borders are on, auto, or off, with no title.
- Repeatable keys. `repeat-time` has no equivalent; Herdr uses modes, so
  resizing is `prefix+r` then arrows rather than a held prefix.

## What Herdr does that tmux cannot

- Agent state. Every pane running a coding agent reports idle, working,
  blocked, done, or unknown, and the sidebar sorts blocked to the top.
- A real CLI. `herdr agent prompt`, `wait`, `read` and `send-keys` drive a
  session from a script. You can steer an agent from another machine.
- Git-aware spaces, with branch and ahead-behind counts in the sidebar, and
  worktrees as first-class workspaces.
- One agent list across SSH machines.
- Session restore. `resume_agents_on_restore` resurrects the conversation,
  not just the shell, for agents with a native session reference. This is
  tmux-resurrect and tmux-continuum, built in and aware of what it restores.
  Only detach keeps processes alive; a server restart restores shape and
  resumes agents.

## How the agent rows work

Herdr's sidebar tokens are a fixed set. There is no working-directory token,
and a style rule can recolour a token but never rewrite its text, so `Claude`
cannot become `[CC]` from config alone. Both values are *reported* per pane
instead, through Herdr's pane metadata API:

    display_agent -> the `agent` token -> [CC]
    token "dir"   -> the `$dir` token  -> deva-chore

`bin/agent-labels.sh` walks the panes and reports them, writing only what
changed. With the plugin linked it runs on `pane.created` and
`pane.agent_detected`. Without it, add a tab-bar timer instead:

```toml
[ui]
tab_bar_right = [
  { type = "command", command = "~/.config/herdr/bin/agent-labels.sh -q",
    interval_seconds = 10, timeout_seconds = 5 },
]
```

Reported metadata does not survive a server restart, which is why something
has to re-run it. Directories show their last two segments, minus a parent
that carries no meaning: `AGENT_LABELS_SKIP_DIRS` defaults to `WIP wip tmp`,
so `~/src/WIP/my-api` reads `my-api` but `~/src/acme/my-api` reads
`acme/my-api`.

## Running Herdr inside tmux

If Herdr runs in a tmux pane, expect `;rgb:0000/afaf/d7d7` to leak into your
shell on focus changes. On focus-in Herdr asks tmux for the terminal theme,
tmux answers, and Herdr then fires 256 OSC 4 palette queries. tmux has no
palette of its own, forwards each one to the outer terminal, and relays the
replies with gaps wide enough that Herdr flushes a partial escape sequence as
keystrokes. This is [herdr#4025](https://github.com/herdrdev/herdr/issues/4025).

`focus-events off` does not fix it: tmux writes focus-in on any pane switch
regardless of that option. Giving tmux a palette does, because then it
answers locally and at once:

```sh
# 256 entries; 0-15 should match your terminal
tmux set -g pane-colours[0] "#586e75"
```

`reference/tmux.conf` is the config this mapping was derived from.

## Files

    sensible.toml        the config block, merged between markers
    herdr-plugin.toml    event hooks, optional
    bin/agent-labels.sh  report [CC] and $dir per pane
    bin/scrollback-search.sh  fzf reverse search in a popup
    bin/last-target.sh   last agent, last workspace
    reference/tmux.conf  the source config
    skills/tmux2herdr/   for coding agents reading this repo

Every script is POSIX `sh`, single file, `shellcheck -s sh` and `dash -n`
clean, with `--help` as the documentation. `t/check.sh` runs the lot.

## License

MIT
