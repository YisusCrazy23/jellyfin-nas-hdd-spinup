#!/bin/sh
# uninstall.sh — stop and remove Jellyfin HDD Spinup watcher/QPKG
set -eu

DEST="/etc/config/jellyfin-hdd-spinup"
QPKG_DIR="/share/CACHEDEV1_DATA/.qpkg/JellyfinHDDSpinup"
QPKG_SH="$QPKG_DIR/JellyfinHDDSpinup.sh"
QPKG_CONF="/etc/config/qpkg.conf"

echo "[-] Stopping watcher"
[ -x "$QPKG_SH" ] && "$QPKG_SH" stop >/dev/null 2>&1 || true
PIDS="$(ps | awk '/[s]pinup_ws_login\.sh/ {print $1}')"
[ -n "$PIDS" ] && kill -9 $PIDS 2>/dev/null || true
rm -rf /var/run/jellyfin_hdd_spinup.lock /tmp/spinup_ws.* 2>/dev/null || true

echo "[-] Removing cron guard"
grep -v 'JellyfinHDDSpinup' /etc/config/crontab > /etc/config/crontab.new 2>/dev/null || true
mv /etc/config/crontab.new /etc/config/crontab 2>/dev/null || true
/etc/init.d/crond.sh restart || true

echo "[-] Removing QPKG entry and files"
# remove qpkg.conf section
tmpconf="$(mktemp)"
awk '
  BEGIN {skip=0}
  /^\[JellyfinHDDSpinup\]/ {skip=1; next}
  /^\[/ {skip=0}
  skip==0 {print}
' "$QPKG_CONF" > "$tmpconf" 2>/dev/null || true
mv "$tmpconf" "$QPKG_CONF" 2>/dev/null || true

rm -rf "$QPKG_DIR" 2>/dev/null || true

echo "[-] Removing installed watcher"
rm -rf "$DEST" 2>/dev/null || true

echo "[OK] Uninstall complete."
