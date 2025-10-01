#!/bin/sh
# Uninstaller (stop watcher + remove cron guard + remove rc.local hook + files)
PATH=/bin:/sbin:/usr/bin:/usr/sbin
set -u

DEST_DIR="/etc/config/jellyfin-hdd-spinup"
DEST_SCRIPT="$DEST_DIR/spinup_ws_login.sh"
CRON="/etc/config/crontab"
RCLOCAL="/etc/rc.local"

echo "[-] Stopping watcher"
PIDS="$(ps | awk '/[s]pinup_ws_login\.sh/ {print $1}')"
[ -n "${PIDS:-}" ] && kill -9 $PIDS 2>/dev/null || true
rm -rf /var/run/jellyfin-hdd-spinup.lock /tmp/jf_spinup.* 2>/dev/null || true

echo "[-] Removing cron guard"
TMP="${CRON}.new"
grep -v 'jellyfin-hdd-spinup/spinup_ws_login.sh' "$CRON" > "$TMP" 2>/dev/null || true
mv "$TMP" "$CRON"
crontab "$CRON" 2>/dev/null || true
CRONPID="$(ps | awk '/[c]rond/ {print $1; exit}')"
[ -n "${CRONPID:-}" ] && kill -HUP "$CRONPID" 2>/dev/null || /etc/init.d/crond.sh restart >/dev/null 2>&1 || true

echo "[-] Removing rc.local hook (if present)"
if [ -f "$RCLOCAL" ] && grep -q 'BEGIN JF HDD SPINUP' "$RCLOCAL"; then
  cp "$RCLOCAL" "${RCLOCAL}.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
  sed '/^# BEGIN JF HDD SPINUP/,/^# END JF HDD SPINUP/d' "$RCLOCAL" > "${RCLOCAL}.new" 2>/dev/null || true
  # Ensure exit 0 at end
  if ! tail -n1 "${RCLOCAL}.new" | grep -q '^exit 0$'; then
    echo "exit 0" >> "${RCLOCAL}.new"
  fi
  mv "${RCLOCAL}.new" "$RCLOCAL"
  chmod +x "$RCLOCAL" 2>/dev/null || true
fi

echo "[-] Removing files"
[ -f "$DEST_SCRIPT" ] && rm -f "$DEST_SCRIPT"
rmdir "$DEST_DIR" 2>/dev/null || true

echo "[✓] Uninstalled."
