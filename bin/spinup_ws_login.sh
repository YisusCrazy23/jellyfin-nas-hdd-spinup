#!/bin/sh
# Jellyfin WAN WebSocket "request" -> spin-up (md + sg_start), cooldown, BusyBox-friendly.
# Single-instance, log-rotation aware, minimal I/O (read-only).

PATH=/bin:/sbin:/usr/bin:/usr/sbin

# ---- Configuration (override by editing these) ----
LOG_DIR="${LOG_DIR:-/share/CACHEDEV1_DATA/.qpkg/jellyfin/logs}"
COOLDOWN="${COOLDOWN:-150}"          # seconds between actions
SLEEP="${SLEEP:-2}"                  # main loop tick
ALLOW_PRIVATE="${ALLOW_PRIVATE:-0}"  # 0 = WAN-only (default), 1 = include LAN/private IPs
TRIGGER_PATTERN="${TRIGGER_PATTERN:-WebSocketManager: WS \".*\" request}"  # grep -E pattern
FORCE_MD="${FORCE_MD:-}"             # e.g. md3 to force, else auto-pick largest data md

LOCKDIR="/var/run/spinup_ws.lock"
TAILPID=""
last_spin=0

is_private_ip() {
  case "$1" in
    10.*|127.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*) return 0 ;;
    *) return 1 ;;
  esac
}

# Pick the largest md device that looks like "data" (exclude md9/md13/md321 etc. meta/system)
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

# List unique base disks (/dev/sdX) that belong to a given md device
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

# Perform a minimal, read-only wake on the array + explicit SCSI START if available
spin_up_once() {
  MD="$FORCE_MD"
  [ -z "$MD" ] && MD="$(pick_data_md)"
  if [ -n "$MD" ] && [ -b "/dev/$MD" ]; then
    dd if="/dev/$MD" of=/dev/null bs=4K count=4 2>/dev/null
  fi
  if command -v sg_start >/dev/null 2>&1; then
    for d in $(md_bases "$MD"); do
      [ -b "$d" ] && sg_start --start "$d" >/dev/null 2>&1 || true
    done
  fi
}

latest_log() { ls -t "$LOG_DIR"/log_*.log 2>/dev/null | head -n1; }

start_tailproc() {
  [ -n "$TAILPID" ] && kill "$TAILPID" 2>/dev/null
  # Pipe tail to a line reader (no extra logs)
  tail -n 0 -f "$CURRENT_FILE" 2>/dev/null | while IFS= read -r line; do
    echo "$line" | grep -E -q "$TRIGGER_PATTERN" || continue

    # Find the first IPv4 candidate
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
