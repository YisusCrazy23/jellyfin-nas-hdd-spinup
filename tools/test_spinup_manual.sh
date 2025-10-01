#!/bin/sh
# Manual wake: tiny read on data md + optional sg_start on member disks.

PATH=/bin:/sbin:/usr/bin:/usr/sbin

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

MD="$(pick_data_md)"
if [ -b "/dev/$MD" ]; then
  echo "[i] Reading small block from /dev/$MD ..."
  dd if="/dev/$MD" of=/dev/null bs=4K count=4 2>/dev/null || true
else
  echo "[!] No suitable data md device found."
fi

if command -v sg_start >/dev/null 2>&1; then
  for d in $(md_bases "$MD"); do
    echo "[i] Sending sg_start --start to $d"
    sg_start --start "$d" >/dev/null 2>&1 || true
  done
else
  echo "[i] sg_start not found; skipping SCSI START."
fi
