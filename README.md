
# Jellyfin NAS HDD Spin‑Up at Homepage

Spin up your **NAS hard drives** automatically **right after a remote client reaches Jellyfin’s home screen** so the first **Play** is fast.  
This tiny watcher tails Jellyfin logs for **`WebSocketManager: WS "IP" request`** and, for **public (WAN) IPs**, immediately issues a **read‑only** wake:
- reads a few **4 KiB** blocks from your data RAID device (e.g. `/dev/md3`) and
- if available, sends **SCSI START UNIT** via `sg_start --start /dev/sdX`

This **bypasses SSD/RAM cache** (which would otherwise satisfy file reads without spinning the disks) so the HDDs are already awake when you hit **Play**.

> **Not triggered on the login page** — it fires right after the WebSocket is established (typically on the **home** page).

> **LAN optional**

---

## What this is (and why)

- **Goal:** Avoid the multi‑second delay when you press Play and HDDs are still spun down.
- **Problem:** File‑level reads can be served by **QTS SSD cache** or RAM page cache, so disks stay asleep.
- **Solution:** Touch the **underlying md device** + optional **SCSI START** → real I/O reaches the drives → **spins them up**, **without any writes**.

**Zero writes** are performed to your data volume. The watcher is **single‑instance**, **quiet**, and enforces a **150‑second cooldown**.

---

## Supported / Tested

- **Tested: QNAP TR-004** and QNAP **HS‑264**, QTS 5.x, Jellyfin **.qpkg** (logs under `/share/CACHEDEV1_DATA/.qpkg/jellyfin/logs`), SSH as **admin** (PuTTY).
- **Should also work** on similar NAS models/firmware with the same log layout and md RAID devices.
- **Requirements:** BusyBox `/bin/sh`, `tail`, `dd`, `awk`, `grep`, `cron`. `sg_start` is **optional** (if present, we use it).

> Use the **real `admin`** account over SSH. A different user in the *administrators* group may lack permissions for cron or raw device access.

---

## How it works

1. The watcher tails Jellyfin’s `log_YYYYMMDD.log` and looks for **`WebSocketManager: WS "..." request`**.
2. On **WAN (public) IPs** only (by default), it wakes disks via:
   - **md read:** `dd if=/dev/mdX of=/dev/null bs=4K count=4` (read‑only), and
   - **SCSI START:** `sg_start --start /dev/sdX` on member devices when `sg_start` exists.
3. A **150 s cooldown** prevents repeated wakeups and keeps the NAS quiet.

---

## Files inside the ZIP

```
bin/spinup_ws_login.sh        # watcher (single-instance, silent, WAN filter, cooldown)
install.sh                    # idempotent installer (copies to /etc/config/jellyfin-hdd-spinup/, starts, cron guard)
uninstall.sh                  # clean removal (kills watcher, removes cron guard)
tools/test_detect.sh          # detect WAN WebSocket “request” lines (no spin-up)
tools/test_spinup_manual.sh   # manual wake: md read + optional sg_start
LICENSE                       # MIT
README.md                     # this file
```

## Quick install (QNAP, SSH as **admin**)

- [**Download jellyfin-nas-hdd-spinup.zip**](https://github.com/Damocles-fr/jellyfin-nas-hdd-spinup/releases)
- Look at 'Configuration' before running install.sh
- Upload the ZIP from  (e.g. to `/share/Public/`), then:
- Some QNAP tasks (cron edits, device access) require the **real admin user**, even if you are administrator too.

```sh
cd /share/Public
unzip jellyfin-HDD-spinup.zip
cd jellyfin-HDD-spinup
sh ./install.sh
```

Verify it’s running (expect **two lines** → parent + worker `tail -f`):

```sh
ps | grep '[s]pinup_ws_login.sh'
```

Let the disks spin down. Open Jellyfin from **WAN/4G** → a WebSocket **request** should pre‑wake the HDDs.

> The watcher is installed to: `/etc/config/jellyfin-hdd-spinup/spinup_ws_login.sh` (persistent) — **not** on your media volume.

---

## Configuration

Edit the header of `bin/spinup_ws_login.sh` **before** running `install.sh` (or re‑install after changes):

- `LOG_DIR` — Jellyfin logs (qpkg default):  
  `/share/CACHEDEV1_DATA/.qpkg/jellyfin/logs`
- `COOLDOWN` — seconds between wake actions (default **150**).
- `SLEEP` — main loop sleep in seconds (default **2**).
- `ALLOW_PRIVATE` — **0** = WAN‑only (default), **1** = also trigger for **private/LAN** IPs.
- `TRIGGER_PATTERN` — regex for matching lines (default: only **`WebSocketManager: WS ".*" request`**).  
  You can broaden it, e.g.:  
  `TRIGGER_PATTERN='WebSocketManager: WS ".*" (request|open)|Authenticated|User logged in'`
- `FORCE_MD` — override auto md detection, e.g. `FORCE_MD="md3"`.

Keep the **cooldown** if you broaden triggers, to avoid unnecessary I/O.

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
Open Jellyfin from WAN and confirm you see lines like:
```
DETECTED WAN WebSocket 'request' from 203.0.113.5 @ Thu Sep 25 11:13:57 CEST 2025
```

### 2) Manual spin‑up (same actions as the watcher)

```sh
cd jellyfin-HDD-spinup
sh tools/test_spinup_manual.sh
```

This will read a tiny block from the biggest data md device and, if present, run `sg_start --start` on member disks.

---

## Safety & Scope

- **Read‑only I/O only** (a few KiB). No filesystem writes, no journal activity.
- The watcher lives under `/etc/config/jellyfin-hdd-spinup/` (system config), **not** on your media volume.
- **WAN‑only by default**; enable LAN with `ALLOW_PRIVATE=1` if desired.
- Single instance with lock; cron guard checks every 2 minutes (BusyBox‑friendly `ps | grep`).

---

## Troubleshooting

- **No triggers?** Check `LOG_DIR` and that `log_YYYYMMDD.log` updates when you open Jellyfin from WAN.  
  Use `sh tools/test_detect.sh` to confirm.
- **Still not waking?** Run `sh tools/test_spinup_manual.sh` — if that wakes the disks, the watcher will too.
- **Wrong md device picked?** Force it: set `FORCE_MD="md3"` inside `bin/spinup_ws_login.sh`, then re‑install.
- **Using a non‑admin SSH account?** Some QNAP tasks (cron edits, device access) require the **real `admin`** user.
- **Too chatty?** Keep `TRIGGER_PATTERN` on `request` and keep `COOLDOWN` at ≥ 150 seconds.

---

## Known pitfalls & mitigations

- File‑level reads may be served by SSD/RAM cache → **use md read + optional SCSI START**.
- Media volume might be remounted read‑only after a fault → we don’t write anything there.
- Some firmwares lack `pgrep` → cron guard uses portable `ps | grep`.

---

## GitHub

https://github.com/Damocles-fr

---

## License

**MIT** — see `LICENSE`.
