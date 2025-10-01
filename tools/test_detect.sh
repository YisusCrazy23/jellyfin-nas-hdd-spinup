#!/bin/sh
# Show WAN WebSocket trigger lines in real time (no spin-up).

PATH=/bin:/sbin:/usr/bin:/usr/sbin

LOG_DIR="${LOG_DIR:-/share/CACHEDEV1_DATA/.qpkg/jellyfin/logs}"
TRIGGER_PATTERN="${TRIGGER_PATTERN:-WebSocketManager: WS \".*\" request}"
ALLOW_PRIVATE="${ALLOW_PRIVATE:-0}"

is_private_ip() {
  case "$1" in
    10.*|127.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*) return 0 ;;
    *) return 1 ;;
  esac
}

LATEST="$(ls -t "$LOG_DIR"/log_*.log 2>/dev/null | head -n1)"
[ -z "$LATEST" ] && echo "No Jellyfin log_*.log yet in $LOG_DIR" && exit 1

tail -n0 -F "$LATEST" 2>/dev/null | while read -r line; do
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

  echo "DETECTED WebSocket from $WAN @ $(date)"
done
