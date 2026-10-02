#!/bin/bash
#== S01 settings
VERSION=1.0.0
NAME="space-check"
ABOUT="TEMP, permanent tablespaces and ASM diskgroups, percent used"
CHECKS="TEMP, top TEMP consumer, 5 fullest tablespaces, ASM diskgroups"
KEYS="ORACLE_SID TEMP_WARN TEMP_CRIT TS_WARN TS_CRIT ASM_WARN ASM_CRIT"
KEYS="$KEYS SQL_TIMEOUT"
ORACLE_SID='' TEMP_WARN=75 TEMP_CRIT=90 TS_WARN=85 TS_CRIT=95
ASM_WARN=80 ASM_CRIT=90 SQL_TIMEOUT=300
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
#== S07 temp
check_temp() {
  sql "twarn=$TEMP_WARN" "tcrit=$TEMP_CRIT" <<'SQL'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 VERIFY OFF TAB OFF LINESIZE 1000
SELECT 'TEMP USAGE|' || name || '|Used=' || TO_CHAR(pct, 'FM990.00')
  || '% of ' || gb || 'G|' || CASE WHEN pct > &tcrit THEN 'CRIT'
  WHEN pct > &twarn THEN 'WARN' ELSE 'OK' END
  FROM (SELECT t.tablespace_name name, ROUND(t.mx / 1073741824, 1) gb,
  ROUND(NVL(u.b, 0) / t.mx * 100, 2) pct
  FROM (SELECT tablespace_name, SUM(CASE WHEN autoextensible = 'YES'
  THEN GREATEST(bytes, maxbytes) ELSE bytes END) mx
  FROM dba_temp_files GROUP BY tablespace_name) t
  LEFT JOIN (SELECT s.tablespace_name, SUM(s.used_blocks * d.block_size) b
  FROM gv$sort_segment s JOIN dba_tablespaces d
  ON d.tablespace_name = s.tablespace_name GROUP BY s.tablespace_name) u
  ON u.tablespace_name = t.tablespace_name WHERE t.mx > 0);
SELECT 'TEMP USAGE|Top consumer|' || s.username || ' sid ' || s.sid
  || ' inst ' || s.inst_id || ': ' || ROUND(u.blocks * t.block_size
  / 1048576) || 'M, sql_id ' || NVL(u.sql_id, '-') || '|INFO'
  FROM gv$tempseg_usage u JOIN gv$session s ON s.inst_id = u.inst_id
  AND s.saddr = u.session_addr AND s.serial# = u.session_num
  JOIN dba_tablespaces t ON t.tablespace_name = u.tablespace
  ORDER BY u.blocks DESC FETCH FIRST 1 ROWS ONLY;
EXIT
SQL
}
#== S08 space
check_space() {
  sql "swarn=$TS_WARN" "scrit=$TS_CRIT" "awarn=$ASM_WARN" \
    "acrit=$ASM_CRIT" <<'SQL'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 VERIFY OFF TAB OFF LINESIZE 1000
SELECT 'TABLESPACE USAGE|' || m.tablespace_name || '|Used='
  || TO_CHAR(ROUND(m.used_percent, 2), 'FM990.00') || '% of max|' || CASE
  WHEN m.used_percent > &scrit THEN 'CRIT'
  WHEN m.used_percent > &swarn THEN 'WARN' ELSE 'OK' END
  FROM dba_tablespace_usage_metrics m JOIN dba_tablespaces t
  ON t.tablespace_name = m.tablespace_name WHERE t.contents = 'PERMANENT'
  ORDER BY m.used_percent DESC FETCH FIRST 5 ROWS ONLY;
SELECT 'ASM DISKGROUP|' || name || '|Used='
  || TO_CHAR(ROUND((1 - free_mb / total_mb) * 100, 2), 'FM990.00')
  || '%, usable free ' || ROUND(usable_file_mb / 1024) || 'G|' || CASE
  WHEN usable_file_mb < 0 OR (1 - free_mb / total_mb) * 100 > &acrit
  THEN 'CRIT' WHEN (1 - free_mb / total_mb) * 100 > &awarn THEN 'WARN'
  ELSE 'OK' END FROM v$asm_diskgroup_stat WHERE total_mb > 0 ORDER BY name;
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
check_temp
check_space
report
