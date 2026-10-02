#!/bin/bash
#== S01 settings
VERSION=1.0.0
NAME="proc-check"
ABOUT="database, ASM, listener and Clusterware processes on every node"
CHECKS="per node: instance pmon, ASM pmon, local listener, CRS daemons"
KEYS="NODES GRID_HOME SSH_PORT SSH_TIMEOUT LISTENERS CRS_DAEMONS CHECK_ASM"
NODES='' GRID_HOME='' SSH_PORT=22 SSH_TIMEOUT=60 LISTENERS=LISTENER
CRS_DAEMONS=ohasd.bin,ocssd.bin,crsd.bin,evmd.bin,gpnpd.bin,gipcd.bin
CRS_DAEMONS=$CRS_DAEMONS,mdnsd.bin,octssd.bin,osysmond.bin CHECK_ASM=1
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
  ps -eo args= | awk '$1 ~ /^ora_pmon_/ { print "PMON|" substr($1, 10) }
    $1 ~ /^asm_pmon_/ { print "ASM|" substr($1, 10) }
    $1 ~ /\/tnslsnr$/ { print "LSNR|" $2 }'
  ps -eo comm= | awk -v want=",$1," 'index(want, "," $1 ",") { n[$1]++ }
    END { for (d in n) print "PROC|" d "|" n[d] }'
}
#== S07 rows
node_rows() {
  local node=$1 out=$2 v lsnr d miss=''
  v=$(awk -F'|' '$1 == "PMON" { print $2 }' <<< "$out" | paste -sd, -)
  if [ -n "$v" ]; then add "DB PROCESS" "$node pmon" "$v" OK
  else add "DB PROCESS" "$node pmon" "no ora_pmon process" CRIT
  fi
  if [ "$CHECK_ASM" = 1 ]; then
    v=$(awk -F'|' '$1 == "ASM" { print $2 }' <<< "$out" | paste -sd, -)
    if [ -n "$v" ]; then add "DB PROCESS" "$node asm" "$v" OK
    else add "DB PROCESS" "$node asm" "no asm_pmon process" CRIT
    fi
  fi
  lsnr=$(awk -F'|' '$1 == "LSNR" { print $2 }' <<< "$out")
  for v in ${LISTENERS//,/ }; do
    if grep -qx "$v" <<< "$lsnr"; then add LISTENER "$node $v" running OK
    else add LISTENER "$node $v" "not running" CRIT
    fi
  done
  v=$(awk -v want=",$LISTENERS," 'NF && !index(want, "," $0 ",")' \
    <<< "$lsnr" | paste -sd, -)
  [ -z "$v" ] || add LISTENER "$node others" "$v" INFO
  for d in ${CRS_DAEMONS//,/ }; do
    grep -q "^PROC|$d|" <<< "$out" || miss="$miss $d"
  done
  if [ -z "$miss" ]; then add "CRS PROCESS" "$node" "all running" OK
  else add "CRS PROCESS" "$node" "not running:$miss" CRIT
  fi
}
#== S08 main
cfg
olr=$(awk -F= '/^crs_home=/ { print $2 }' /etc/oracle/olr.loc 2>/dev/null)
detect GRID_HOME "$olr"
detect NODES "$("$GRID_HOME/bin/olsnodes" 2>/dev/null | paste -sd, -)"
need NODES
[ "$MODE" = check ] && show_cfg
here=$(hostname -s)
ssh_opts=(-q -o BatchMode=yes -o ConnectTimeout=10 -p "$SSH_PORT")
for node in ${NODES//,/ }; do
  if [ "${node%%.*}" = "$here" ]; then
    [ "$MODE" = check ] && { add TEST "$node" "this host" OK; continue; }
    out=$(collect "$CRS_DAEMONS")
    rc=0
  elif [ "$MODE" = check ]; then
    if timeout "$SSH_TIMEOUT" ssh "${ssh_opts[@]}" "$node" true < /dev/null
    then add TEST "ssh $node" "login works" OK
    else add TEST "ssh $node" "login failed" CRIT
    fi
    continue
  else
    out=$(timeout "$SSH_TIMEOUT" ssh "${ssh_opts[@]}" "$node" bash -s \
      <<< "$(declare -f collect); collect $CRS_DAEMONS" 2>/dev/null)
    rc=$?
  fi
  if [ "$rc" -ne 0 ] || [ -z "$out" ]; then
    add "DB PROCESS" "$node" "NO DATA, unreachable or failed, rc=$rc" CRIT
    continue
  fi
  node_rows "$node" "$out"
done
report
