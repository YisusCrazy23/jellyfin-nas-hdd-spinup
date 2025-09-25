
#!/bin/sh
# Live view of WAN WebSocket 'request' lines (no spin-up). Good for confirming triggers.

PATH=/bin:/sbin:/usr/bin:/usr/sbin
LOG_DIR="/share/CACHEDEV1_DATA/.qpkg/jellyfin/logs"
TRIGGER_PATTERN='WebSocketManager: WS ".*" request'

is_private_ip(){ case "$1" in 10.*|127.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*) return 0;; *) return 1;; esac; }
latest_log(){ ls -t "$LOG_DIR"/log_*.log 2>/dev/null | head -n1; }

LATEST="$(latest_log)"
if [ -z "$LATEST" ]; then
  echo "No Jellyfin log file found in $LOG_DIR"
  exit 1
fi

echo "Tailing: $LATEST"
tail -n0 -F "$LATEST" | while read -r line; do
  echo "$line" | grep -Eq "$TRIGGER_PATTERN" || continue
  ip=$(echo "$line" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n1)
  [ -n "$ip" ] || continue
  is_private_ip "$ip" && continue
  echo "DETECTED WAN WebSocket 'request' from $ip @ $(date)"
done
