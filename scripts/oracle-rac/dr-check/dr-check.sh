#!/bin/bash
#== S01 settings
VERSION=1.0.0
NAME="dr-check"
ABOUT="archive destinations and Data Guard gap and lag, run on the primary"
CHECKS="archive destinations, standby destination, gap and lag per thread"
KEYS="ORACLE_SID STANDBY_DEST GAP_WARN GAP_CRIT LAG_WARN_MIN LAG_CRIT_MIN"
KEYS="$KEYS SQL_TIMEOUT"
ORACLE_SID='' STANDBY_DEST='' GAP_WARN=10 GAP_CRIT=100 LAG_WARN_MIN=15
LAG_CRIT_MIN=60 SQL_TIMEOUT=300
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
#== S06 sql
find_sid() {
  local s
  s=$(ps -eo args= | awk '/^ora_pmon_/ { sub(/^ora_pmon_/, ""); print }')
  [[ $s == *$'\n'* ]] || detect ORACLE_SID "$s"
  need ORACLE_SID
  export ORACLE_SID
}
sql() {
  local out rc line n0=${#R[@]}
  out=$({ printf 'DEFINE %s\n' "$@"; cat; } |
    timeout "$SQL_TIMEOUT" sqlplus -s -L / as sysdba 2>&1)
  rc=$?
  while IFS= read -r line; do
    if [[ $line =~ ^([^|]+)[|]([^|]*)[|]([^|]*)[|](OK|WARN|CRIT|INFO)$ ]]
    then add "${BASH_REMATCH[@]:1}"
    elif [[ $line =~ (ORA|SP2)-[0-9] ]]; then add "DB QUERY" error "$line" CRIT
    elif [[ $line =~ [^[:space:]] && ! $line =~ ^(ERROR|Process|Session) ]]
    then add "DB QUERY" "unparsed line" "$line" WARN
    fi
  done <<< "$out"
  [ "$rc" = 124 ] && add "DB QUERY" sqlplus "timed out" CRIT
  [ "$rc" -ge 126 ] && add "DB QUERY" sqlplus "cannot run sqlplus, rc=$rc" CRIT
  [ "${#R[@]}" -gt "$n0" ] || add "DB QUERY" sqlplus "no output, rc=$rc" CRIT
}
#== S07 dest
check_dest() {
  sql "sby=$sby" <<'SQL'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 VERIFY OFF TAB OFF LINESIZE 1000
SELECT 'ARCHIVE DEST|Dest ' || dest_id || ' -> ' || destination || '|'
  || status || CASE WHEN error IS NOT NULL THEN ': '
  || REPLACE(error, '|', '/') END || '|'
  || CASE WHEN status = 'VALID' THEN 'OK' ELSE 'CRIT' END
  FROM v$archive_dest WHERE status <> 'INACTIVE'
  AND destination IS NOT NULL ORDER BY dest_id;
SELECT 'DB SYNC STATUS|standby destination|detected '
  || NVL(TO_CHAR(MIN(dest_id)), 'none') || ', configured '
  || DECODE(&sby, 0, 'auto', -1, 'none', TO_CHAR(&sby)) || '|' || CASE
  WHEN &sby < 0 THEN 'INFO'
  WHEN MIN(dest_id) IS NULL AND &sby > 0 THEN 'CRIT'
  WHEN MIN(dest_id) IS NULL THEN 'WARN'
  WHEN &sby > 0 AND MIN(dest_id) <> &sby THEN 'WARN' ELSE 'INFO' END
  FROM v$archive_dest WHERE target = 'STANDBY' AND status <> 'INACTIVE';
EXIT
SQL
}
#== S08 sync
check_sync() {
  sql "sby=$sby" "gwarn=$GAP_WARN" "gcrit=$GAP_CRIT" \
    "lwarn=$LAG_WARN_MIN" "lcrit=$LAG_CRIT_MIN" <<'SQL'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 VERIFY OFF TAB OFF LINESIZE 1000
WITH sd AS (SELECT NVL(NULLIF(&sby, 0), MIN(dest_id)) d
  FROM v$archive_dest WHERE target = 'STANDBY' AND status <> 'INACTIVE'),
rl AS (SELECT resetlogs_change# r FROM v$database),
pr AS (SELECT thread#, MAX(sequence#) seq FROM v$archived_log, rl
  WHERE standby_dest = 'NO' AND resetlogs_change# = rl.r GROUP BY thread#),
dr AS (SELECT a.thread#, MAX(a.sequence#) seq, MAX(a.next_time) t
  FROM v$archived_log a, sd, rl WHERE a.dest_id = sd.d
  AND a.applied = 'YES' AND a.resetlogs_change# = rl.r GROUP BY a.thread#),
x AS (SELECT pr.thread# th, pr.seq ps, dr.seq ds, pr.seq - dr.seq gap,
  ROUND((SYSDATE - dr.t) * 1440) mins FROM pr LEFT JOIN dr
  ON dr.thread# = pr.thread#)
SELECT 'DB SYNC STATUS|Thread ' || th || '|PR=' || ps || ' DR='
  || NVL(TO_CHAR(ds), 'NONE') || ' GAP=' || NVL(TO_CHAR(gap), '?')
  || ' LAG=' || CASE WHEN ds IS NULL THEN '?' WHEN gap <= 0 THEN '0'
  ELSE TO_CHAR(mins) END || 'min|' || CASE WHEN ds IS NULL THEN 'CRIT'
  WHEN gap > &gcrit OR (gap > 0 AND mins > &lcrit) THEN 'CRIT'
  WHEN gap > &gwarn OR (gap > 0 AND mins > &lwarn) THEN 'WARN'
  ELSE 'OK' END FROM x ORDER BY th;
EXIT
SQL
}
#== S09 main
cfg
find_sid
case $STANDBY_DEST in
  '') sby=0 ;;
  none) sby=-1 ;;
  *[!0-9]*) die 65 "STANDBY_DEST must be a number or none" ;;
  *) sby=$STANDBY_DEST ;;
esac
if [ "$MODE" = check ]; then
  show_cfg
  sql "sby=$sby" <<'SQL'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 VERIFY OFF TAB OFF LINESIZE 1000
SELECT 'TEST|standby destination|detected '
  || NVL(TO_CHAR(MIN(dest_id)), 'none') || ', configured '
  || DECODE(&sby, 0, 'auto', -1, 'none', TO_CHAR(&sby)) || '|' || CASE
  WHEN MIN(dest_id) IS NULL AND &sby = 0 THEN 'WARN'
  WHEN &sby > 0 AND NVL(MIN(dest_id), -2) <> &sby THEN 'CRIT' ELSE 'OK' END
  FROM v$archive_dest WHERE target = 'STANDBY' AND status <> 'INACTIVE';
EXIT
SQL
  report
fi
check_dest
if [ "$sby" = -1 ]; then
  add "DB SYNC STATUS" "Data Guard" "not checked, STANDBY_DEST=none" INFO
else
  check_sync
fi
report
