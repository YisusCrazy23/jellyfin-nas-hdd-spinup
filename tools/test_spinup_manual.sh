#!/bin/sh
# Manually spin up disks using SCSI START UNIT on members of the largest data md
PATH=/bin:/sbin:/usr/bin:/usr/sbin

SG=""
for c in /usr/sbin/sg_start /sbin/sg_start /usr/bin/sg_start /bin/sg_start; do
  if [ -x "$c" ]; then SG="$c"; break; fi
done
if [ -z "$SG" ]; then
  echo "sg_start not found; please install sg3_utils"
  exit 1
fi

pick_data_md() {
  awk '
    /^md[0-9]+ :/ {m=$1; next}
    /blocks/ && m!="" {print m,$1; m=""}
  ' /proc/mdstat 2>/dev/null | grep -Ev '^(md9|md13|md321) ' | sort -k2,2n | tail -1 | awk '{print $1}'
}

md_bases() {
  MD="$1"
  [ -z "$MD" ] && return 0
  line=$(awk -v M="$MD" '$1==M{print;exit}' /proc/mdstat 2>/dev/null)
  [ -z "$line" ] && return 0
  for part in $(echo "$line" | grep -Eo '([shv]d[a-z]+[0-9]+)'); do
    base=$(echo "$part" | sed 's/[0-9]\+$//')
    echo "/dev/$base"
  done | sort -u
}

MD=$(pick_data_md)
[ -n "$MD" ] || { echo "No data md found"; exit 1; }

for d in $(md_bases "$MD"); do
  [ -b "$d" ] || continue
  "$SG" --start "$d" >/dev/null 2>&1 || true
done

echo "Spin-up commands sent."
