#!/bin/sh
# Uninstall jellyfin-HDD-spinup (QNAP BusyBox-safe) — all-in-one
set -e
PATH=/bin:/sbin:/usr/bin:/usr/sbin

BASE="/etc/config/jellyfin-hdd-spinup"
CRON="/etc/config/crontab"
TMP="${CRON}.new"
LOCK="/var/run/jellyfin-hdd-spinup.lock"

echo "[-] Stopping watcher"
PIDS="$(ps | awk '/[s]pinup_ws_login\.sh/ {print $1}')"
[ -n "$PIDS" ] && kill -9 $PIDS 2>/dev/null || true
rm -rf "$LOCK" /tmp/jf_spinup.* 2>/dev/null || true

echo "[-] Removing cron guard + boot-seeder"
grep -v 'jellyfin-hdd-spinup/spinup_ws_login.sh' "$CRON" > "$TMP" 2>/dev/null || true
mv "$TMP" "$CRON"
crontab "$CRON" 2>/dev/null || true
CRONPID="$(ps | awk '/[c]rond/ {print $1; exit}')"
[ -n "$CRONPID" ] && kill -HUP "$CRONPID" 2>/dev/null || /etc/init.d/crond.sh restart >/dev/null 2>&1 || true

echo "[-] Cleaning legacy rc.local lines (if any)"
if [ -f /etc/rc.local ]; then
  sed -e '/jellyfin-hdd-spinup/d' /etc/rc.local > /etc/rc.local.new 2>/dev/null || true
  mv /etc/rc.local.new /etc/rc.local 2>/dev/null || true
  chmod +x /etc/rc.local 2>/dev/null || true
fi

echo "[-] Removing files"
rm -rf "$BASE" 2>/dev/null || true

echo "[✓] Uninstall complete"
exit 0
