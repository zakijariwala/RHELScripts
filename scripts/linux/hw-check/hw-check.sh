#!/bin/bash
#== S01 settings
VERSION=1.0.0
NAME="hw-check"
ABOUT="network bonding slaves, HugePages and transparent hugepages"
CHECKS="every bond and its slaves, HugePages, transparent hugepages"
KEYS="CHECK_HUGEPAGES PROC_DIR SYS_DIR"
CHECK_HUGEPAGES=1 PROC_DIR=/proc SYS_DIR=/sys
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
#== S06 bonding
check_bonds() {
  local b name up tot st slave mii n=0
  for b in "$PROC_DIR"/net/bonding/*; do
    [ -r "$b" ] || continue
    n=$((n + 1))
    name=${b##*/}
    up=0 tot=0
    while read -r slave mii; do
      if [ "$slave" = - ]; then st=$mii; continue; fi
      tot=$((tot + 1))
      if [ "$mii" = up ]; then up=$((up + 1))
      else add BONDING "$name $slave" "MII status $mii" CRIT
      fi
    done < <(awk -F': ' '/^Slave Interface/ { s = $2 }
      /^MII Status/ { print (s == "" ? "-" : s), $2; s = "" }' "$b")
    if [ "$st" != up ] || [ "$up" -eq 0 ]; then st=CRIT
    elif [ "$up" -lt "$tot" ]; then st=WARN
    else st=OK
    fi
    add BONDING "$name" "$up of $tot slaves up" "$st"
  done
  [ "$n" -gt 0 ] || add BONDING all "no bonded interfaces" INFO
}
#== S07 memory
check_huge() {
  local tot free rsvd size thp
  if [ "$CHECK_HUGEPAGES" != 1 ]; then
    add HUGEPAGES all "not checked, CHECK_HUGEPAGES=0" INFO
    return
  fi
  read -r tot free rsvd size < <(awk '/^HugePages_Total/ { t = $2 }
    /^HugePages_Free/ { f = $2 } /^HugePages_Rsvd/ { r = $2 }
    /^Hugepagesize/ { z = $2 } END { print t, f, r, z }' \
    "$PROC_DIR/meminfo" 2>/dev/null)
  if [ -z "$tot" ]; then
    add HUGEPAGES configured "$PROC_DIR/meminfo not readable" WARN
  elif [ "$tot" -eq 0 ]; then
    add HUGEPAGES configured "0, the SGA uses normal pages" WARN
  else
    add HUGEPAGES configured "$tot x ${size}kB, free $free, reserved $rsvd" OK
  fi
  thp=$(cat "$SYS_DIR/kernel/mm/transparent_hugepage/enabled" 2>/dev/null)
  case $thp in
    *'[never]'*) add HUGEPAGES transparent "never" OK ;;
    '') add HUGEPAGES transparent "setting not readable" WARN ;;
    *) add HUGEPAGES transparent "$thp, Oracle advises never" WARN ;;
  esac
}
#== S08 main
cfg
if [ "$MODE" = check ]; then
  show_cfg
  for f in "$PROC_DIR/meminfo" "$SYS_DIR/kernel/mm"; do
    if [ -r "$f" ]; then add TEST "$f" readable OK
    else add TEST "$f" "not readable" CRIT
    fi
  done
  report
fi
check_bonds
check_huge
report
