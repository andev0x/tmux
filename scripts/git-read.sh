#!/usr/bin/env bash
# =============================================================================
# git-read.sh — render the cached git workspace state
#
#   git-read.sh [dir]
#
# Output (status bar segment):
#   󰊢 main ●3   branch with 3 dirty/untracked entries
#   󰊢 main      clean branch
#   󰊢 –         not inside a repository
#
# This script never calls git. It only reads the sample published by
# git-update.sh and kicks off a detached refresh when that sample is stale,
# which keeps the status line latency at a single file read.
# =============================================================================

set -u
export LC_ALL=C

dir=${1:-$PWD}
[ -d "$dir" ] || dir=$PWD

TTL=${TMUX_GIT_TTL:-5}
CACHE_DIR="${TMPDIR:-/tmp}/tmux-telemetry-${UID:-0}"

# Resolve our own directory without forking `dirname`.
self_dir=${0%/*}
[ "$self_dir" = "$0" ] && self_dir=.

if [ ! -d "$CACHE_DIR" ]; then
  mkdir -p "$CACHE_DIR" 2>/dev/null || exit 0
fi

set -- $(printf '%s' "$dir" | cksum)
cache="$CACHE_DIR/git-${1:-0}"
lock="$cache.lock"

now=$(date +%s)

ts=0
repo=0
branch=
dirty=0
if [ -r "$cache" ]; then
  IFS='|' read -r ts repo branch dirty ahead behind <"$cache" 2>/dev/null || ts=0
fi

# A corrupt or partial cache must degrade to a cold cache, never fail.
case ${ts:-0} in '' | *[!0-9]*) ts=0 ;; esac
case ${repo:-0} in 0 | 1) ;; *) repo=0 ;; esac
case ${dirty:-0} in '' | *[!0-9]*) dirty=0 ;; esac

# --------------------------------------------------- stale-while-revalidate
age=$((now - ${ts:-0}))
refresh=0
if [ "${ts:-0}" -eq 0 ] || [ "$age" -ge "$TTL" ] || [ "$age" -lt 0 ]; then
  refresh=1
fi

if [ "$refresh" = "1" ] && [ -d "$lock" ]; then
  # A live worker owns the lock; a dead one leaves it behind for >30s.
  m=$(date -r "$lock" +%s 2>/dev/null) || m=
  if [ -n "$m" ] && [ $((now - m)) -le 30 ]; then
    refresh=0
  else
    rmdir "$lock" 2>/dev/null
  fi
fi

if [ "$refresh" = "1" ]; then
  (TMUX_GIT_SYNC=1 "$self_dir/git-update.sh" "$dir" </dev/null >/dev/null 2>&1 &)
fi

# ------------------------------------------------------------------- display
if [ "${repo:-0}" != "1" ]; then
  printf '󰊢 –\n'
elif [ "${dirty:-0}" -gt 0 ] 2>/dev/null; then
  printf '󰊢 %s ●%s\n' "${branch:-?}" "$dirty"
else
  printf '󰊢 %s\n' "${branch:-?}"
fi
