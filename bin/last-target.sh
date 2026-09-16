#!/bin/sh
# shellcheck shell=sh
# Version: 0.1.0

set -eu

prog=${0##*/}
VERSION=0.1.0

EXIT_OK=0
EXIT_ERROR=1
EXIT_USAGE=2

QUIET=0
STATE_DIR=${HERDR_PLUGIN_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/tmux2herdr}

log() { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }
err() { printf '%s\n' "$*" >&2; }
die() { err "$prog: error: $*"; exit "$EXIT_ERROR"; }
usage() {
  cat <<USAGE
$prog - tmux's last-window and last-session, for Herdr

tmux had "prefix + C-a" for the last window and "prefix + C-s" for the last
session. Herdr has last_pane and nothing else, so this keeps the previous
focused workspace and agent in a state file and jumps back to them.

"record" is driven by the plugin's workspace.focused and pane.focused hooks.
Without the plugin linked, nothing records and "back" has nothing to do.

USAGE:
  $prog record workspace|agent
  $prog back   workspace|agent
  $prog show

OPTIONS:
  -q, --quiet     Suppress non-error output
  -h, --help      Show this help
  -V, --version   Show version

ENV:
  HERDR_PLUGIN_STATE_DIR  State location (default: $STATE_DIR)
  HERDR_BIN_PATH          Herdr binary (default: herdr on PATH)

EXAMPLES:
  $prog back workspace
  $prog show
USAGE
}
version() { printf '%s %s\n' "$prog" "$VERSION"; }
require() { command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"; }

herdr_bin() {
  h=${HERDR_BIN_PATH:-herdr}
  command -v "$h" >/dev/null 2>&1 || die "missing dependency: herdr"
  printf '%s' "$h"
}

# Focused workspace id, or the focused agent's pane id.
current_of() {
  case $1 in
    workspace) "$HERDR" workspace list 2>/dev/null \
        | jq -r '.result.workspaces[]? | select(.focused) | .workspace_id' ;;
    agent) "$HERDR" agent list 2>/dev/null \
        | jq -r '.result.agents[]? | select(.focused) | .pane_id' ;;
    *) die "unknown kind: $1" ;;
  esac
}

# Two files per kind: what is focused now, and what was focused before it.
# Writing only on a real change is what makes "back" a toggle.
do_record() {
  kind=$1
  cur=$(current_of "$kind") || true
  [ -n "$cur" ] || return 0
  mkdir -p "$STATE_DIR"
  prev_file=$STATE_DIR/$kind.previous
  cur_file=$STATE_DIR/$kind.current
  old=""
  [ ! -f "$cur_file" ] || old=$(cat "$cur_file")
  [ "$old" != "$cur" ] || return 0
  [ -z "$old" ] || printf '%s\n' "$old" > "$prev_file"
  printf '%s\n' "$cur" > "$cur_file"
  log "$kind: $old -> $cur"
}

do_back() {
  kind=$1
  prev_file=$STATE_DIR/$kind.previous
  [ -f "$prev_file" ] || { log "no previous $kind yet"; return 0; }
  target=$(cat "$prev_file")
  [ -n "$target" ] || { log "no previous $kind yet"; return 0; }
  case $kind in
    workspace) "$HERDR" workspace focus "$target" >/dev/null \
        || die "cannot focus workspace $target" ;;
    agent) "$HERDR" agent focus "$target" >/dev/null \
        || die "cannot focus agent $target" ;;
  esac
  log "focused $kind $target"
}

do_show() {
  for kind in workspace agent; do
    cur=""; prev=""
    [ ! -f "$STATE_DIR/$kind.current" ] || cur=$(cat "$STATE_DIR/$kind.current")
    [ ! -f "$STATE_DIR/$kind.previous" ] || prev=$(cat "$STATE_DIR/$kind.previous")
    printf '%-9s current=%-10s previous=%s\n' "$kind" "${cur:--}" "${prev:--}"
  done
}

while [ $# -gt 0 ]; do
  case $1 in
    -h|--help) usage; exit "$EXIT_OK" ;;
    -V|--version) version; exit "$EXIT_OK" ;;
    -q|--quiet) QUIET=1 ;;
    --) shift; break ;;
    -*) die "unknown option: $1" ;;
    *) break ;;
  esac
  shift
done

main() {
  [ $# -gt 0 ] || { usage; exit "$EXIT_USAGE"; }
  require jq
  HERDR=$(herdr_bin)
  cmd=$1
  shift
  case $cmd in
    record|back)
      [ $# -gt 0 ] || die "$cmd needs: workspace or agent"
      case $1 in
        workspace|agent) : ;;
        *) die "unknown kind: $1" ;;
      esac
      if [ "$cmd" = record ]; then do_record "$1"; else do_back "$1"; fi
      ;;
    show) do_show ;;
    *) die "unknown command: $cmd" ;;
  esac
}

main "$@"
