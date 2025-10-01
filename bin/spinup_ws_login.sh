#!/bin/sh
# Jellyfin WAN "Home" connect -> spin up NAS disks using SCSI START UNIT (sg_start).
# - No file/block reads (safer on QNAP ext4/RAID/DRBD/cache).
# - Triggers on Jellyfin WebSocket "request" lines (after login; not on login page).
# - WAN-only by default (LAN optional), cooldown gating, boot wait (5 min).
# - BusyBox/QNAP-safe, single instance via a lock directory.
#
# Tested: QNAP HS-264, QTS 5.x, admin SSH, PuTTY.
# Requirements: sg3_utils (sg_start) present in PATH (/usr/sbin preferred).
#
# Tunables:
#   LOG_DIR        Jellyfin logs folder
#   COOLDOWN       seconds between spinups (default 150)
#   SLEEP          main loop period (default 2)
#   BOOT_WAIT      seconds after boot before acting (default 300 = 5 min)
#   ALLOW_PRIVATE  0=ignore LAN/private IPs, 1=allow LAN as trigger (default 0)
#   TRIGGER_PATTERN grep -E pattern for lines to match (default WebSocket "request")
#   FORCE_MD       set to e.g. md3 to force which md array to wake
#
PATH=/bin:/sbin:/usr/bin:/usr/sbin

LOG_DIR="/share/CACHEDEV1_DATA/.qpkg/jellyfin/logs"
COOLDOWN=150
SLEEP=2
BOOT_WAIT=300
ALLOW_PRIVATE=0
TRIGGER_PATTERN='WebSocketManager: WS ".*" request'
FORCE_MD=""

LOCK="/var/run/jellyfin-hdd-spinup.lock"
TAILPID=""
last_spin=0

# --- resolve sg_start binary
SG_START=""
for c in /usr/sbin/sg_start /sbin/sg_start /usr/bin/sg_start /bin/sg_start; do
  if [ -x "$c" ]; then SG_START="$c"; break; fi
done

is_private_ip() {
  case "$1" in
    10.*|127.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*) return 0 ;;
    *) return 1 ;;
  esac
}

uptime_secs() { awk '{print int($1)}' /proc/uptime 2>/dev/null || echo 0; }

# pick the largest md data array (exclude md9/md13/md321) unless FORCE_MD is set
pick_data_md() {
  if [ -n "$FORCE_MD" ]; then echo "$FORCE_MD"; return 0; fi
  awk '
    /^md[0-9]+ :/ {m=$1; next}
    /blocks/ && m!="" {print m,$1; m=""}
  ' /proc/mdstat 2>/dev/null   | grep -Ev '^(md9|md13|md321) '   | sort -k2,2n | tail -1 | awk '{print $1}'
}

# list base /dev/sdX for a given md from /proc/mdstat
md_bases() {
  MD="$1"
  [ -z "$MD" ] && return 0
  line=$(awk -v M="$MD" '$1==M{print;exit}' /proc/mdstat 2>/dev/null)
  [ -z "$line" ] && return 0
  for part in $(echo "$line" | grep -Eo '([shv]d[a-z]+[0-9]+)'); do
    base=$(echo "$part" | sed 's/[0-9]\+$//')
    echo "/dev/$base"
  done | sort -u
}

spin_up_once() {
  # Gate on boot wait
  U=$(uptime_secs)
  if [ "$U" -lt "$BOOT_WAIT" ]; then
    return 0
  fi

  # Use SCSI START UNIT (no data reads)
  [ -n "$SG_START" ] || return 0
  MD=$(pick_data_md)
  for d in $(md_bases "$MD"); do
    [ -b "$d" ] || continue
    "$SG_START" --start "$d" >/dev/null 2>&1 || true
  done
}

latest_log() { ls -t "$LOG_DIR"/log_*.log 2>/dev/null | head -n1; }

start_tail() {
  [ -n "$TAILPID" ] && kill "$TAILPID" 2>/dev/null
  tail -n 0 -f "$CURRENT_FILE" 2>/dev/null | while IFS= read -r line; do
    echo "$line" | grep -E -q "$TRIGGER_PATTERN" || continue
    ip=$(echo "$line" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n1)
    [ -n "$ip" ] || continue
    if [ "$ALLOW_PRIVATE" -ne 1 ]; then
      is_private_ip "$ip" && continue
    fi
    now=$(date +%s)
    elapsed=$((now - last_spin))
    if [ "$elapsed" -ge "$COOLDOWN" ]; then
      spin_up_once
      last_spin=$now
    fi
  done &
  TAILPID=$!
}

# single instance
mkdir "$LOCK" 2>/dev/null || exit 0

CURRENT_FILE=""
while :; do
  LATEST=$(latest_log)
  if [ -n "$LATEST" ] && [ "$LATEST" != "$CURRENT_FILE" ]; then
    CURRENT_FILE="$LATEST"
    start_tail
  fi
  sleep "$SLEEP"
done
