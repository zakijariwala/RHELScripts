#!/bin/bash
#== S01 settings
VERSION=1.0.0
NAME="db-check"
ABOUT="database status, instances, app sessions, limits, blocking, long calls"
CHECKS="open mode, log mode, instances, sessions, limits, blocking, long calls"
KEYS="ORACLE_SID APP_USER GRID_HOME EXPECTED_INSTANCES RESTART_WARN_DAYS"
KEYS="$KEYS ACTIVE_MAX INACTIVE_MAX LIMIT_WARN LIMIT_CRIT BLOCK_SECS"
KEYS="$KEYS LONG_QUERY_SECS LONG_QUERY_SKIP SQL_TIMEOUT"
ORACLE_SID='' APP_USER='' GRID_HOME='' EXPECTED_INSTANCES='' RESTART_WARN_DAYS=1
ACTIVE_MAX=18 INACTIVE_MAX=1000 LIMIT_WARN=80 LIMIT_CRIT=90 BLOCK_SECS=300
LONG_QUERY_SECS=1800 LONG_QUERY_SKIP=SYS,SYSTEM,GGADMIN SQL_TIMEOUT=300
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
#== S07 status
check_status() {
  sql "restart=$RESTART_WARN_DAYS" "instances=$EXPECTED_INSTANCES" <<'SQL'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 VERIFY OFF TAB OFF LINESIZE 1000
SELECT 'DATABASE|name|' || name || '|INFO' FROM v$database;
SELECT 'DB STATUS|OPEN_MODE inst ' || inst_id || '|' || open_mode || '|'
  || CASE WHEN open_mode = 'READ WRITE' THEN 'OK' ELSE 'CRIT' END
  FROM gv$database ORDER BY inst_id;
SELECT 'DB STATUS|LOG_MODE|' || log_mode || '|'
  || CASE WHEN log_mode = 'ARCHIVELOG' THEN 'OK' ELSE 'CRIT' END
  FROM v$database;
SELECT 'INSTANCE STATUS|Instance ' || inst_id || ' (' || instance_name
  || ' on ' || host_name || ')|' || status || ', up '
  || TO_CHAR(ROUND(SYSDATE - startup_time, 1), 'FM9990.0') || ' days|'
  || CASE WHEN status <> 'OPEN' THEN 'CRIT'
  WHEN SYSDATE - startup_time < &restart THEN 'WARN' ELSE 'OK' END
  FROM gv$instance ORDER BY inst_id;
SELECT 'INSTANCE STATUS|Instances OPEN|' || COUNT(*) || ' of &instances|'
  || CASE WHEN COUNT(*) < &instances THEN 'CRIT' ELSE 'OK' END
  FROM gv$instance WHERE status = 'OPEN';
EXIT
SQL
}
#== S08 sessions
check_sessions() {
  sql "app=$APP_USER" "amax=$ACTIVE_MAX" "imax=$INACTIVE_MAX" <<'SQL'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 VERIFY OFF TAB OFF LINESIZE 1000
SELECT 'SESSION COUNT|Inst ' || i.inst_id || ' ' || st.s || '|'
  || NVL(c.cnt, 0) || '|' || CASE
  WHEN st.s = 'ACTIVE' AND NVL(c.cnt, 0) = 0 THEN 'WARN'
  WHEN st.s = 'ACTIVE' AND c.cnt > &amax THEN 'WARN'
  WHEN st.s = 'INACTIVE' AND NVL(c.cnt, 0) > &imax THEN 'WARN'
  ELSE 'OK' END
  FROM gv$instance i CROSS JOIN (SELECT 'ACTIVE' s FROM dual
  UNION ALL SELECT 'INACTIVE' FROM dual) st
  LEFT JOIN (SELECT inst_id, status, COUNT(*) cnt FROM gv$session
  WHERE username = '&app' GROUP BY inst_id, status) c
  ON c.inst_id = i.inst_id AND c.status = st.s
  ORDER BY i.inst_id, st.s;
EXIT
SQL
}
#== S09 load
check_load() {
  sql "lwarn=$LIMIT_WARN" "lcrit=$LIMIT_CRIT" "blk=$BLOCK_SECS" \
    "lq=$LONG_QUERY_SECS" "skip=$LONG_QUERY_SKIP" <<'SQL'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 VERIFY OFF TAB OFF LINESIZE 1000
SELECT 'SESSION LIMIT|Inst ' || inst_id || ' ' || resource_name || '|'
  || current_utilization || ' of ' || TRIM(limit_value) || '|' || CASE
  WHEN current_utilization > TO_NUMBER(TRIM(limit_value)) * &lcrit / 100
  THEN 'CRIT'
  WHEN current_utilization > TO_NUMBER(TRIM(limit_value)) * &lwarn / 100
  THEN 'WARN' ELSE 'OK' END
  FROM gv$resource_limit WHERE resource_name IN ('processes', 'sessions')
  AND TRIM(limit_value) <> 'UNLIMITED' ORDER BY inst_id, resource_name;
SELECT 'BLOCKING|Sessions blocked > &blk.s|' || COUNT(*) || '|'
  || CASE WHEN COUNT(*) > 0 THEN 'WARN' ELSE 'OK' END FROM gv$session
  WHERE blocking_session IS NOT NULL AND seconds_in_wait > &blk;
SELECT 'LONG CALLS|Active calls > &lq.s|' || COUNT(*) || '|'
  || CASE WHEN COUNT(*) > 0 THEN 'WARN' ELSE 'OK' END FROM gv$session
  WHERE type = 'USER' AND status = 'ACTIVE' AND username IS NOT NULL
  AND INSTR(',&skip,', ',' || username || ',') = 0
  AND last_call_et > &lq;
EXIT
SQL
}
#== S10 main
cfg
olr=$(awk -F= '/^crs_home=/ { print $2 }' /etc/oracle/olr.loc 2>/dev/null)
detect GRID_HOME "$olr"
nodes=$("$GRID_HOME/bin/olsnodes" 2>/dev/null | wc -l)
[ "$nodes" -gt 0 ] && detect EXPECTED_INSTANCES "$nodes"
find_sid
need APP_USER
need EXPECTED_INSTANCES
if [ "$MODE" = check ]; then
  show_cfg
  sql "app=$APP_USER" <<'SQL'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 VERIFY OFF TAB OFF LINESIZE 1000
SELECT 'TEST|login, APP_USER exists|&app|' || CASE WHEN COUNT(*) = 1
  THEN 'OK' ELSE 'CRIT' END FROM dba_users WHERE username = '&app';
EXIT
SQL
  report
fi
check_status
check_sessions
check_load
report
