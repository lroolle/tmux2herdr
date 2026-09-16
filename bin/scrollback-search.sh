#!/bin/sh
# shellcheck shell=sh
# Version: 0.1.0

set -eu

prog=${0##*/}
VERSION=0.1.0

EXIT_OK=0
EXIT_ERROR=1

LINES_DEFAULT=${SCROLLBACK_SEARCH_LINES:-5000}

err() { printf '%s\n' "$*" >&2; }
die() { err "$prog: error: $*"; exit "$EXIT_ERROR"; }
usage() {
  cat <<USAGE
$prog - fzf over a pane's scrollback, tmux reverse-search style

tmux bound "prefix + /" to copy-mode already searching backwards. Herdr's
copy mode searches with / and ? but cannot be started pre-armed, so this
reads the pane's scrollback and filters it with fzf instead. The newest
line is first. Enter copies the selection to the clipboard and prints it.

Meant to run from a Herdr popup keybinding, which sets HERDR_ACTIVE_PANE_ID:

  [[keys.command]]
  key = "prefix+slash"
  type = "popup"
  command = "~/.config/herdr/bin/$prog"

USAGE:
  $prog [OPTIONS] [pane_id]

OPTIONS:
  -l, --lines N   Scrollback lines to read (default: $LINES_DEFAULT)
  -h, --help      Show this help
  -V, --version   Show version

ENV:
  HERDR_ACTIVE_PANE_ID     Pane to search when no argument is given
  HERDR_BIN_PATH           Herdr binary (default: herdr on PATH)
  SCROLLBACK_SEARCH_LINES  Default line count
USAGE
}
version() { printf '%s %s\n' "$prog" "$VERSION"; }
require() { command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"; }

# First clipboard tool that exists; printing is the fallback so the line is
# never lost on a box without one.
clip() {
  if command -v pbcopy >/dev/null 2>&1; then pbcopy
  elif command -v wl-copy >/dev/null 2>&1; then wl-copy
  elif command -v xclip >/dev/null 2>&1; then xclip -selection clipboard
  else cat >/dev/null
  fi
}

lines=$LINES_DEFAULT
pane=${HERDR_ACTIVE_PANE_ID:-}

while [ $# -gt 0 ]; do
  case $1 in
    -h|--help) usage; exit "$EXIT_OK" ;;
    -V|--version) version; exit "$EXIT_OK" ;;
    -l|--lines) shift; [ $# -gt 0 ] || die "--lines needs a value"; lines=$1 ;;
    --) shift; break ;;
    -*) die "unknown option: $1" ;;
    *) pane=$1 ;;
  esac
  shift
done
[ $# -eq 0 ] || pane=$1

main() {
  require fzf
  herdr=${HERDR_BIN_PATH:-herdr}
  command -v "$herdr" >/dev/null 2>&1 || die "missing dependency: herdr"
  [ -n "$pane" ] || die "no pane: run from a Herdr popup or pass a pane id"

  # `pane read` prints the scrollback as plain text, not JSON. --raw would
  # keep the ANSI escapes, which fzf would show literally.
  text=$("$herdr" pane read "$pane" --source recent --lines "$lines") \
    || die "cannot read pane $pane"
  [ -n "$text" ] || die "pane $pane has no scrollback"

  # --tac puts the newest line under the cursor, which is what a reverse
  # search means. Exit 130 is a plain cancel, not a failure.
  pick=$(printf '%s\n' "$text" | grep -v '^[[:space:]]*$' | fzf --tac \
    --prompt='reverse-search> ' --no-sort --exact --info=inline \
    --height=100% --border=none) || {
      status=$?
      [ "$status" -eq 130 ] && exit "$EXIT_OK"
      exit "$status"
    }

  printf '%s' "$pick" | clip
  printf '%s\n' "$pick"
}

main
