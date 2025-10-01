#!/bin/sh
# Uninstall jellyfin-hdd-spinup (QNAP BusyBox-safe)

set -e

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

echo "[-] Removing rc.local hook (if any)"
if [ -f /etc/rc.local ]; then
  # Try in-place deletion; fallback to tmp if busybox sed lacks -i
  if sed -n '/BEGIN JF HDD SPINUP/,/END JF HDD SPINUP/p' /etc/rc.local >/dev/null 2>&1; then
    ( sed -i '/BEGIN JF HDD SPINUP/,/END JF HDD SPINUP/d' /etc/rc.local 2>/dev/null ) || {
      cp /etc/rc.local /etc/rc.local.bak.$$ 2>/dev/null || true
      sed '/BEGIN JF HDD SPINUP/,/END JF HDD SPINUP/d' /etc/rc.local >/etc/rc.local.new 2>/dev/null || true
      mv /etc/rc.local.new /etc/rc.local 2>/dev/null || true
    }
  fi
fi

echo "[-] Removing files"
rm -rf "$BASE" 2>/dev/null || true

echo "[✓] Uninstall complete"
exit 0
