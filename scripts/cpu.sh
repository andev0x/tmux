#!/usr/bin/env bash
# =============================================================================
# cpu.sh — CPU + RAM telemetry for the tmux status line
#
# Output (single line, no ANSI):  󰻠 24% 󰍛 61%
#
# Performance contract
#   * never sleeps and never blocks the status line
#   * samples are memoised for TMUX_TELEMETRY_TTL seconds (default 3)
#   * macOS : one `ps` snapshot + `vm_stat` (no `top -l 2`, which costs ~1.5s)
#   * Linux : /proc/stat delta against the previous sample + /proc/meminfo
#
# The cache lives in the per-user telemetry directory so multiple tmux
# clients share one sample instead of each spawning their own.
# =============================================================================

set -u
export LC_ALL=C

TTL=${TMUX_TELEMETRY_TTL:-3}
CACHE_DIR="${TMPDIR:-/tmp}/tmux-telemetry-${UID:-0}"
CACHE="$CACHE_DIR/cpu"

mkdir -p "$CACHE_DIR" 2>/dev/null || exit 0

now=$(date +%s)

# ---------------------------------------------------------------- cache read
prev_ts=0
prev_cpu=
prev_ram=
prev_total=0
prev_idle=0

if [ -r "$CACHE" ]; then
  read -r prev_ts prev_cpu prev_ram prev_total prev_idle <"$CACHE" 2>/dev/null || prev_ts=0
fi

# A corrupt or partial cache must degrade to a cold sample, never fail.
case ${prev_ts:-0} in '' | *[!0-9]*) prev_ts=0 ;; esac
case ${prev_cpu:-} in '' | *[!0-9]*) prev_cpu= ;; esac
case ${prev_ram:-} in '' | *[!0-9]*) prev_ram= ;; esac
case ${prev_total:-0} in '' | *[!0-9]*) prev_total=0 ;; esac
case ${prev_idle:-0} in '' | *[!0-9]*) prev_idle=0 ;; esac

if [ "${prev_ts:-0}" -gt 0 ] && [ -n "${prev_cpu:-}" ] && [ -n "${prev_ram:-}" ]; then
  age=$((now - prev_ts))
  if [ "$age" -ge 0 ] && [ "$age" -lt "$TTL" ]; then
    printf '󰻠 %s%% 󰍛 %s%%\n' "$prev_cpu" "$prev_ram"
    exit 0
  fi
fi

# ------------------------------------------------------------------- helpers
os=$(uname -s)

clamp() {
  case ${1:-} in
    '' | *[!0-9]*) printf '0' ;;
    *) [ "$1" -gt 100 ] && printf '100' || printf '%s' "$1" ;;
  esac
}

# Emits "<usage> <raw_total> <raw_idle>"; the raw counters let the next run
# calculate an instantaneous delta without ever sleeping.
cpu_sample() {
  case $os in
    Linux)
      [ -r /proc/stat ] || return 1
      read -r _ u n s i w irq sirq st _ </proc/stat || return 1
      total=$((u + n + s + i + w + irq + sirq + st))
      idle=$((i + w))
      [ "$total" -gt 0 ] || return 1
      if [ "$prev_total" -gt 0 ] && [ "$total" -gt "$prev_total" ]; then
        dt=$((total - prev_total))
        di=$((idle - prev_idle))
        [ "$di" -lt 0 ] && di=0
        printf '%s %s %s\n' "$(((100 * (dt - di) + dt / 2) / dt))" "$total" "$idle"
      else
        printf '%s %s %s\n' "$(((100 * (total - idle) + total / 2) / total))" "$total" "$idle"
      fi
      ;;
    Darwin)
      ncpu=$(sysctl -n hw.ncpu 2>/dev/null) || ncpu=1
      case $ncpu in '' | *[!0-9]*) ncpu=1 ;; esac
      [ "$ncpu" -gt 0 ] || ncpu=1
      load=$(ps -A -o %cpu= 2>/dev/null | awk '{ s += $1 } END { printf "%d", s }')
      case ${load:-} in '' | *[!0-9]*) return 1 ;; esac
      # ps reports per-core percentages; normalise against available cores
      printf '%s 0 0\n' "$(((load + ncpu / 2) / ncpu))"
      ;;
    *) return 1 ;;
  esac
}

ram_sample() {
  case $os in
    Linux)
      awk '
        /^MemTotal:/     { t = $2 }
        /^MemAvailable:/ { a = $2 }
        END { if (t > 0) printf "%d", (100 * (t - a) + t / 2) / t; else printf "0" }
      ' /proc/meminfo 2>/dev/null
      ;;
    Darwin)
      page_size=$(sysctl -n hw.pagesize 2>/dev/null) || page_size=4096
      mem_size=$(sysctl -n hw.memsize 2>/dev/null) || return 1
      vm_stat 2>/dev/null | awk -v ps="$page_size" -v total="$mem_size" '
        /Pages active/                 { v = $NF; sub(/\.$/, "", v); a = v }
        /Pages wired down/             { v = $NF; sub(/\.$/, "", v); w = v }
        /Pages occupied by compressor/ { v = $NF; sub(/\.$/, "", v); c = v }
        /Pages compressed/             { if (c == "") { v = $NF; sub(/\.$/, "", v); c = v } }
        END {
          used = (a + w + c) * ps
          if (total > 0) printf "%d", (100 * used + total / 2) / total
          else printf "0"
        }
      '
      ;;
    *) printf '0' ;;
  esac
}

# ---------------------------------------------------------------- sample run
raw_total=0
raw_idle=0

sample=$(cpu_sample) || sample=
if [ -n "$sample" ]; then
  set -- $sample
  cpu=$(clamp "${1:-0}")
  raw_total=${2:-0}
  raw_idle=${3:-0}
else
  cpu=0
fi

ram=$(clamp "$(ram_sample 2>/dev/null)")
[ -n "${ram:-}" ] || ram=0

# --------------------------------------------------------------- cache write
# Atomic write: a concurrent client either sees the old or the new sample.
printf '%s %s %s %s %s\n' "$now" "$cpu" "$ram" "$raw_total" "$raw_idle" >"$CACHE.$$" 2>/dev/null &&
  mv -f "$CACHE.$$" "$CACHE" 2>/dev/null

printf '󰻠 %s%% 󰍛 %s%%\n' "$cpu" "$ram"
