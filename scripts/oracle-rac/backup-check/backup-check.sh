#!/bin/bash
#== S01 settings
VERSION=1.0.0
NAME="backup-check"
ABOUT="Fast Recovery Area use and RMAN backup age"
CHECKS="FRA used percent, last DB backup, last archivelog backup, failures"
KEYS="ORACLE_SID FRA_WARN FRA_CRIT CHECK_RMAN DB_BACKUP_MAX_HRS"
KEYS="$KEYS ARCH_BACKUP_MAX_HRS SQL_TIMEOUT"
ORACLE_SID='' FRA_WARN=80 FRA_CRIT=90 CHECK_RMAN=1 DB_BACKUP_MAX_HRS=26
ARCH_BACKUP_MAX_HRS=6 SQL_TIMEOUT=300
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
#== S07 fra
check_fra() {
  sql "fwarn=$FRA_WARN" "fcrit=$FRA_CRIT" <<'SQL'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 VERIFY OFF TAB OFF LINESIZE 1000
SELECT 'FRA USAGE|' || name || '|Used=' || TO_CHAR(pct, 'FM990.00')
  || '% of ' || gb || 'G|' || CASE WHEN pct > &fcrit THEN 'CRIT'
  WHEN pct > &fwarn THEN 'WARN' ELSE 'OK' END
  FROM (SELECT name, ROUND(space_limit / 1073741824) gb,
  ROUND((space_used - space_reclaimable) / space_limit * 100, 2) pct
  FROM v$recovery_file_dest WHERE space_limit > 0);
SELECT 'FRA USAGE|FRA|not configured|INFO' FROM dual WHERE NOT EXISTS
  (SELECT 1 FROM v$recovery_file_dest WHERE space_limit > 0);
EXIT
SQL
}
#== S08 rman
check_rman() {
  sql "dbhrs=$DB_BACKUP_MAX_HRS" "archrs=$ARCH_BACKUP_MAX_HRS" <<'SQL'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 VERIFY OFF TAB OFF LINESIZE 1000
SELECT 'RMAN BACKUP|Last DB backup (full/incr)|'
  || NVL(TO_CHAR(MAX(end_time), 'DD-MM-YYYY HH24:MI'), 'NONE') || '|'
  || CASE WHEN MAX(end_time) IS NULL
  OR (SYSDATE - MAX(end_time)) * 24 > &dbhrs THEN 'CRIT' ELSE 'OK' END
  FROM v$rman_backup_job_details WHERE input_type IN ('DB FULL', 'DB INCR')
  AND status IN ('COMPLETED', 'COMPLETED WITH WARNINGS');
SELECT 'RMAN BACKUP|Last archivelog backup|'
  || NVL(TO_CHAR(MAX(end_time), 'DD-MM-YYYY HH24:MI'), 'NONE') || '|'
  || CASE WHEN MAX(end_time) IS NULL
  OR (SYSDATE - MAX(end_time)) * 24 > &archrs THEN 'WARN' ELSE 'OK' END
  FROM v$rman_backup_job_details WHERE input_type = 'ARCHIVELOG'
  AND status IN ('COMPLETED', 'COMPLETED WITH WARNINGS');
SELECT 'RMAN BACKUP|Failed jobs (24h)|' || COUNT(*) || '|'
  || CASE WHEN COUNT(*) > 0 THEN 'WARN' ELSE 'OK' END
  FROM v$rman_backup_job_details
  WHERE status LIKE '%FAILED%' AND start_time > SYSDATE - 1;
EXIT
SQL
}
#== S09 main
cfg
find_sid
if [ "$MODE" = check ]; then
  show_cfg
  sql "x=1" <<'SQL'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 VERIFY OFF TAB OFF LINESIZE 1000
SELECT 'TEST|sqlplus login|' || instance_name || ' ' || status || '|OK'
  FROM v$instance;
EXIT
SQL
  report
fi
check_fra
if [ "$CHECK_RMAN" = 1 ]; then
  check_rman
else
  add "RMAN BACKUP" "RMAN" "not checked, CHECK_RMAN=0" INFO
fi
report
