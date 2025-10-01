#!/bin/sh
# Manual spin-up using SCSI START UNIT (no reads)
PATH=/bin:/sbin:/usr/bin:/usr/sbin

command -v sg_start >/dev/null 2>&1 || {
  echo "sg_start not found. Install sg3_utils or ensure sg_start is available on your QNAP."
  exit 1
}

# Determine largest data md (exclude system md arrays)
MD="$(awk '/^md[0-9]+ :/{m=$1;next} /blocks/&&m!=""{print m,$1;m=""}' /proc/mdstat \
     | grep -Ev '^(md9|md13|md321) ' | sort -k2,2n | tail -1 | awk "{print \$1}")"

if [ -z "$MD" ] || [ ! -b "/dev/$MD" ]; then
  echo "No suitable data md device found."
  exit 1
fi

line="$(awk -v M="$MD" '$1==M{print;exit}' /proc/mdstat)"
BASES=""
for part in $(echo "$line" | grep -Eo '([shv]d[a-z]+[0-9]+)'); do
  b="/dev/$(echo "$part" | sed 's/[0-9]\+$//')"
  echo "$BASES" | grep -qw "$b" || BASES="$BASES $b"
done

[ -z "$BASES" ] && { echo "No member base disks found for /dev/$MD"; exit 1; }

echo "Sending START UNIT to:"
for d in $BASES; do
  echo "  $d"
  sg_start --start "$d" >/dev/null 2>&1 || true
done
echo "Done."
