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
EXIT_CONFLICT=3

DRY_RUN=0
QUIET=0
FORCE=0
LINK_PLUGIN=1

CDPATH=''
SRC_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
CONFIG_DIR=${HERDR_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/herdr}
CONFIG=${HERDR_CONFIG_PATH:-$CONFIG_DIR/config.toml}
BEGIN_MARK='# >>> tmux2herdr >>>'
END_MARK='# <<< tmux2herdr <<<'

# Tables in sensible.toml. TOML rejects a duplicate table outright, so a
# blind append to a config that already has [keys] produces a broken file.
TABLES='[keys] [ui] [ui.sidebar.agents]'

log() { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }
err() { printf '%s\n' "$*" >&2; }
die() { err "$prog: error: $*"; exit "$EXIT_ERROR"; }
usage() {
  cat <<USAGE
$prog - install the tmux2herdr config block and plugin

Copies bin/ into your Herdr config dir, merges sensible.toml into
config.toml between markers, and links the plugin. Never overwrites a
config it did not write: an existing [keys] or [ui] table stops the install
unless you pass --force, which backs the file up first.

USAGE:
  $prog [OPTIONS]

OPTIONS:
  -n, --dry-run    Print what would happen, change nothing
  -f, --force      Back up and replace a conflicting config
      --no-plugin  Skip linking the Herdr plugin
  -q, --quiet      Suppress non-error output
  -h, --help       Show this help
  -V, --version    Show version

ENV:
  HERDR_CONFIG_PATH  Config file (default: $CONFIG)
  HERDR_BIN_PATH     Herdr binary (default: herdr on PATH)

EXAMPLES:
  $prog --dry-run
  $prog
  $prog --force --no-plugin
USAGE
}
version() { printf '%s %s\n' "$prog" "$VERSION"; }
require() { command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"; }

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf 'DRY-RUN: %s\n' "$*"
  else
    "$@"
  fi
}

has_our_block() { [ -f "$CONFIG" ] && grep -qF "$BEGIN_MARK" "$CONFIG"; }

conflicting_tables() {
  [ -f "$CONFIG" ] || return 0
  # Ignore what we wrote ourselves; only user-authored tables conflict.
  stripped=$(awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
    index($0, b) { skip = 1 } !skip { print } index($0, e) { skip = 0 }' "$CONFIG")
  for table in $TABLES; do
    printf '%s\n' "$stripped" | grep -q "^[[:space:]]*$(printf '%s' "$table" \
      | sed 's/[][\.*^$]/\\&/g')" && printf '%s ' "$table"
  done
  return 0
}

while [ $# -gt 0 ]; do
  case $1 in
    -h|--help) usage; exit "$EXIT_OK" ;;
    -V|--version) version; exit "$EXIT_OK" ;;
    -n|--dry-run) DRY_RUN=1 ;;
    -f|--force) FORCE=1 ;;
    --no-plugin) LINK_PLUGIN=0 ;;
    -q|--quiet) QUIET=1 ;;
    --) shift; break ;;
    -*) die "unknown option: $1" ;;
    *) usage; exit "$EXIT_USAGE" ;;
  esac
  shift
done

main() {
  require awk
  require sed
  herdr=${HERDR_BIN_PATH:-herdr}
  command -v "$herdr" >/dev/null 2>&1 || die "herdr not found; install it first"
  require jq
  [ -f "$SRC_DIR/sensible.toml" ] || die "sensible.toml missing next to $prog"

  conflicts=$(conflicting_tables)
  if [ -n "$conflicts" ] && [ "$FORCE" -eq 0 ] && ! has_our_block; then
    err "$prog: $CONFIG already defines: $conflicts"
    err "TOML has no duplicate tables, so appending would break the file."
    err "Merge sensible.toml by hand, or re-run with --force to back up and replace."
    exit "$EXIT_CONFLICT"
  fi

  run mkdir -p "$CONFIG_DIR/bin"
  for script in agent-labels.sh scrollback-search.sh last-target.sh; do
    run cp "$SRC_DIR/bin/$script" "$CONFIG_DIR/bin/$script"
    run chmod 755 "$CONFIG_DIR/bin/$script"
  done
  log "installed bin/ into $CONFIG_DIR/bin"

  if [ -f "$CONFIG" ]; then
    backup=$CONFIG.bak.$(date +%Y%m%d%H%M%S)
    run cp "$CONFIG" "$backup"
    log "backed up $CONFIG -> $backup"
  else
    backup=""
    run touch "$CONFIG"
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    printf 'DRY-RUN: merge sensible.toml into %s between markers\n' "$CONFIG"
  else
    tmp=$CONFIG.tmp.$$
    # Drop any previous block of ours, keep everything else, append fresh.
    awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
      index($0, b) { skip = 1; next } index($0, e) { skip = 0; next } !skip' \
      "$CONFIG" > "$tmp"
    if [ "$FORCE" -eq 1 ] && [ -n "$conflicts" ]; then
      for table in $TABLES; do
        esc=$(printf '%s' "$table" | sed 's/[][\.*^$]/\\&/g')
        awk -v t="^[[:space:]]*$esc" '
          $0 ~ t { drop = 1; next }
          /^[[:space:]]*\[/ { drop = 0 }
          !drop' "$tmp" > "$tmp.2"
        mv "$tmp.2" "$tmp"
      done
      log "removed conflicting tables: $conflicts"
    fi
    {
      printf '%s\n' "$BEGIN_MARK"
      printf '# Managed by tmux2herdr install.sh. Edits between the markers\n'
      printf '# are replaced on the next install; put yours outside them.\n'
      cat "$SRC_DIR/sensible.toml"
      printf '%s\n' "$END_MARK"
    } >> "$tmp"
    mv "$tmp" "$CONFIG"
    log "merged sensible.toml into $CONFIG"

    # A config Herdr rejects is worse than no install: roll back and say so.
    if ! "$herdr" config check >/dev/null 2>&1; then
      if [ -n "$backup" ]; then
        cp "$backup" "$CONFIG"
        err "$prog: herdr rejected the merged config; restored $backup"
      else
        rm -f "$CONFIG"
        err "$prog: herdr rejected the merged config; removed it"
      fi
      "$herdr" config check || true
      exit "$EXIT_ERROR"
    fi
    log "herdr config check: ok"
  fi

  if [ "$LINK_PLUGIN" -eq 1 ]; then
    run "$herdr" plugin link "$SRC_DIR" \
      || err "$prog: plugin link failed; config still installed, labels fall back to the timer"
  fi

  log ""
  log "done. reload a running server with:  $herdr server reload-config"
  log "prefix is ctrl+h; press prefix+? for the keymap"
}

main "$@"
