#!/bin/bash
#== S01 settings
VERSION=1.0.0
NAME="disk-check"
ABOUT="disk and inode use, read-only filesystems, SCSI and multipath paths"
CHECKS="space and inodes per mount, read-only filesystems, SCSI, multipath"
KEYS="FS_WARN FS_CRIT INODE_WARN INODE_CRIT MPATH_MIN PROC_DIR SYS_DIR"
FS_WARN=80 FS_CRIT=90 INODE_WARN=80 INODE_CRIT=90 MPATH_MIN=2
PROC_DIR=/proc SYS_DIR=/sys
#== S02 helpers
set -o pipefail
R=()
die() { echo "$NAME: $2" >&2; exit "$1"; }
add() { R+=("$1|$2|${3//|//}|$4"); }
rank() { case $1 in CRIT) echo 2 ;; WARN) echo 1 ;; *) echo 0 ;; esac; }
rate() {
  awk -v v="$1" -v w="$2" -v c="$3" 'BEGIN {
    if (v !~ /^[0-9]+([.][0-9]+)?$/) print "WARN"
    else if (v + 0 > c + 0) print "CRIT"
    else if (v + 0 > w + 0) print "WARN"
    else print "OK" }'
}
#== S03 output
report() {
  local c w o all=OK
  c=$(printf '%s\n' "${R[@]}" | grep -c '|CRIT$')
  w=$(printf '%s\n' "${R[@]}" | grep -c '|WARN$')
  o=$(printf '%s\n' "${R[@]}" | grep -c '|OK$')
  [ "$w" -gt 0 ] && all=WARN
  [ "$c" -gt 0 ] && all=CRIT
  add SUMMARY "$(hostname -s) $NAME $VERSION $(date '+%F %T')" \
    "CRIT=$c WARN=$w OK=$o" "$all"
  printf '%s\n' "SECTION|KEY|VALUE|STATUS" "${R[@]}" | if [ "$MODE" = csv ]
  then tr -d '"' | sed 's/|/","/g; s/.*/"&"/'
  else column -t -s '|'
  fi
  exit "$(rank "$all")"
}
#== S04 config
declare -A SRC
cfg() {
  local f k v
  f=$(dirname "$0")/config.env
  [ -f "$f" ] || return 0
  while IFS='=' read -r k v; do
    [ -n "$k" ] || continue
    [[ " $KEYS " == *" $k "* ]] || die 65 "config.env: bad key $k"
    [[ $v =~ ^[A-Za-z0-9_./:,@+-]*$ ]] || die 65 "config.env: bad value $k"
    if [[ $k =~ ^CHECK_|(WARN|CRIT|MAX|SECS|MIN|HRS|DAYS|TIMEOUT|MB|PORT)$ ]]
    then
      [[ $v =~ ^[0-9]+([.][0-9]+)?$ ]] || die 65 "config.env: $k not a number"
    fi
    printf -v "$k" '%s' "$v"
    SRC[$k]=config
  done < <(tr -d '\r' < "$f"; echo)
}
detect() {
  [ -n "$2" ] || return 0
  if [ -z "${!1}" ]; then printf -v "$1" '%s' "$2"; SRC[$1]=detected
  elif [ "${!1}" != "$2" ]; then SRC[$1]="MISMATCH, detected $2"; fi
}
need() { [ -n "${!1}" ] || die 65 "$1 missing: docs/config-from-inventory.md"; }
#== S05 options
MODE=run
case ${1:-} in
  '') ;;
  --csv) MODE=csv ;;
  --check-config) MODE=check ;;
  --version) echo "$NAME $VERSION"; exit 0 ;;
  --help) echo "$NAME: $ABOUT"
    echo "usage: bash $NAME.sh [--csv | --check-config | --version | --help]"
    exit 0 ;;
  *) die 64 "unknown option: $1 (try --help)" ;;
