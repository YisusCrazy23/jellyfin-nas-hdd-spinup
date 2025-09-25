
#!/bin/sh
# Manual wake: read small block from md + optional sg_start for member disks.

PATH=/bin:/sbin:/usr/bin:/usr/sbin
FORCE_MD=""  # set e.g. "md3" to override

pick_data_md(){
  [ -n "$FORCE_MD" ] && { echo "$FORCE_MD"; return; }
  awk '
    /^md[0-9]+ :/ {md=$1; next}
    /blocks/ && md!=""{print md,$1; md=""}
  ' /proc/mdstat 2>/dev/null \
  | grep -Ev '^(md9|md13|md321) ' \
  | sort -k2,2n \
  | tail -1 \
  | awk '{print $1}'
}

md_bases(){
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
  echo "[*] Reading 4 KiB from /dev/$MD ..."
  dd if="/dev/$MD" of=/dev/null bs=4K count=4 2>/dev/null || true
else
  echo "[!] Could not determine a data md device."
fi

if command -v sg_start >/dev/null 2>&1; then
  for d in $(md_bases "$MD"); do
    [ -b "$d" ] || continue
    echo "[*] Sending SCSI START to $d ..."
    sg_start --start "$d" >/dev/null 2>&1 || true
  done
else
  echo "[i] sg_start not found; skipping SCSI START step."
fi

echo "[✓] Manual spin-up sequence completed."
