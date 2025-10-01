#!/bin/sh
# Manual wake using sg_start on member disks (no reads).

PATH=/bin:/sbin:/usr/bin:/usr/sbin

uptime_secs() { awk '{printf "%d", $1}' /proc/uptime 2>/dev/null; }

pick_data_md() {
  awk '
    /^md[0-9]+ :/ {md=$1; next}
    /blocks/ && md!=""{print md,$1; md=""}
  ' /proc/mdstat 2>/dev/null \
  | grep -Ev '^(md9|md13|md321) ' \
  | sort -k2,2n \
  | tail -1 \
  | awk '{print $1}'
}

md_bases() {
  MD="$1"
  [ -z "$MD" ] && return 0
  line="$(awk -v M="$MD" '$1==M{print;exit}' /proc/mdstat 2>/dev/null)"
  [ -z "$line" ] && return 0
  BASES=""
  for part in $(echo "$line" | grep -Eo '([shv]d[a-z]+[0-9]+)'); do
    b="/dev/$(echo "$part" | sed 's/[0-9]\+$//')"
    echo "$BASES" | grep -qw "$b" || BASES="$BASES $b"
  done
  echo "$BASES"
}

BOOT_WAIT="${BOOT_WAIT:-420}"
up="$(uptime_secs)"
if [ -n "$up" ] && [ "$up" -lt "$BOOT_WAIT" ]; then
  echo "[i] Uptime ${up}s < BOOT_WAIT ${BOOT_WAIT}s — delaying manual wake."
  exit 0
fi

MD="$(pick_data_md)"
if ! command -v sg_start >/dev/null 2>&1; then
  echo "[!] sg_start not found. Install sg3_utils or use the watcher once available."
  exit 1
fi

for d in $(md_bases "$MD"); do
  echo "[i] Sending sg_start --start to $d"
  sg_start --start "$d" >/dev/null 2>&1 || true
done
