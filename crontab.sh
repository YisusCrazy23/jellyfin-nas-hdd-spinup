#!/bin/sh
# Install/refresh cron entries for jellyfin-hdd-spinup (QNAP BusyBox-safe)

set -e

CRON="/etc/config/crontab"
TMP="${CRON}.new"
WATCHER="/etc/config/jellyfin-hdd-spinup/spinup_ws_login.sh"

# 0) Sanity: watcher present?
if [ ! -x "$WATCHER" ]; then
  echo "ERROR: watcher not found or not executable: $WATCHER" 1>&2
  exit 1
fi

# 1) Remove any previous lines related to the watcher
grep -v 'jellyfin-hdd-spinup/spinup_ws_login.sh' "$CRON" > "$TMP" 2>/dev/null || true

# 2) Guard: every 2 minutes, (re)start if not present
printf '%s\n' \
'*/2 * * * * /bin/sh -c "ps | grep -q '\''[s]pinup_ws_login.sh'\'' || /etc/config/jellyfin-hdd-spinup/spinup_ws_login.sh >/dev/null 2>&1 &"' \
>> "$TMP"

# 3) Boot-seeder: every minute while uptime < 20 min, (re)start if not present
printf '%s\n' \
'* * * * * /bin/sh -c "U=$(awk '\''{print int($1)}'\'' /proc/uptime 2>/dev/null || echo 999999); if [ \"$U\" -lt 1200 ]; then ps | grep -q '\''[s]pinup_ws_login.sh'\'' || /etc/config/jellyfin-hdd-spinup/spinup_ws_login.sh >/dev/null 2>&1 & fi"' \
>> "$TMP"

# 4) Swap crontab and compile spool
mv "$TMP" "$CRON"
crontab "$CRON" 2>/dev/null || true

# 5) Nudge/restart crond (BusyBox/QTS)
CRONPID="$(ps | awk '/[c]rond/ {print $1; exit}')"
if [ -n "$CRONPID" ]; then
  kill -HUP "$CRONPID" 2>/dev/null || true
else
  /etc/init.d/crond.sh restart >/dev/null 2>&1 || true
fi

# 6) Start now (the watcher itself waits BOOT_WAIT before acting)
 /bin/sh -c "$WATCHER >/dev/null 2>&1 &"

exit 0
