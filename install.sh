#!/bin/sh
# Idempotent installer for QNAP (run as 'admin' over SSH). PuTTY-safe.

set -eu
PATH=/bin:/sbin:/usr/bin:/usr/sbin

DEST_DIR="/etc/config/jellyfin-hdd-spinup"
DEST_SCRIPT="$DEST_DIR/spinup_ws_login.sh"
CRON="/etc/config/crontab"
RC="/etc/rc.local"

echo "[+] Creating destination dir: $DEST_DIR"
mkdir -p "$DEST_DIR"

echo "[+] Installing watcher to $DEST_SCRIPT"
cp -f "bin/spinup_ws_login.sh" "$DEST_SCRIPT"
chmod +x "$DEST_SCRIPT"

echo "[+] Stopping any running instance"
PIDS="$(ps | awk '/[s]pinup_ws_login\.sh/ {print $1}')"
[ -n "${PIDS:-}" ] && kill -9 $PIDS 2>/dev/null || true
rm -rf /var/run/spinup_ws.lock /tmp/spinup_ws.* 2>/dev/null || true

echo "[+] Starting watcher"
/bin/sh -c "$DEST_SCRIPT >/dev/null 2>&1 &"

echo "[+] Ensuring cron guard exists (every 2 minutes)"
TMP="${CRON}.new"
grep -v 'spinup_ws_login.sh' "$CRON" > "$TMP" 2>/dev/null || true
echo '*/2 * * * * /bin/sh -c "ps | grep -q '\''[s]pinup_ws_login.sh'\'' || /etc/config/jellyfin-hdd-spinup/spinup_ws_login.sh >/dev/null 2>&1 &"' >> "$TMP"
mv "$TMP" "$CRON"

# Politely reload crond; if not running, restart in background (avoid killing the SSH TTY)
CRONPID="$(ps | awk '/[c]rond/ {print $1; exit}')"
if [ -n "${CRONPID:-}" ]; then
  kill -HUP "$CRONPID" 2>/dev/null || true
else
  /etc/init.d/crond.sh restart >/dev/null 2>&1 &
fi

echo "[+] Ensuring /etc/rc.local boot hook (delayed start)"
if [ ! -f "$RC" ]; then
  echo "[i] Creating $RC"
  printf '#!/bin/sh\n\nexit 0\n' > "$RC"
  chmod +x "$RC"
fi

# Remove any previous jellyfin-hdd-spinup block and any trailing 'exit 0'
TMP="${RC}.tmp.$$"
awk '
  BEGIN{skip=0}
  /BEGIN jellyfin-hdd-spinup/ {skip=1; next}
  /END jellyfin-hdd-spinup/ {skip=0; next}
  {print}
' "$RC" | awk '{ if ($0 ~ /^[[:space:]]*exit[[:space:]]+0[[:space:]]*$/) next; print }' > "$TMP"

# Append our block and one final exit 0
cat >> "$TMP" <<'BLOCK'
# BEGIN jellyfin-hdd-spinup
( sleep 300; /bin/sh /etc/config/jellyfin-hdd-spinup/spinup_ws_login.sh >/dev/null 2>&1 & ) &
# END jellyfin-hdd-spinup
exit 0
BLOCK

mv "$TMP" "$RC"
chmod +x "$RC"

echo "[✓] Install done. Verify with:  ps | grep '[s]pinup_ws_login.sh'"
