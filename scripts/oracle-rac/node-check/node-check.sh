#!/bin/bash
#== S01 settings
VERSION=1.0.0
NAME="node-check"
ABOUT="CPU, memory, swap, load, filesystems, alert log ORA- on every node"
CHECKS="per node: CPU, memory, swap, load, filesystems, alert log ORA- errors"
KEYS="NODES GRID_HOME SSH_PORT SSH_TIMEOUT SQL_TIMEOUT CPU_WARN CPU_CRIT"
KEYS="$KEYS MEM_WARN MEM_CRIT SWAP_WARN SWAP_CRIT LOAD_WARN LOAD_CRIT"
KEYS="$KEYS FS_WARN FS_CRIT CHECK_ALERTLOG ALERT_WINDOW_HRS"
NODES='' GRID_HOME='' SSH_PORT=22 SSH_TIMEOUT=150 SQL_TIMEOUT=120
CPU_WARN=60 CPU_CRIT=85 MEM_WARN=75 MEM_CRIT=90 SWAP_WARN=10 SWAP_CRIT=30
LOAD_WARN=1.0 LOAD_CRIT=2.0 FS_WARN=80 FS_CRIT=90
CHECK_ALERTLOG=1 ALERT_WINDOW_HRS=4
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
#== S06 collect
collect() {
  local pid sid oh cpu
  cpu=$(LC_ALL=C sar -u 1 3 2>/dev/null | awk '/^Average/ {
    printf "%.2f", 100 - $NF }')
  echo "CPU|$cpu"
  LC_ALL=C free -m | awk '/^Mem:/ { printf "MEM|%.2f\n", ($2 - $7) / $2 * 100 }
    /^Swap:/ { s = 0; if ($2 > 0) s = $3 / $2 * 100; printf "SWAP|%.2f\n", s }'
  awk -v c="$(nproc)" '{ printf "LOAD|%.2f\n", $1 / c }' /proc/loadavg
  df -P -l -x tmpfs -x devtmpfs -x squashfs -x iso9660 2>/dev/null |
    awk 'NR > 1 { sub(/%/, "", $5); print "FS|" $6 "|" $5 }'
  [ "$1" = 1 ] || return 0
  read -r pid sid < <(ps -eo pid=,args= | awk '$2 ~ /^ora_pmon_/ {
    print $1, substr($2, 10); exit }')
  [ -n "$sid" ] || { echo "ALERT|none"; return 0; }
  oh=$(tr '\0' '\n' 2>/dev/null < "/proc/$pid/environ" |
    awk -F= '$1 == "ORACLE_HOME" { print $2 }')
  { printf 'DEFINE hrs=%s\n' "$2"; cat <<'SQL'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 VERIFY OFF TAB OFF LINESIZE 1000
SELECT 'ALERT|' || COUNT(*) || '|' || SUBSTR(REPLACE(MAX(message_text)
  KEEP (DENSE_RANK LAST ORDER BY originating_timestamp), CHR(10), ' '),
  1, 120) FROM v$diag_alert_ext WHERE component_id = 'rdbms'
  AND originating_timestamp > SYSTIMESTAMP - INTERVAL '&hrs' HOUR
  AND message_text LIKE '%ORA-%';
EXIT
SQL
  } | ORACLE_SID=$sid ORACLE_HOME=${oh:-$ORACLE_HOME} PATH=$oh/bin:$PATH \
    timeout "$3" sqlplus -s -L / as sysdba 2>&1
}
#== S07 rate
flag() {
  local r
  r=$(rate "$2" "$3" "$4")
  [ "$r" = OK ] || why="$why $1"
  [ "$(rank "$r")" -gt "$(rank "$st")" ] && st=$r
}
#== S08 os
node_os() {
  local tag a b r val cpu='' mem='' swap='' lpc='' st=OK why=''
  local fs=0 top=-1 mnt=''
  while IFS='|' read -r tag a b; do
    case $tag in
      CPU) cpu=$a ;; MEM) mem=$a ;; SWAP) swap=$a ;; LOAD) lpc=$a ;;
      FS) [[ $b =~ ^[0-9]+$ ]] || continue
        fs=$((fs + 1))
        [ "$b" -gt "$top" ] && top=$b && mnt=$a
        r=$(rate "$b" "$FS_WARN" "$FS_CRIT")
        [ "$r" = OK ] || add FILESYSTEM "$1 $a" "Used=$b%" "$r" ;;
    esac
  done <<< "$2"
  flag CPU "$cpu" "$CPU_WARN" "$CPU_CRIT"
  flag Mem "$mem" "$MEM_WARN" "$MEM_CRIT"
  flag Swap "$swap" "$SWAP_WARN" "$SWAP_CRIT"
  flag Load "$lpc" "$LOAD_WARN" "$LOAD_CRIT"
  val="CPU: ${cpu:-?}% Mem: ${mem:-?}% Swap: ${swap:-?}% Load/core: ${lpc:-?}"
  add "OS UTILIZATION" "$1" "$val${why:+ (flagged:$why)}" "$st"
  if [ "$fs" -eq 0 ]; then add FILESYSTEM "$1" "no filesystems read" WARN
  else add FILESYSTEM "$1" "$fs checked, highest $top% on $mnt" \
    "$(rate "$top" "$FS_WARN" "$FS_CRIT")"
  fi
}
#== S09 alert
node_alert() {
  local line cnt msg
  [ "$CHECK_ALERTLOG" = 1 ] || return 0
  line=$(grep -m1 -E '^ALERT[|]|ORA-|SP2-' <<< "$2")
  IFS='|' read -r _ cnt msg <<< "$line"
  if [ "$cnt" = none ]; then
    add "ALERT LOG" "$1" "no ora_pmon process, alert log not read" WARN
  elif ! [[ $line == ALERT* && $cnt =~ ^[0-9]+$ ]]; then
    add "ALERT LOG" "$1" "query failed: ${line:-no output}" WARN
  elif [ "$cnt" -gt 0 ]; then
    add "ALERT LOG" "$1" "$cnt ORA- in ${ALERT_WINDOW_HRS}h, latest: $msg" WARN
  else
    add "ALERT LOG" "$1" "0 ORA- in ${ALERT_WINDOW_HRS}h" OK
  fi
}
#== S10 main
cfg
olr=$(awk -F= '/^crs_home=/ { print $2 }' /etc/oracle/olr.loc 2>/dev/null)
detect GRID_HOME "$olr"
detect NODES "$("$GRID_HOME/bin/olsnodes" 2>/dev/null | paste -sd, -)"
need NODES
[ "$MODE" = check ] && show_cfg
here=$(hostname -s)
ssh_opts=(-q -o BatchMode=yes -o ConnectTimeout=10 -p "$SSH_PORT")
args=("$CHECK_ALERTLOG" "$ALERT_WINDOW_HRS" "$SQL_TIMEOUT")
for node in ${NODES//,/ }; do
  if [ "${node%%.*}" = "$here" ]; then
    [ "$MODE" = check ] && { add TEST "$node" "this host" OK; continue; }
    out=$(collect "${args[@]}")
    rc=0
  elif [ "$MODE" = check ]; then
    if timeout "$SSH_TIMEOUT" ssh "${ssh_opts[@]}" "$node" true < /dev/null
    then add TEST "ssh $node" "login works" OK
    else add TEST "ssh $node" "login failed" CRIT
    fi
    continue
  else
    out=$(timeout "$SSH_TIMEOUT" ssh "${ssh_opts[@]}" "$node" bash -s \
      <<< "$(declare -f collect); collect ${args[*]}" 2>/dev/null)
    rc=$?
  fi
  if [ "$rc" -ne 0 ] || ! grep -q '^CPU[|]' <<< "$out"; then
    add "OS UTILIZATION" "$node" "NO DATA, unreachable or failed, rc=$rc" CRIT
    continue
  fi
  node_os "$node" "$out"
  node_alert "$node" "$out"
done
report
