#!/bin/sh
# Tail the latest Jellyfin log and print WAN WebSocket detections (no spin-up)
PATH=/bin:/sbin:/usr/bin:/usr/sbin
LOG_DIR="/share/CACHEDEV1_DATA/.qpkg/jellyfin/logs"

LATEST=$(ls -t "$LOG_DIR"/log_*.log 2>/dev/null | head -n1)
if [ -z "$LATEST" ]; then
  echo "No log file found in $LOG_DIR"
  exit 1
fi

tail -n0 -F "$LATEST" | while read -r line; do
  echo "$line" | grep -q 'WebSocketManager: WS ".*" request' || continue
  ip=$(echo "$line" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n1)
  case "$ip" in 10.*|127.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*) continue;; esac
  echo "DETECTED WAN WebSocket 'request' from $ip @ $(date)"
done
