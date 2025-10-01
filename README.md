# jellyfin-HDD-spinup — spin up NAS disks on Jellyfin homepage (QNAP-friendly)

**Purpose:** Reduce the “Play” delay when your Jellyfin libraries live on disks that spin down.
This watcher detects the first **WebSocket “request”** from the Jellyfin server (which happens **right after** the login page, when the home UI appears) and **wakes the target array** so movies start faster.

**How it works (safe, read‑only, cache‑friendly):**
- Monitors the latest `log_YYYYMMDD.log` in your Jellyfin logs directory.
- On a WAN client connecting (by default it ignores LAN/private IPs), triggers **SCSI START UNIT** (`sg_start --start`) on the **member disks of your data RAID** (detected from `/proc/mdstat`).  
- **No filesystem writes**, **no block reads** — avoids SSD‑cache traps and reduces the risk of “aborted command / read‑only remounts.”
- Built‑in **cooldown** (default 150s) to prevent repeated wake‑ups.
- **Boot wait** (default 420s ≈ 7 minutes): the watcher self‑delays after NAS startup to let QNAP services settle.

> Tested on **QNAP HS‑264, QTS 5**, SSH with the **real `admin`** account. Other “administrator” users may fail to edit cron or manage services on QNAP — use `admin`.

---

## Why you might need this
Many NASes (and the TR‑004 enclosure) spin down drives to save power. On Jellyfin, the **first playback** after idle is slow because the disks are sleeping. SSD caching can even **mask small reads** causing no spin‑up at all. This project wakes disks **proactively** once the user hits the **Jellyfin home screen**, so playback is ready.

**Not triggered on the login page** — only after the UI loads (WebSocket “request”).

---

## Compatibility
- Designed for **QNAP + Jellyfin QPKG** (`/share/CACHEDEV1_DATA/.qpkg/jellyfin/logs`).
- Uses `/proc/mdstat` to discover the **largest data RAID** (excludes QNAP system md9/md13/md321) and then **SCSI START** on member disks.
- Requires `sg_start` (from `sg3_utils`) to be available on your QNAP firmware. Most QTS builds ship it; if not, install or copy `sg_start` accordingly.

> The watcher performs **no writes** and **no raw reads** on your data volume. It only issues **START UNIT** to the member disks. This is intentionally conservative to avoid the EXT4 read‑only remounts you may have seen with naive “dd” wake techniques.

---

## Quick start (admin over SSH)
Upload the ZIP somewhere on the NAS (e.g. `Public/`) then:

```sh
unzip jellyfin-HDD-spinup.zip -d /share/CACHEDEV1_DATA/Public/
cd /share/CACHEDEV1_DATA/Public/jellyfin-HDD-spinup
sh ./install.sh
```

Verify it’s running:
```sh
ps | grep '[s]pinup_ws_login.sh'
```

Optional tests:
```sh
# Live detection (no spin-up)
sh ./tools/test_detect.sh

# Manual spin-up (START UNIT on detected member disks)
sh ./tools/test_spinup_manual.sh
```

> The service **self-delays ~7 minutes after boot** (configurable) even if started by cron earlier. This avoids races during QNAP startup.

Uninstall:
```sh
cd /share/CACHEDEV1_DATA/Public/jellyfin-HDD-spinup
sh ./uninstall.sh
```

---

## Configuration knobs (edit `bin/spinup_ws_login.sh` header)
- `LOG_DIR` — Jellyfin logs folder. Default: `/share/CACHEDEV1_DATA/.qpkg/jellyfin/logs`
- `COOLDOWN` — seconds between spin-ups. Default: `150`
- `SLEEP` — main loop tick. Default: `2`
- `BOOT_WAIT` — **minimum uptime** (seconds) before doing anything. Default: `420` (7 minutes)
- `ALLOW_PRIVATE` — `0` = only WAN clients (default), `1` = also trigger for LAN/private IPs
- `TRIGGER_PATTERN` — grep‑E pattern for Jellyfin log lines. Default: `WebSocketManager: WS ".*" request`
- `FORCE_MD` — set to e.g. `md3` to force which md array to wake instead of auto‑detecting the largest data md

> Changes take effect next time the service starts (or kill and re‑start it).

---

## What exactly is excluded?
- **Login page** (no trigger). The first trigger happens when the home screen loads and the WebSocket connects (`request` line).
- **Private IPs** by default (10/127/192.168/172.16–31). Set `ALLOW_PRIVATE=1` to include LAN.
- QNAP system md arrays **md9/md13/md321** are excluded; we wake the **largest other md** instead.

---

## Why this is safer than early attempts
- We **removed all raw reads** (`dd if=/dev/mdX` and file reads) that can provoke “Aborted Command / I/O error / EXT4 read‑only remount” during spin transitions on some bridges/enclosures.
- We rely on **SCSI START UNIT** only, which is the correct way to request a spin‑up without touching data paths.
- We also **wait 7 minutes** after boot (`BOOT_WAIT=420`) so the NAS, RAID layers, and TR‑004 bridge are fully ready.

If you ever see the filesystem go read‑only again, do **not** run filesystem repairs immediately; first ensure the array and enclosure are healthy. This tool should no longer trigger such behavior.

---

## Files & layout
```
jellyfin-HDD-spinup/
├─ README.md
├─ LICENSE
├─ install.sh             # installs service to /etc/config/jellyfin-hdd-spinup + cron guard
├─ uninstall.sh           # removes service + cron guard
├─ bin/
│  └─ spinup_ws_login.sh  # the watcher (sg_start-only)
└─ tools/
   ├─ test_detect.sh      # tail WebSocket 'request' lines (WAN/LAN policy applies)
   └─ test_spinup_manual.sh # send START UNIT to member disks of the data md
```

---

## GitHub topic tags
`jellyfin` `qnap` `nas` `tr-004` `spinup` `spindown` `scsi` `sg3_utils` `websocket` `ext4` `raid` `mdraid` `qts5`

---

## License
MIT
