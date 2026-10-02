#!/bin/bash
#== S01 settings
VERSION=1.0.0
NAME="host-check"
ABOUT="reboot pending, time sync, processes, systemd units, kdump, kernel log"
CHECKS="kernel, reboot, chrony, processes, failed units, kdump, kernel log"
KEYS="PROCS TIME_WARN_MS TIME_CRIT_MS CHECK_KDUMP KLOG_HRS"
PROCS=crond,chronyd,sshd TIME_WARN_MS=100 TIME_CRIT_MS=1000
CHECK_KDUMP=1 KLOG_HRS=24
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
#== S06 kernel
check_kernel() {
  local run new
  run=$(uname -r)
  new=$(rpm -q --last kernel-core 2>/dev/null | awk 'NR == 1 {
    sub(/^kernel-core-/, "", $1); print $1 }')
  if [ -z "$new" ]; then
    add KERNEL running "$run, installed kernels not readable" WARN
  elif [ "$run" = "$new" ]; then
    add KERNEL running "$run, the newest installed" OK
  else
    add KERNEL running "$run, newest installed $new: reboot pending" WARN
  fi
  if ! command -v needs-restarting > /dev/null; then
    add KERNEL needs-restarting "not installed (dnf-utils)" WARN
  elif timeout 60 needs-restarting -r > /dev/null 2>&1; then
    add KERNEL needs-restarting "no reboot needed" OK
  else
    add KERNEL needs-restarting "reboot needed, core packages updated" WARN
  fi
}
#== S07 time
check_time() {
  local out rc leap off src st
  out=$(timeout 10 chronyc tracking 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ]; then
    add "TIME SYNC" chrony "chronyc failed, rc=$rc: ${out%%$'\n'*}" CRIT
    return
  fi
  leap=$(awk -F': ' '/^Leap status/ { print $2 }' <<< "$out")
  src=$(awk -F': ' '/^Reference ID/ { print $2 }' <<< "$out")
  off=$(awk '/^System time/ { printf "%.2f", $4 * 1000 }' <<< "$out")
  if [ "$leap" != Normal ]; then
    add "TIME SYNC" chrony "not synchronised, leap status ${leap:-?}" CRIT
    return
  fi
  st=$(rate "$off" "$TIME_WARN_MS" "$TIME_CRIT_MS")
  add "TIME SYNC" chrony "offset ${off:-?} ms, source $src" "$st"
}
#== S08 procs
check_procs() {
  local p n
  for p in ${PROCS//,/ }; do
    n=$(pgrep -xc "$p")
    if [ "${n:-0}" -gt 0 ]; then add PROCESS "$p" "$n running" OK
    else add PROCESS "$p" "not running" CRIT
    fi
  done
}
#== S09 systemd
check_units() {
  local out rc units
  out=$(timeout 30 systemctl list-units --state=failed --no-legend --plain \
    2>&1)
  rc=$?
  if [ "$rc" -ne 0 ]; then
    add SYSTEMD "failed units" "systemctl failed, rc=$rc" CRIT
    return
  fi
  units=$(awk 'NF { print $1 }' <<< "$out" | paste -sd, -)
  if [ -n "$units" ]; then add SYSTEMD "failed units" "$units" WARN
  else add SYSTEMD "failed units" "none" OK
  fi
  [ "$CHECK_KDUMP" = 1 ] || return 0
  units=$(systemctl is-active kdump 2>/dev/null)
  if [ "$units" = active ]; then add SYSTEMD kdump active OK
  else add SYSTEMD kdump "${units:-unknown}, no crash dump on a panic" WARN
  fi
}
#== S10 klog
check_klog() {
  local out rc n
  if [ "$(id -u)" != 0 ] && ! id -Gn | grep -qwE 'adm|systemd-journal'
  then
    add "KERNEL LOG" errors "not readable: user not in systemd-journal" WARN
    return
  fi
  out=$(timeout 30 journalctl -k -p err -q --no-pager -o cat \
    --since "-${KLOG_HRS}h" 2>&1)
  rc=$?
  n=$(grep -c . <<< "$out")
  if [ "$rc" -ne 0 ]; then
    add "KERNEL LOG" errors "journalctl failed, rc=$rc" WARN
  elif [ "$n" -gt 0 ]; then
    add "KERNEL LOG" errors "$n in ${KLOG_HRS}h, latest: ${out##*$'\n'}" WARN
  else
    add "KERNEL LOG" errors "0 in ${KLOG_HRS}h" OK
  fi
}
#== S11 main
cfg
if [ "$MODE" = check ]; then
  show_cfg
  for c in uname rpm chronyc pgrep systemctl journalctl; do
    if command -v "$c" > /dev/null; then add TEST "$c" found OK
    else add TEST "$c" "not found" CRIT
    fi
  done
  report
fi
check_kernel
check_time
check_procs
check_units
check_klog
report
