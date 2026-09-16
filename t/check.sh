#!/bin/sh
# shellcheck shell=sh
# Version: 0.1.0

set -eu

CDPATH=''
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
scripts="$root/install.sh $root/bin/agent-labels.sh $root/bin/scrollback-search.sh $root/bin/last-target.sh $root/t/check.sh"
fail=0

for s in $scripts; do
  [ -x "$s" ] || { printf 'not executable: %s\n' "$s" >&2; fail=1; }
done

if command -v shellcheck >/dev/null 2>&1; then
  # shellcheck disable=SC2086  # deliberate word splitting over the list
  shellcheck -s sh $scripts || fail=1
  printf 'shellcheck: done\n'
else
  printf 'shellcheck: not installed, skipped\n' >&2
fi

if command -v dash >/dev/null 2>&1; then
  for s in $scripts; do dash -n "$s" || fail=1; done
  printf 'dash -n: done\n'
else
  for s in $scripts; do sh -n "$s" || fail=1; done
  printf 'dash: not installed, used sh -n\n' >&2
fi

# The config block must parse, and must still contain the prefix.
grep -q '^prefix = ' "$root/sensible.toml" || { printf 'sensible.toml: no prefix\n' >&2; fail=1; }
grep -q 'min_herdr_version' "$root/herdr-plugin.toml" || { printf 'manifest: no min_herdr_version\n' >&2; fail=1; }
if command -v herdr >/dev/null 2>&1; then
  HERDR_CONFIG_PATH=$root/sensible.toml herdr config check || fail=1
else
  printf 'herdr: not installed, config check skipped\n' >&2
fi

[ "$fail" -eq 0 ] || { printf 'FAIL\n' >&2; exit 1; }
printf 'ok\n'
