#!/usr/bin/env bash
# =============================================================================
# git-update.sh — refresh the cached git state used by the status line
#
#   git-update.sh [dir]                 status mode: print now, refresh in the
#                                       background when the cache is stale
#   TMUX_GIT_SYNC=1 git-update.sh [dir] worker mode: sample git, then print
#   TMUX_GIT_FORCE=1 git-update.sh [dir] refresh in the foreground (bind u)
#
# Output (status bar segment):
#   󰚰 ↑1 ↓2   branch is ahead/behind its upstream
#   󰚰 ✓       branch is in sync with its upstream
#   󰚰 –       no upstream, or not inside a repository
#
# A single `git status --porcelain=v2 --branch` call yields the branch name,
# the upstream divergence and the dirty count, so the status line never pays
# for several git invocations. The expensive work always happens in a
# detached worker, never on the status line's critical path.
# =============================================================================

set -u
export LC_ALL=C
export GIT_OPTIONAL_LOCKS=0

dir=${1:-$PWD}
[ -d "$dir" ] || dir=$PWD

TTL=${TMUX_GIT_TTL:-5}
CACHE_DIR="${TMPDIR:-/tmp}/tmux-telemetry-${UID:-0}"
mkdir -p "$CACHE_DIR" 2>/dev/null || exit 0

# Stable per-directory key without depending on md5sum/md5 differences.
set -- $(printf '%s' "$dir" | cksum)
cache="$CACHE_DIR/git-${1:-0}"
lock="$cache.lock"

now=$(date +%s)

# ------------------------------------------------------------------ formatting
format_update() { # repo ahead behind
  case ${1:-0} in
    1) ;;
    *) printf '󰚰 –\n'; return ;;
  esac
  # -1 is the "no upstream" sentinel; anything non-numeric degrades to it.
  case ${2:--1} in
    '' | *[!0-9]*) printf '󰚰 –\n'; return ;;
  esac
  if [ "$2" -eq 0 ] && [ "${3:-0}" -eq 0 ] 2>/dev/null; then
    printf '󰚰 ✓\n'
  else
    printf '󰚰'
    [ "$2" -gt 0 ] && printf ' ↑%s' "$2"
    [ "${3:-0}" -gt 0 ] 2>/dev/null && printf ' ↓%s' "$3"
    printf '\n'
  fi
}

# ------------------------------------------------------------------ cache read
ts=0 repo=0 branch= dirty=0 ahead=-1 behind=-1
if [ -r "$cache" ]; then
  IFS='|' read -r ts repo branch dirty ahead behind <"$cache" 2>/dev/null || ts=0
fi

# A corrupt or partial cache must degrade to a cold cache, never fail.
case ${ts:-0} in '' | *[!0-9]*) ts=0 ;; esac
case ${repo:-0} in 0 | 1) ;; *) repo=0 ;; esac
case ${dirty:-0} in '' | *[!0-9]*) dirty=0 ;; esac
case ${ahead:--1} in '' | *[!0-9]*) ahead=-1 ;; esac
case ${behind:--1} in '' | *[!0-9]*) behind=-1 ;; esac

serve() {
  format_update "${repo:-0}" "${ahead:--1}" "${behind:--1}"
}

age=$((now - ${ts:-0}))
lock_is_stale() {
  m=$(date -r "$lock" +%s 2>/dev/null) || return 1
  [ -n "$m" ] && [ $((now - m)) -gt 30 ]
}

# ------------------------------------------------- status mode (non-blocking)
if [ -z "${TMUX_GIT_SYNC:-}" ] && [ -z "${TMUX_GIT_FORCE:-}" ]; then
  if [ "${ts:-0}" -gt 0 ] && [ "$age" -ge 0 ] && [ "$age" -lt "$TTL" ]; then
    serve
    exit 0
  fi
  # Cold or stale cache: answer instantly from whatever we have and let a
  # detached worker refresh the sample.
  if [ ! -d "$lock" ] || lock_is_stale; then
    if [ -d "$lock" ]; then rmdir "$lock" 2>/dev/null; fi
    (TMUX_GIT_SYNC=1 "$0" "$dir" </dev/null >/dev/null 2>&1 &)
  fi
  serve
  exit 0
fi

# ------------------------------------------------------------- worker sampling
# mkdir is atomic: only one worker samples a given directory at a time.
if ! mkdir "$lock" 2>/dev/null; then
  # A worker that was killed can leave its lock behind; recover from that.
  if lock_is_stale; then
    rmdir "$lock" 2>/dev/null
  fi
  mkdir "$lock" 2>/dev/null || {
    serve
    exit 0
  }
fi
trap 'rmdir "$lock" 2>/dev/null' EXIT INT TERM

repo=1
branch=
dirty=0
ahead=-1
behind=-1
oid=

if ! out=$(git -C "$dir" status --porcelain=v2 --branch 2>/dev/null); then
  repo=0
fi

if [ "$repo" -eq 1 ]; then
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case $line in
      '# branch.oid '*) oid=${line#\# branch.oid } ;;
      '# branch.head '*) branch=${line#\# branch.head } ;;
      '# branch.ab '*)
        ab=${line#\# branch.ab }
        ahead=${ab%% *}
        behind=${ab##* }
        ahead=${ahead#+}
        behind=${behind#-}
        ;;
      '#'*) ;;
      *) dirty=$((dirty + 1)) ;;
    esac
  done <<<"$out"
fi

# Detached HEAD falls back to the short commit id.
case ${branch:-} in
  '' | '(detached)') [ -n "${oid:-}" ] && branch=${oid:0:7} ;;
esac
[ -n "${branch:-}" ] || branch='?'
branch=${branch//|/_}
[ "${#branch}" -gt 20 ] && branch="${branch:0:19}…"

# Atomic publish for concurrent readers.
printf '%s|%s|%s|%s|%s|%s\n' "$now" "$repo" "$branch" "$dirty" "$ahead" "$behind" >"$cache.$$" 2>/dev/null &&
  mv -f "$cache.$$" "$cache" 2>/dev/null

format_update "$repo" "$ahead" "$behind"