esac
[ $# -le 1 ] || die 64 "one option at most (try --help)"
show_cfg() {
  local k st
  for k in $KEYS; do
    st=INFO; [[ ${SRC[$k]} == MISMATCH* ]] && st=WARN
    add CONFIG "$k" "${!k:-(empty)} [${SRC[$k]:-default}]" "$st"
  done
  add CONFIG "checks" "$CHECKS" INFO
}
#== S06 filesystems
usage() {
  local mnt pct st n=0 top=0 at=''
  while read -r mnt pct; do
    n=$((n + 1))
    [ "$pct" -gt "$top" ] && top=$pct && at=$mnt
    st=$(rate "$pct" "$2" "$3")
    [ "$st" = OK ] || add "$1" "$mnt" "Used=$pct%" "$st"
  done < <(df -P "${@:4}" -l -x tmpfs -x devtmpfs -x squashfs -x iso9660 \
    2>/dev/null | awk 'NR > 1 && $5 ~ /^[0-9]+%$/ {
      sub(/%/, "", $5); print $6, $5 }')
  if [ "$n" -eq 0 ]; then add "$1" local "no filesystems read" WARN
  else add "$1" local "$n checked, highest $top% on $at" \
    "$(rate "$top" "$2" "$3")"
  fi
}
check_fs() {
  local mnt ro=0
  usage FILESYSTEM "$FS_WARN" "$FS_CRIT"
  usage INODES "$INODE_WARN" "$INODE_CRIT" -i
  if [ ! -r "$PROC_DIR/mounts" ]; then
    add "READ-ONLY FS" local "$PROC_DIR/mounts not readable" WARN
    return
  fi
  while read -r mnt; do
    add "READ-ONLY FS" "$mnt" "mounted read-only" CRIT
    ro=1
  done < <(awk '$3 ~ /^(xfs|ext[234]|btrfs)$/ && $4 ~ /(^|,)ro(,|$)/ {
    print $2 }' "$PROC_DIR/mounts")
  [ "$ro" = 1 ] || add "READ-ONLY FS" local "none read-only" OK
}
#== S07 paths
state_of() { cat "$SYS_DIR/block/$1/device/state" 2>/dev/null || echo unknown; }
check_paths() {
  local dev st n=0 bad=0
  for dev in "$SYS_DIR"/block/sd*; do
    [ -e "$dev/device/state" ] || continue
    n=$((n + 1))
    st=$(state_of "${dev##*/}")
    [ "$st" = running ] && continue
    add "SCSI PATH" "${dev##*/}" "state $st" WARN
    bad=1
  done
  if [ "$n" -eq 0 ]; then add "SCSI PATH" all "no SCSI disks" INFO
  elif [ "$bad" = 0 ]; then add "SCSI PATH" all "$n paths running" OK
  fi
}
#== S08 multipath
check_mpath() {
  local dm s name tot up st n=0
  for dm in "$SYS_DIR"/block/dm-*; do
    [[ $(cat "$dm/dm/uuid" 2>/dev/null) == mpath-* ]] || continue
    n=$((n + 1))
    name=$(cat "$dm/dm/name")
    tot=0 up=0
    for s in "$dm"/slaves/*; do
      [ -e "$s" ] || continue
      tot=$((tot + 1))
      [ "$(state_of "${s##*/}")" = running ] && up=$((up + 1))
    done
    st=OK
    [ "$up" -lt "$MPATH_MIN" ] && st=WARN
    [ "$up" -eq 0 ] && st=CRIT
    add MULTIPATH "$name" "$up of $tot paths running" "$st"
  done
  [ "$n" -gt 0 ] || add MULTIPATH all "no multipath devices" INFO
}
#== S09 main
cfg
if [ "$MODE" = check ]; then
  show_cfg
  for f in "$PROC_DIR/mounts" "$SYS_DIR/block"; do
    if [ -r "$f" ]; then add TEST "$f" readable OK
    else add TEST "$f" "not readable" CRIT
    fi
  done
  report
fi
check_fs
check_paths
check_mpath
report
