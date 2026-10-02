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
