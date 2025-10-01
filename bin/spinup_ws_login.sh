#!/bin/sh
# jellyfin-HDD-spinup: Wake NAS disks when a WAN client reaches Jellyfin’s home.
# Safe mode: NO filesystem reads/writes. Uses SCSI START UNIT via sg_start.
# - Tails Jellyfin logs for: WebSocketManager: WS "IP" request
# - Filters WAN (public) IPs by default (LAN optional)
# - Cooldown between spin-ups; waits BOOT_WAIT seconds after boot before acting
# - Picks the largest data md (from /proc/mdstat) and runs sg_start on member /dev/sdX
#
# Tested on: QNAP HS-264 (QTS 5.x) + TR-004, Jellyfin .qpkg logs under
#   /share/CACHEDEV1_DATA/.qpkg/jellyfin/logs
#
# Configuration (edit as needed):
LOG_DIR="/share/CACHEDEV1_DATA/.qpkg/jellyfin/logs"
COOLDOWN=150          # seconds between spin-ups
SLEEP=2               # loop tick (seconds)
BOOT_WAIT=420         # minimum uptime before reacting (7 minutes)
ALLOW_PRIVATE=0       # 0 = WAN only (default), 1 = also trigger for LAN/private IPs
TRIGGER_PATTERN='WebSocketManager: WS ".*" request'  # grep -E pattern to match lines
FORCE_MD=""           # e.g., FORCE_MD="md3" to force which md to wake

LOCKDIR="/var/run/jellyfin-hdd-spinup.lock"
PIPE="/tmp/jf_spinup.$$"
TAILPID=""
last_spin=0

PATH=/bin:/sbin:/usr/bin:/usr/sbin

is_private_ip() {
  case "$1" in
    10.*|127.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*) return 0 ;;
    *) return 1 ;;
  esac
}

uptime_sec() {
  awk '{printf "%d", $1}' /proc/uptime 2>/dev/null
}

# pick the largest data md from /proc/mdstat, excluding md9/md13/md321
pick_data_md() {
  if [ -n "$FORCE_MD" ]; then
    echo "$FORCE_MD"
    return 0
  fi
  awk '
    /^md[0-9]+ :/ {md=$1; next}
    /blocks/ && md!=""{print md, $1; md=""}
  ' /proc/mdstat 2>/dev/null \
  | grep -Ev '^(md9|md13|md321) ' \
  | sort -k2,2n | tail -1 | awk '{print $1}'
}

# list member base devices (/dev/sdX) for a given md array
md_bases() {
  MD="$1"
  [ -n "$MD" ] || return 0
  line="$(awk -v M="$MD" '$1==M{print;exit}' /proc/mdstat 2>/dev/null)"
  [ -n "$line" ] || return 0
  BASES=""
  for part in $(echo "$line" | grep -Eo '([shv]d[a-z]+[0-9]+)'); do
    b="/dev/$(echo "$part" | sed 's/[0-9]\+$//')"
    echo "$BASES" | grep -qw "$b" || BASES="$BASES $b"
  done
  echo "$BASES"
}

spin_up_once() {
  # only sg_start (no dd). If sg_start missing, silently do nothing.
  command -v sg_start >/dev/null 2>&1 || return 0
  MD="$(pick_data_md)"
  for d in $(md_bases "$MD"); do
    [ -b "$d" ] || continue
    sg_start --start "$d" >/dev/null 2>&1 || true
  done
}

latest_log() {
  ls -t "$LOG_DIR"/log_*.log 2>/dev/null | head -n1
}

start_tail() {
  [ -n "$TAILPID" ] && kill "$TAILPID" 2>/dev/null
  tail -n 0 -f "$CURRENT_FILE" > "$PIPE" 2>/dev/null &
  TAILPID=$!
}

cleanup() {
  [ -n "$TAILPID" ] && kill "$TAILPID" 2>/dev/null
  rm -f "$PIPE"
  rmdir "$LOCKDIR" 2>/dev/null
  exit 0
}

# Single instance
mkdir "$LOCKDIR" 2>/dev/null || exit 0

# Prepare FIFO
rm -f "$PIPE" 2>/dev/null
mkfifo "$PIPE" 2>/dev/null || exit 1

# Wait for a log file to exist
CURRENT_FILE="$(latest_log)"
while [ -z "$CURRENT_FILE" ]; do
  sleep "$SLEEP"
  CURRENT_FILE="$(latest_log)"
done

trap cleanup INT TERM EXIT
start_tail

while :; do
  # Wait for boot settle
  up="$(uptime_sec)"
  if [ -z "$up" ] || [ "$up" -lt "$BOOT_WAIT" ]; then
    sleep "$SLEEP"
    # still rotate the tailer if the file changed
    LATEST="$(latest_log)"
    [ -n "$LATEST" ] && [ "$LATEST" != "$CURRENT_FILE" ] && { CURRENT_FILE="$LATEST"; start_tail; }
    continue
  fi

  # Detect log rotation
  LATEST="$(latest_log)"
  if [ -n "$LATEST" ] && [ "$LATEST" != "$CURRENT_FILE" ]; then
    CURRENT_FILE="$LATEST"
    start_tail
  fi

  # Non-blocking read from FIFO
  if read -t "$SLEEP" line < "$PIPE"; then
    echo "$line" | grep -E -q "$TRIGGER_PATTERN" || continue

    # Extract first IPv4, honor ALLOW_PRIVATE
    WAN=""
    for cand in $(echo "$line" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}'); do
      if [ "$ALLOW_PRIVATE" -eq 1 ]; then
        WAN="$cand"; break
      else
        if ! is_private_ip "$cand"; then WAN="$cand"; break; fi
      fi
    done
    [ -z "$WAN" ] && continue

    now=$(date +%s 2>/dev/null)
    [ -z "$now" ] && now=0
    elapsed=$((now - last_spin))
    if [ "$elapsed" -ge "$COOLDOWN" ]; then
      spin_up_once
      last_spin=$now
    fi
  fi
done
