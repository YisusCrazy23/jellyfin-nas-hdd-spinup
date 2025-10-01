#!/bin/sh
# Installer for jellyfin-HDD-spinup (QNAP BusyBox friendly)
# - Installs watcher to /etc/config/jellyfin-hdd-spinup/
# - Adds cron guard (every 2 minutes) and compiles cron spool
# - Adds /etc/rc.local fallback (starts watcher once at boot)
# - Starts watcher now (watcher self-waits BOOT_WAIT before acting)

PATH=/bin:/sbin:/usr/bin:/usr/sbin
set -u

SRC_DIR="$(pwd)"
DEST_DIR="/etc/config/jellyfin-hdd-spinup"
DEST_SCRIPT="$DEST_DIR/spinup_ws_login.sh"
CRON="/etc/config/crontab"
RCLOCAL="/etc/rc.local"

echo "[+] Creating destination dir: $DEST_DIR"
mkdir -p "$DEST_DIR"

echo "[+] Installing watcher to $DEST_SCRIPT"
cp "$SRC_DIR/bin/spinup_ws_login.sh" "$DEST_SCRIPT"
chmod +x "$DEST_SCRIPT"

echo "[+] Stopping any running instance"
PIDS="$(ps | awk '/[s]pinup_ws_login\.sh/ {print $1}')"
[ -n "${PIDS:-}" ] && kill -9 $PIDS 2>/dev/null || true
rm -rf /var/run/jellyfin-hdd-spinup.lock /tmp/jf_spinup.* 2>/dev/null || true

echo "[+] Starting watcher"
/bin/sh -c "$DEST_SCRIPT >/dev/null 2>&1 &"

echo "[+] Ensuring cron guard exists (every 2 minutes)"
TMP="${CRON}.new"
grep -v 'jellyfin-hdd-spinup/spinup_ws_login.sh' "$CRON" > "$TMP" 2>/dev/null || true
echo '*/2 * * * * /bin/sh -c "ps | grep -q '\''[s]pinup_ws_login.sh'\'' || /etc/config/jellyfin-hdd-spinup/spinup_ws_login.sh >/dev/null 2>&1 &"' >> "$TMP"
mv "$TMP" "$CRON"
# Compile to spool and nudge cron
crontab "$CRON" 2>/dev/null || true
CRONPID="$(ps | awk '/[c]rond/ {print $1; exit}')"
[ -n "${CRONPID:-}" ] && kill -HUP "$CRONPID" 2>/dev/null || /etc/init.d/crond.sh restart >/dev/null 2>&1 || true

echo "[+] Ensuring /etc/rc.local fallback exists"
if [ ! -f "$RCLOCAL" ]; then
  cat > "$RCLOCAL" <<'EORC'
#!/bin/sh
# rc.local - executed at the end of multiuser boot
# Keep this file executable.
exit 0
EORC
  chmod +x "$RCLOCAL"
fi

# Add our block once
if ! grep -q 'BEGIN JF HDD SPINUP' "$RCLOCAL"; then
  cp "$RCLOCAL" "${RCLOCAL}.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
  sed -e '/^exit 0$/d' "$RCLOCAL" > "${RCLOCAL}.tmp"
  cat >> "${RCLOCAL}.tmp" <<'EOBLK'
# BEGIN JF HDD SPINUP
if [ -x /etc/config/jellyfin-hdd-spinup/spinup_ws_login.sh ]; then
  /etc/config/jellyfin-hdd-spinup/spinup_ws_login.sh >/dev/null 2>&1 &
fi
# END JF HDD SPINUP
exit 0
EOBLK
  mv "${RCLOCAL}.tmp" "$RCLOCAL"
  chmod +x "$RCLOCAL"
fi

echo "[✓] Install complete. Verify with: ps | grep '[s]pinup_ws_login.sh'"
