#!/bin/sh
# shellcheck shell=sh
# Version: 0.1.0

set -eu
umask 077

prog=${0##*/}
VERSION=0.1.0

EXIT_OK=0
EXIT_ERROR=1
EXIT_USAGE=2

DRY_RUN=0
QUIET=0
CLEAR=0
SOURCE_ID=user:agent-labels

# Parent segments that carry no meaning in a row: show the basename alone.
SKIP_DIRS=${AGENT_LABELS_SKIP_DIRS:-WIP wip tmp}

log() { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }
err() { printf '%s\n' "$*" >&2; }
die() { err "$prog: error: $*"; exit "$EXIT_ERROR"; }
usage() {
  cat <<USAGE
$prog - tag Herdr agent rows with a short agent code and their directory

Herdr's sidebar has no cwd token and its style rules recolour a token
without rewriting the text, so both values are reported per pane:

  display_agent -> the "agent" token -> [CC]
  token "dir"   -> the "\$dir" token  -> deva-chore

Reported metadata does not survive a server restart and new panes start
bare, so run this on a timer. It writes only panes that changed and prints
nothing unless asked, which keeps a tab-bar status entry invisible.

USAGE:
  $prog [OPTIONS]

OPTIONS:
  -c, --clear     Remove the labels this tool reported
  -n, --dry-run   Print actions without executing
  -q, --quiet     Suppress non-error output
  -h, --help      Show this help
  -V, --version   Show version

ENV:
  HERDR_SOCKET_PATH       Herdr API socket (default: the local server)
  AGENT_LABELS_SKIP_DIRS  Parent names to drop, space separated
                          (default: "WIP wip tmp")

EXAMPLES:
  $prog
  $prog --dry-run
  HERDR_SOCKET_PATH=/tmp/herdr-mac.sock $prog
USAGE
}
version() { printf '%s %s\n' "$prog" "$VERSION"; }
require() { command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"; }

# Two-letter code per agent. Herdr's canonical ids first, then the extra
# runtimes deva launches, which arrive as custom reported agents.
tag_for() {
  case $1 in
    claude) printf 'CC' ;;
    codex) printf 'CX' ;;
    gemini) printf 'GM' ;;
    cursor) printf 'CU' ;;
    cline) printf 'CN' ;;
    devin) printf 'DV' ;;
    antigravity|agy) printf 'AG' ;;
    pi) printf 'PI' ;;
    kimi) printf 'KM' ;;
    grok) printf 'GK' ;;
    opencode) printf 'OC' ;;
    dsh) printf 'DS' ;;
    *) printf '%s' "$1" | tr '[:lower:]' '[:upper:]' | cut -c1-2 ;;
  esac
}

# Last two path segments, minus a meaningless parent: claude-code/cctrace
# but plain deva-chore under WIP. Herdr truncates an over-wide token itself,
# so no ellipsis here.
short_dir() {
  p=${1%/}
  [ -n "$p" ] || return 0
  [ "$p" != "${HOME:-}" ] || { printf '~'; return 0; }
  base=${p##*/}
  parent=${p%/*}
  parent=${parent##*/}
  [ -n "$parent" ] || { printf '/%s' "$base"; return 0; }
  for skip in $SKIP_DIRS; do
    [ "$parent" != "$skip" ] || { printf '%s' "$base"; return 0; }
  done
  printf '%s/%s' "$parent" "$base"
}

report() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf 'DRY-RUN: herdr pane report-metadata %s\n' "$*"
    return 0
  fi
  herdr pane report-metadata "$@" || die "report-metadata failed: $1"
}

while [ $# -gt 0 ]; do
  case $1 in
    -h|--help) usage; exit "$EXIT_OK" ;;
    -V|--version) version; exit "$EXIT_OK" ;;
    -c|--clear) CLEAR=1 ;;
    -n|--dry-run) DRY_RUN=1 ;;
    -q|--quiet) QUIET=1 ;;
    --) shift; break ;;
    -*) die "unknown option: $1" ;;
    *) usage; exit "$EXIT_USAGE" ;;
  esac
  shift
done

main() {
  require herdr
  require jq

  panes=$(herdr pane list) || die "herdr pane list failed (is the server running?)"
  case $panes in
    *'"error"'*) die "herdr pane list: $(printf '%s' "$panes" | jq -r '.error.message // .error')" ;;
  esac

  rows=$(printf '%s' "$panes" | jq -r '
    .result.panes[]
    | select(.agent != null)
    | [ .pane_id, .agent, (.foreground_cwd // .cwd // ""),
        (.display_agent // ""), (.tokens.dir // "") ]
    | @tsv') || die "cannot parse pane list"

  [ -n "$rows" ] || { log "no agent panes"; return 0; }

  tab=$(printf '\t')
  changed=0
  # Fed by here-doc, not a pipe: a pipeline would run the loop in a
  # subshell and lose the counter.
  while IFS="$tab" read -r id agent cwd cur_tag cur_dir; do
    if [ "$CLEAR" -eq 1 ]; then
      [ -n "$cur_tag" ] || [ -n "$cur_dir" ] || continue
      report "$id" --source "$SOURCE_ID" --clear-display-agent --clear-token dir
      log "cleared $id"
      changed=$((changed + 1))
      continue
    fi
    want_tag="[$(tag_for "$agent")]"
    want_dir=$(short_dir "$cwd")
    [ "$cur_tag" != "$want_tag" ] || [ "$cur_dir" != "$want_dir" ] || continue
    if [ -n "$want_dir" ]; then
      report "$id" --source "$SOURCE_ID" --display-agent "$want_tag" --token "dir=$want_dir"
    else
      report "$id" --source "$SOURCE_ID" --display-agent "$want_tag" --clear-token dir
    fi
    log "$id $want_tag $want_dir"
    changed=$((changed + 1))
  done <<ROWS
$rows
ROWS

  if [ "$CLEAR" -eq 1 ]; then log "$changed cleared"; else log "$changed updated"; fi
}

main "$@"
