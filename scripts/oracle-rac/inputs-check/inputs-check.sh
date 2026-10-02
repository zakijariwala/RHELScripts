#!/bin/bash
#== S01 settings
VERSION=1.0.0
NAME="inputs-check"
ABOUT="sftp log size, active session peaks, app servers, from other jobs"
CHECKS="sftp_output, activesession.sh, server_checklist, file freshness"
KEYS="SFTP_FILE SERVER_FILE ACTIVESESSION_SCRIPT ACTIVESESSION_TIMEOUT"
KEYS="$KEYS STALE_MIN SFTP_LOG_WARN_MB"
SFTP_FILE=/home/oracle/sftp_output SERVER_FILE=/home/oracle/server_checklist
ACTIVESESSION_SCRIPT=/home/oracle/scripts/activesession.sh
ACTIVESESSION_TIMEOUT=120 STALE_MIN=60 SFTP_LOG_WARN_MB=1024
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
#== S06 tools
trim() { sed 's/^[[:space:]]*//; s/[[:space:]]*$//' <<< "$1"; }
fresh() {
  local age
  if [ ! -r "$2" ]; then add "$1" "$2" "file missing" CRIT; return 1; fi
  age=$((($(date +%s) - $(stat -c %Y "$2")) / 60))
  [ "$age" -le "$STALE_MIN" ] && return 0
  add "$1" "$2" "STALE: last updated ${age}m ago, producer job stopped?" CRIT
  return 1
}
#== S07 sftp
check_sftp() {
  local line path mod size status st mb
  fresh "SFTP LOG" "$SFTP_FILE" || return
  while IFS= read -r line; do
    line=$(trim "${line//$'\r'/}")
    case $line in ''|PATH*) continue ;; esac
    IFS=',' read -r path mod size status <<< "$line"
    size=$(trim "$size")
    if [ -z "$size" ]; then
      add "SFTP LOG" "unparsed line" "$line" WARN; continue
    fi
    mb=$(awk -v s="$size" 'BEGIN { n = s + 0; u = toupper(substr(s, length(s)))
      if (u == "G") n *= 1024; if (u == "K") n /= 1024
      if (u == "T") n *= 1048576; printf "%d", n }')
    st=$(rate "$mb" "$SFTP_LOG_WARN_MB" 999999999)
    [ "$(trim "$status")" = Normal ] || st=WARN
    line="size $size, modified $(trim "$mod")"
    add "SFTP LOG" "$(trim "$path")" "$line, producer says: $(trim "$status")" \
      "$st"
  done < "$SFTP_FILE"
}
#== S08 sessions
check_active() {
  local out rc line win hi s1 lo s2 st found=0
  out=$(timeout "$ACTIVESESSION_TIMEOUT" sh "$ACTIVESESSION_SCRIPT" 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ]; then
    add "ACTIVE SESSIONS" activesession.sh "failed or timed out, rc=$rc" CRIT
    return
  fi
  while IFS= read -r line; do
    line=$(trim "${line//$'\r'/}")
    case $line in ''|Date*) continue ;; esac
    IFS=',' read -r _ win hi s1 lo s2 <<< "$line"
    s1=$(trim "$s1"); s2=$(trim "$s2")
    if [ -z "$s1" ]; then
      add "ACTIVE SESSIONS" "unparsed line" "$line" WARN; continue
    fi
    found=1
    st=OK
    [ "${s1^^}" = NORMAL ] || st=WARN
    [ -z "$s2" ] || [ "${s2^^}" = NORMAL ] || st=WARN
    line="highest $(trim "$hi") [$s1], lowest $(trim "$lo") [${s2:-?}]"
    add "ACTIVE SESSIONS" "Last 2h ($(trim "$win"))" "$line" "$st"
  done <<< "$out"
  [ "$found" = 1 ] ||
    add "ACTIVE SESSIONS" activesession.sh "no data rows" WARN
}
#== S09 servers
check_servers() {
  local line total acc inacc st found=0
  fresh "APP SERVERS" "$SERVER_FILE" || return
  while IFS= read -r line; do
    line=$(trim "${line//$'\r'/}")
    case $line in ''|Total*) continue ;; esac
    IFS=',' read -r total acc inacc _ <<< "$line"
    total=$(trim "$total"); acc=$(trim "$acc"); inacc=$(trim "$inacc")
    if ! [[ $total =~ ^[0-9]+$ && $acc =~ ^[0-9]+$ ]]; then
      add "APP SERVERS" "unparsed line" "$line" WARN; continue
    fi
    found=1
    st=OK
    { [ "$acc" -lt "$total" ] || [ "${inacc:-0}" != 0 ]; } && st=CRIT
    line="$acc of $total, inaccessible ${inacc:-?}"
    add "APP SERVERS" Accessible "$line" "$st"
  done < "$SERVER_FILE"
  [ "$found" = 1 ] || add "APP SERVERS" "$SERVER_FILE" "no data rows" WARN
}
#== S10 main
cfg
if [ "$MODE" = check ]; then
  show_cfg
  for f in "$SFTP_FILE" "$SERVER_FILE" "$ACTIVESESSION_SCRIPT"; do
    if [ -r "$f" ]; then add TEST "$f" "readable" OK
    else add TEST "$f" "missing or not readable" CRIT
    fi
  done
  report
fi
check_sftp
check_active
check_servers
report
