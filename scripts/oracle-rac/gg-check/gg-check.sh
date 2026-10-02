#!/bin/bash
#== S01 settings
VERSION=1.0.0
NAME="gg-check"
ABOUT="GoldenGate extracts via gg2.sh on the GoldenGate host, over ssh"
CHECKS="per extract: status, lag, checkpoint age"
KEYS="GG_HOST SSH_PORT SSH_TIMEOUT GG_SCRIPT GG_LAG_WARN GG_LAG_CRIT"
KEYS="$KEYS GG_CKPT_WARN_MIN GG_CKPT_CRIT_MIN"
GG_HOST='' SSH_PORT=22 SSH_TIMEOUT=60 GG_SCRIPT=/home/oracle/scripts/gg2.sh
GG_LAG_WARN=60 GG_LAG_CRIT=300 GG_CKPT_WARN_MIN=5 GG_CKPT_CRIT_MIN=15
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
#== S06 extract
extract_row() {
  local name status started lag ckpt scn secs='' age='' st=OK r
  IFS=',' read -r name status started lag ckpt scn <<< "${1//\"/}"
  if [ -z "$status" ] || [ -z "$lag" ]; then
    add GOLDENGATE "unparsed line" "$1" WARN
    return
  fi
  if [[ $lag =~ ^([0-9]+):([0-9][0-9]):([0-9][0-9])$ ]]; then
    secs=$((10#${BASH_REMATCH[1]} * 3600 + 10#${BASH_REMATCH[2]} * 60))
    secs=$((secs + 10#${BASH_REMATCH[3]}))
  fi
  ckpt=$(date -d "$ckpt" +%s 2>/dev/null) &&
    age=$((($(date +%s) - ckpt) / 60))
  [ "$status" = RUNNING ] || st=CRIT
  for r in "$(rate "$secs" "$GG_LAG_WARN" "$GG_LAG_CRIT")" \
    "$(rate "$age" "$GG_CKPT_WARN_MIN" "$GG_CKPT_CRIT_MIN")"; do
    [ "$(rank "$r")" -gt "$(rank "$st")" ] && st=$r
  done
  r="$status, lag $lag, checkpoint ${age:-?}m ago"
  add GOLDENGATE "$name" "$r, started $started, SCN $scn" "$st"
}
#== S07 gg
check_gg() {
  local out rc line found=0
  out=$(timeout "$SSH_TIMEOUT" ssh "${ssh_opts[@]}" "$GG_HOST" \
    "sh $GG_SCRIPT" < /dev/null 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ] || [ -z "$out" ]; then
    add GOLDENGATE "$GG_HOST" "no output, unreachable or failed, rc=$rc" CRIT
    return
  fi
  while IFS= read -r line; do
    line=$(echo "$line" | tr -d '\r' | sed 's/^ *//; s/ *$//')
    case $line in ''|Extract_Name*) continue ;; esac
    found=1
    extract_row "$line"
  done <<< "$out"
  [ "$found" = 1 ] || add GOLDENGATE Extracts "no extract rows in output" CRIT
}
#== S08 main
cfg
need GG_HOST
ssh_opts=(-q -o BatchMode=yes -o ConnectTimeout=10 -p "$SSH_PORT")
if [ "$MODE" = check ]; then
  show_cfg
  if timeout "$SSH_TIMEOUT" ssh "${ssh_opts[@]}" "$GG_HOST" \
    test -r "$GG_SCRIPT" < /dev/null; then
    add TEST "ssh $GG_HOST" "login works, $GG_SCRIPT readable" OK
  else
    add TEST "ssh $GG_HOST" "login failed or $GG_SCRIPT not readable" CRIT
  fi
  report
fi
check_gg
report
