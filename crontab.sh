#!/bin/sh
# Reinstall cron guard and compile into cron spool (for QNAP that forgets it on boot)
PATH=/bin:/sbin:/usr/bin:/usr/sbin
CRON="/etc/config/crontab"
TMP="${CRON}.new"
grep -v 'jellyfin-hdd-spinup/spinup_ws_login.sh' "$CRON" > "$TMP" 2>/dev/null || true
echo '*/2 * * * * /bin/sh -c "ps | grep -q '\''[s]pinup_ws_login.sh'\'' || /etc/config/jellyfin-hdd-spinup/spinup_ws_login.sh >/dev/null 2>&1 &"' >> "$TMP"
mv "$TMP" "$CRON"
crontab "$CRON" 2>/dev/null || true
CRONPID="$(ps | awk '/[c]rond/ {print $1; exit}')"
[ -n "${CRONPID:-}" ] && kill -HUP "$CRONPID" 2>/dev/null || /etc/init.d/crond.sh restart >/dev/null 2>&1 || true
echo "[✓] Cron guard reinstalled."
