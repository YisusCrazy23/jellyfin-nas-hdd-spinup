# Jellyfin NAS HDD Spin‑Up at Homepage

Spin up your **NAS hard drives** automatically **right after a remote client reaches Jellyfin’s home screen** so the first **Play** is fast.  
This tiny watcher tails Jellyfin logs for **`WebSocketManager: WS "IP" request`** and, for **public (WAN) IPs**, immediately issues a **read‑only** wake:
- On a WAN client connecting (by default it ignores LAN/private IPs), triggers **SCSI START UNIT** (`sg_start --start`) on the **member disks of your data RAID** (detected from `/proc/mdstat`).  
- **No filesystem writes**, **no block reads** — avoids SSD‑cache traps and reduces the risk of “aborted command / read‑only remounts.”
- Built‑in **cooldown** (default 150s) to prevent repeated wake‑ups.
- **Boot wait** (default 420s ≈ 7 minutes): the watcher self‑delays after NAS startup to let QNAP services settle.

This **bypasses SSD/RAM cache** (which would otherwise satisfy file reads without spinning the disks) so the HDDs are already awake when you hit **Play**.

> **Not triggered on the login page** — it fires right after the WebSocket is established (typically on the **home** page).

> **LAN optional**

---

## Why you might need this
Many NASes (and the TR‑004 enclosure) spin down drives to save power. On Jellyfin, the **first playback** after idle is slow because the disks are sleeping. SSD caching can even **mask small reads** causing no spin‑up at all. This project wakes disks **proactively** once the user hits the **Jellyfin home screen**, so playback is ready.

---

## Supported / Tested

- **Tested: QNAP TR-004** and QNAP **HS‑264**, QTS 5.x, Jellyfin **.qpkg** (logs under `/share/CACHEDEV1_DATA/.qpkg/jellyfin/logs`), SSH as **admin** (PuTTY).
- **Should also work** on similar NAS models/firmware with the same log layout and md RAID devices.
- Uses `/proc/mdstat` to discover the **largest data RAID** (excludes QNAP system md9/md13/md321) and then **SCSI START** on member disks.
- Requires `sg_start` (from `sg3_utils`) to be available on your QNAP firmware. Most QTS builds ship it; if not, install or copy `sg_start` accordingly.

> The watcher performs **no writes** and **no raw reads** on your data volume. It only issues **START UNIT** to the member disks. This is intentionally conservative to avoid the EXT4 read‑only remounts you may have seen with naive “dd” wake techniques.

---

## Configuration

Edit the header of `bin/spinup_ws_login.sh` **before** running `install.sh` (or re‑install after changes):

- `LOG_DIR` — Jellyfin logs folder. Default: `/share/CACHEDEV1_DATA/.qpkg/jellyfin/logs`
- `COOLDOWN` — seconds between spin-ups. Default: `150`
- `SLEEP` — main loop tick. Default: `2`
- `BOOT_WAIT` — **minimum uptime** (seconds) before doing anything. Default: `420` (7 minutes)
- `ALLOW_PRIVATE` — `0` = only WAN clients (default), `1` = also trigger for LAN/private IPs
- `TRIGGER_PATTERN` — grep‑E pattern for Jellyfin log lines. Default: `WebSocketManager: WS ".*" request`
- `FORCE_MD` — set to e.g. `md3` to force which md array to wake instead of auto‑detecting the largest data md

Keep the **cooldown** if you broaden triggers to avoid unnecessary I/O.

> Changes take effect next time the service starts (or kill and re‑start it).

> The service **self-delays ~7 minutes after boot** (configurable) even if started by cron earlier. This avoids races during QNAP startup.

---

## Quick install (QNAP, SSH as **admin**)

Unzip (e.g. to `/share/Public/`), then:

> Use the **real `admin`** account over SSH. A different user in the *administrators* group may lack permissions for cron or raw device access.

```sh
cd /share/Public/jellyfin-HDD-spinup
sh ./install.sh
```

Verify it’s running (expect **two lines** → parent + worker `tail -f`):

```sh
ps | grep '[s]pinup_ws_login.sh'
```

Let disks spin down, then open Jellyfin from **WAN/4G** → the watcher should pre‑wake HDDs on the **home** screen.

> The watcher is installed to: `/etc/config/jellyfin-hdd-spinup/spinup_ws_login.sh` (persistent) — **not** on your media volume.

---

## Uninstall

```sh
cd /share/Public/jellyfin-HDD-spinup   # or wherever you unzipped it
sh ./uninstall.sh
```

Removes the watcher, cron guard, and `/etc/config/jellyfin-hdd-spinup/`.

---

## Verifying & Testing

### 1) Detect triggers (no spin‑up)
```sh
cd jellyfin-HDD-spinup
sh tools/test_detect.sh
```
Open Jellyfin from WAN and confirm output like:
```
DETECTED WAN WebSocket 'request' from 203.0.113.5 @ Thu Sep 25 11:13:57 CEST 2025
```

### 2) Manual spin‑up (same actions as the watcher)
```sh
cd jellyfin-HDD-spinup
sh tools/test_spinup_manual.sh
```
This reads a tiny block from the biggest data md device and, if present, runs `sg_start --start` on member disks.

---

## Files in this repo

```
bin/spinup_ws_login.sh        # watcher (single-instance, WAN filter, cooldown, BusyBox-friendly)
install.sh                    # idempotent installer (/etc/config/jellyfin-hdd-spinup/ + cron guard + rc.local hook)
uninstall.sh                  # clean removal (kills watcher, removes cron guard and rc.local hook)
tools/test_detect.sh          # detect WAN WebSocket “request” lines (no spin-up)
tools/test_spinup_manual.sh   # manual wake: md read + optional sg_start
LICENSE                       # MIT
README.md                     # this file
```

## Safety & Scope

- **Read‑only I/O** . No filesystem writes, no journal activity.
- Lives under `/etc/config/jellyfin-hdd-spinup/` (system config), **not** on your media volume.
- **WAN‑only** by default; enable LAN with `ALLOW_PRIVATE=1` if desired.
- Single instance with lock; cron guard is BusyBox‑compatible.

---

## GitHub

https://github.com/Damocles-fr

---

## License

**MIT** — see `LICENSE`.
