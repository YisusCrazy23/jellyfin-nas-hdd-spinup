#!/bin/sh
# Install jellyfin-HDD-spinup (QNAP QTS 5, BusyBox-safe) — all-in-one (cron integrated)
set -e
PATH=/bin:/sbin:/usr/bin:/usr/sbin

DEST="/etc/config/jellyfin-hdd-spinup"
CRON="/etc/config/crontab"
TMP="${CRON}.new"

echo "[+] Creating destination dir: $DEST"
mkdir -p "$DEST"

echo "[+] Installing watcher to $DEST/spinup_ws_login.sh"
cp -f "./bin/spinup_ws_login.sh" "$DEST/spinup_ws_login.sh"
chmod +x "$DEST/spinup_ws_login.sh"

echo "[+] Stopping any running instance"
PIDS="$(ps | awk '/[s]pinup_ws_login\.sh/ {print $1}')"
[ -n "$PIDS" ] && kill -9 $PIDS 2>/dev/null || true
rm -rf /var/run/jellyfin-hdd-spinup.lock /tmp/jf_spinup.* 2>/dev/null || true

echo "[+] Starting watcher now"
/bin/sh -c "$DEST/spinup_ws_login.sh >/dev/null 2>&1 &"

echo "[+] Writing cron guard + boot-seeder"
# Remove any old lines
grep -v 'jellyfin-hdd-spinup/spinup_ws_login.sh' "$CRON" > "$TMP" 2>/dev/null || true
# Guard every 2 min
echo '*/2 * * * * /bin/sh -c "ps | grep -q '\''[s]pinup_ws_login.sh'\'' || /etc/config/jellyfin-hdd-spinup/spinup_ws_login.sh >/dev/null 2>&1 &"' >> "$TMP"
# Boot-seeder: each minute while uptime < 20 min
echo '* * * * * /bin/sh -c "U=$(awk '\''{print int($1)}'\'' /proc/uptime 2>/dev/null || echo 999999); if [ "$U" -lt 1200 ]; then ps | grep -q '\''[s]pinup_ws_login.sh'\'' || /etc/config/jellyfin-hdd-spinup/spinup_ws_login.sh >/dev/null 2>&1 & fi"' >> "$TMP"
mv "$TMP" "$CRON"
crontab "$CRON" 2>/dev/null || true

# HUP crond or restart
CRONPID="$(ps | awk '/[c]rond/ {print $1; exit}')"
if [ -n "$CRONPID" ]; then
  kill -HUP "$CRONPID" 2>/dev/null || true
else
  /etc/init.d/crond.sh restart >/dev/null 2>&1 || true
fi

echo "[✓] Install complete."
echo "    Verify: ps | grep '[s]pinup_ws_login.sh'"
echo "    Cron  : crontab -l | grep jellyfin-hdd-spinup"
exit 0
