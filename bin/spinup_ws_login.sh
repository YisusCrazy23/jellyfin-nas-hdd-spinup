
#!/bin/sh
# Jellyfin WAN WebSocket "request" -> spin-up (md + optional sg_start), cooldown, silent.
# Read-only micro I/O only. Single-instance. QNAP/BusyBox friendly.

PATH=/bin:/sbin:/usr/bin:/usr/sbin

# === Tunables ===============================================================
LOG_DIR="/share/CACHEDEV1_DATA/.qpkg/jellyfin/logs"   # Jellyfin log folder
COOLDOWN=150                                          # Seconds between wake actions
SLEEP=2                                               # Main loop period
ALLOW_PRIVATE=0                                       # 0=WAN only (default), 1=also allow private/LAN IPs
TRIGGER_PATTERN='WebSocketManager: WS ".*" request'   # Change to broaden if needed
FORCE_MD=""                                           # e.g. "md3" to override auto-detection
LOCKDIR="/var/run/spinup_ws.lock"                     # Single-instance lock
# ===========================================================================

TAILPID=""
last_spin=0

is_private_ip(){
  case "$1" in
    10.*|127.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*) return 0 ;;
    *) return 1 ;;
  esac
}

# Pick the largest "data" md device (exclude md9/md13/md321) unless FORCE_MD is set
pick_data_md(){
  [ -n "$FORCE_MD" ] && { echo "$FORCE_MD"; return; }
  awk '
    /^md[0-9]+ :/ {md=$1; next}
    /blocks/ && md!=""{print md,$1; md=""}
  ' /proc/mdstat 2>/dev/null \
  | grep -Ev '^(md9|md13|md321) ' \
  | sort -k2,2n \
  | tail -1 \
  | awk '{print $1}'
}

# List unique /dev/sdX members of a given md (from /proc/mdstat)
md_bases(){
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

# Minimal wake: read a tiny block from md, then (if available) send SCSI START to members
spin_up_once(){
  MD="$(pick_data_md)"
  [ -b "/dev/$MD" ] && dd if="/dev/$MD" of=/dev/null bs=4K count=4 2>/dev/null

  if command -v sg_start >/dev/null 2>&1; then
    for d in $(md_bases "$MD"); do
      [ -b "$d" ] && sg_start --start "$d" >/dev/null 2>&1 || true
    done
  fi
}

latest_log(){ ls -t "$LOG_DIR"/log_*.log 2>/dev/null | head -n1; }

start_tailproc(){
  [ -n "$TAILPID" ] && kill "$TAILPID" 2>/dev/null
  tail -n 0 -f "$CURRENT_FILE" 2>/dev/null | while IFS= read -r line; do
    echo "$line" | grep -Eq "$TRIGGER_PATTERN" || continue

    ip=$(echo "$line" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n1)
    [ -n "$ip" ] || continue
    if [ "$ALLOW_PRIVATE" -eq 0 ] && is_private_ip "$ip"; then
      continue
    fi

    now=$(date +%s); elapsed=$((now - last_spin))
    if [ "$elapsed" -ge "$COOLDOWN" ]; then
      spin_up_once
      last_spin=$now
    fi
  done &
  TAILPID=$!
}

# Single-instance
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
