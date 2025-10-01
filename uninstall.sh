#!/bin/sh
# Uninstaller (clean stop + cron removal)

set -eu
PATH=/bin:/sbin:/usr/bin:/usr/sbin

DEST_DIR="/etc/config/jellyfin-hdd-spinup"
DEST_SCRIPT="$DEST_DIR/spinup_ws_login.sh"
CRON="/etc/config/crontab"

echo "[-] Stopping watcher"
PIDS="$(ps | awk '/[s]pinup_ws_login\.sh/ {print $1}')"
[ -n "${PIDS:-}" ] && kill -9 $PIDS 2>/dev/null || true
rm -rf /var/run/spinup_ws.lock /tmp/spinup_ws.* 2>/dev/null || true

echo "[-] Removing cron guard"
TMP="${CRON}.new"
grep -v 'spinup_ws_login.sh' "$CRON" > "$TMP" 2>/dev/null || true
mv "$TMP" "$CRON"
CRONPID="$(ps | awk '/[c]rond/ {print $1; exit}')"
[ -n "${CRONPID:-}" ] && kill -HUP "$CRONPID" 2>/dev/null || true

if [ -f "$DEST_SCRIPT" ]; then
  echo "[-] Removing $DEST_SCRIPT"
  rm -f "$DEST_SCRIPT"
fi
rmdir "$DEST_DIR" 2>/dev/null || true

echo "[✓] Uninstalled."
