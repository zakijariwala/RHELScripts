#!/bin/bash
#== S01 settings
VERSION=1.0.0
NAME="crs-check"
ABOUT="Clusterware resources whose TARGET is ONLINE but STATE is not"
CHECKS="every resource in crsctl stat res -t: TARGET against STATE"
KEYS="GRID_HOME CRS_TIMEOUT"
GRID_HOME='' CRS_TIMEOUT=60
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
#== S06 parse
not_online() {
  awk '/^-+$/ || /^Name / || /^Local Resources/ || /^Cluster Resources/ {
      next }
    /^[^ \t]/ { res = $1; next }
    { t = ""; s = ""; rest = ""
      for (i = 1; i <= NF; i++)
        if ($i ~ /^(ONLINE|OFFLINE|INTERMEDIATE|UNKNOWN)$/ && s == "") {
          if (t == "") t = $i
          else { s = $i; for (j = i + 1; j <= NF; j++) rest = rest " " $j }
        }
      if (t == "ONLINE" && s != "" && s != "ONLINE") print res, s, rest }'
}
#== S07 crs
check_crs() {
  local crsctl=$GRID_HOME/bin/crsctl out rc res state rest bad=0
  if [ ! -x "$crsctl" ]; then
    add CLUSTERWARE crsctl "not found at $crsctl, set GRID_HOME" WARN
    return
  fi
  out=$(timeout "$CRS_TIMEOUT" "$crsctl" stat res -t 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ]; then
    add CLUSTERWARE "crsctl stat res -t" "failed, rc=$rc" CRIT
    return
  fi
  while read -r res state rest; do
    [ -n "$res" ] || continue
    bad=1
    if [ "$state" = OFFLINE ]; then st=CRIT; else st=WARN; fi
    add CLUSTERWARE "$res" "target ONLINE, state $state $rest" "$st"
  done < <(not_online <<< "$out")
  [ "$bad" = 1 ] || add CLUSTERWARE "Resources with TARGET=ONLINE" \
    "all ONLINE" OK
}
#== S08 main
cfg
olr=$(awk -F= '/^crs_home=/ { print $2 }' /etc/oracle/olr.loc 2>/dev/null)
detect GRID_HOME "$olr"
need GRID_HOME
if [ "$MODE" = check ]; then
  show_cfg
  if [ -x "$GRID_HOME/bin/crsctl" ]; then
    add TEST crsctl "found in $GRID_HOME/bin" OK
  else
    add TEST crsctl "not found in $GRID_HOME/bin" CRIT
  fi
  report
fi
check_crs
report
