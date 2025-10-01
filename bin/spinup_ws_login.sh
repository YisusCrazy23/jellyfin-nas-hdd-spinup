#!/bin/sh
# Jellyfin WAN WebSocket "request" -> spin-up (sg_start-only), cooldown, BusyBox-friendly.
# Single-instance, log-rotation aware, minimal and safe.
#
# Tested on: QNAP HS-264, QTS 5 (admin over SSH)

PATH=/bin:/sbin:/usr/bin:/usr/sbin

# ---- Configuration (override by editing these) ----
LOG_DIR="${LOG_DIR:-/share/CACHEDEV1_DATA/.qpkg/jellyfin/logs}"
COOLDOWN="${COOLDOWN:-150}"          # seconds between actions
SLEEP="${SLEEP:-2}"                  # main loop tick
BOOT_WAIT="${BOOT_WAIT:-420}"        # min uptime before acting (7 min)
ALLOW_PRIVATE="${ALLOW_PRIVATE:-0}"  # 0 = WAN-only, 1 = include LAN/private IPs
TRIGGER_PATTERN="${TRIGGER_PATTERN:-WebSocketManager: WS \".*\" request}"  # grep -E pattern
FORCE_MD="${FORCE_MD:-}"             # e.g. md3 to force the data array

LOCKDIR="/var/run/spinup_ws.lock"
TAILPID=""
last_spin=0

is_private_ip() {
  case "$1" in
    10.*|127.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*) return 0 ;;
    *) return 1 ;;
  esac
}

uptime_secs() {
  awk '{printf "%d", $1}' /proc/uptime 2>/dev/null
}

pick_data_md() {
  awk '
    /^md[0-9]+ :/ {md=$1; next}
    /blocks/ && md!=""{print md,$1; md=""}
  ' /proc/mdstat 2>/dev/null \
  | grep -Ev '^(md9|md13|md321) ' \
  | sort -k2,2n \
  | tail -1 \
  | awk '{print $1}'
}

md_bases() {
  MD="$1"
  [ -z "$MD" ] && return 0
  line="$(awk -v M="$MD" '$1==M{print;exit}' /proc/mdstat 2>/dev/null)"
  [ -z "$line" ] && return 0
  BASES=""
  for part in $(echo "$line" | grep -Eo '([shv]d[a-z]+[0-9]+)'); do
    b="/dev/$(echo "$part" | sed 's/[0-9]\+$//')"
    echo "$BASES" | grep -qw "$b" || BASES="$BASES $b"
  done
  echo "$BASES"
}

spin_up_once() {
  # Honor boot wait regardless of who started us
  up="$(uptime_secs)"
  [ -n "$up" ] && [ "$up" -lt "$BOOT_WAIT" ] && return 0

  MD="$FORCE_MD"
  [ -z "$MD" ] && MD="$(pick_data_md)"

  # sg_start-only: do not read from md or the filesystem
  if command -v sg_start >/dev/null 2>&1; then
    for d in $(md_bases "$MD"); do
      [ -b "$d" ] && sg_start --start "$d" >/dev/null 2>&1 || true
    done
  fi
}

latest_log() { ls -t "$LOG_DIR"/log_*.log 2>/dev/null | head -n1; }

start_tailproc() {
  [ -n "$TAILPID" ] && kill "$TAILPID" 2>/dev/null
  tail -n 0 -f "$CURRENT_FILE" 2>/dev/null | while IFS= read -r line; do
    echo "$line" | grep -E -q "$TRIGGER_PATTERN" || continue

    WAN=""
    for cand in $(echo "$line" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}'); do
      if [ "$ALLOW_PRIVATE" = "1" ]; then
        WAN="$cand"; break
      else
        if ! is_private_ip "$cand"; then WAN="$cand"; break; fi
      fi
    done
    [ -z "$WAN" ] && continue

    now=$(date +%s); elapsed=$((now - last_spin))
    if [ "$elapsed" -ge "$COOLDOWN" ]; then
      spin_up_once
      last_spin=$now
    fi
  done &
  TAILPID=$!
}

# --- Single-instance guard ---
mkdir "$LOCKDIR" 2>/dev/null || exit 0

CURRENT_FILE=""
while :; do
  LATEST="$(latest_log)"
  if [ -n "$LATEST" ] && [ "$LATEST" != "$CURRENT_FILE" ]; then
    CURRENT_FILE="$LATEST"
    start_tailproc
  fi
  sleep "$SLEEP"
done
