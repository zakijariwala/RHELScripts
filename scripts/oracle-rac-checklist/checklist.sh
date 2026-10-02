#!/bin/bash
#==============================================================================
# checklist.sh  -  Oracle RAC monitoring checklist          v2.1
#
# HOW TO READ THE ANNOTATIONS
#   [ADDED]    new in v2
#   [CHANGED]  v1 logic kept, behaviour modified
#   [FIXED]    v1 bug corrected
#   [REMOVED]  v1 code deleted
#   [... v2.1] the same, for changes made in v2.1
#   #~ ...     struck-out older line, kept for reference only, never executed
#   --~ ...    same, inside the SQL block
#
# SETUP [ADDED v2.1]
#   Copy config.env.example to config.env in the same folder and edit it.
#   Full steps: README.md in the same folder.
#
# USAGE
#   bash checklist.sh                   CSV to terminal (same shape as v1)
#   bash checklist.sh --table           aligned table, easier to read on screen
#   bash checklist.sh --html            HTML report to stdout
#   bash checklist.sh --mail            send HTML report to MAIL_TO
#   bash checklist.sh --mail-if-issues  send only when WARN/CRIT found (cron later)
#   bash checklist.sh --no-history      skip writing the history log
#
#   Run it the same way as v1, but with bash instead of sh:
#~   sudo -iu oracle bash -c "cd /home/oracle/scripts && bash ./checklist.sh --table"
#   [CHANGED v2.1] own folder, so config.env sits next to it and v1 stays put:
#   sudo -iu oracle bash -c "cd /home/oracle/scripts/oracle-rac-checklist && bash ./checklist.sh --table"
#
# EXIT CODES [ADDED]
#   0 all OK | 1 at least one WARN | 2 at least one CRIT | 3 already running
#   64 bad option or invalid config.env                           [ADDED v2.1]
#
# CHANGELOG v1 -> v2
#   FIXED
#    1. Node 2 unreachable printed "Normal" (u2/m2 defaulted to 0). Now CRIT.
#    2. A down instance vanished from GV$INSTANCE output. Now counted
#       against EXPECTED_INSTANCES.
#    3. sqlplus errors (ORA-/SP2-) were dropped by the awk NF>1 filter.
#       Now reported as CRIT rows.
#    4. "No Active Session" branch could never fire under GROUP BY.
#       Now every instance x status row always appears.
#    5. TEMP used bytes_cached (cached extents, not usage) from local v$ only.
#       Now real used blocks across all instances vs max size incl. autoextend.
#    6. DB sync mixed archive destinations, dropped threads with no applied
#       log, and had no time-based lag. All three fixed.
#    7. sftp_output and server_checklist were printed with no freshness
#       check. A dead producer job showed "all good" forever. Now stale = CRIT.
#    8. ssh calls could hang forever. Now BatchMode + ConnectTimeout + timeout.
#   CHANGED
#    - OPEN_MODE checked on every instance (was ROWNUM = 1)
#    - Memory % uses "available" column; CPU samples 3s (was 1s)
#    - Node 2 metrics in one ssh call (was three)
#    - IPs, ports, thresholds moved to CONFIG
#    - One status vocabulary: OK / WARN / CRIT / INFO
#      (was Normal / High / Warning / CRITICAL / Running / High Session)
#    - CSV fields quoted, so commas inside values no longer shift columns
#   ADDED
#    - Permanent tablespaces, FRA, archive destination errors, ASM diskgroups,
#      RMAN backup age, alert log ORA- errors, Clusterware resources,
#      filesystems on both nodes, swap, load, process/session limits,
#      blocking sessions, long-running calls, top TEMP consumer,
#      GoldenGate lag/checkpoint thresholds, sftp.log size threshold
#    - Summary row, exit codes, HTML report, mail, history log, run lock
#   REMOVED
#    - Commented-out "sar -r" lines (dead code)
#    - echo -e on section headers (nothing to escape)
#
# CHANGELOG v2 -> v2.1
#   CHANGED
#    - CONFIG values moved to config.env next to the script. The script
#      reads it as KEY=value lines and validates every value; it never
#      executes it. Built-in defaults stay in the script.
#    - crsctl and activesession.sh timeouts moved to config
#      (CRS_TIMEOUT, ACTIVESESSION_TIMEOUT); they were inline.
#    - --no-history now wins over WRITE_HISTORY=1 in config.env.
#   ADDED
#    - CHECK_GG toggle: 0 skips GoldenGate (pre-prod has none).
#    - CHECK_DG toggle: 0 skips Data Guard sync (DB with no standby).
#    - CONFIG row: says whether config.env was loaded.
#    - Exit code 64 for an invalid config.env.
#==============================================================================

# --- Run under real bash even if started as "sh checklist.sh" ------- [ADDED]
# v1 ran via "sh ./checklist.sh". On RHEL, sh is bash in POSIX mode, which
# disables features used below. This switches POSIX mode off.
if [ -z "$BASH_VERSION" ]; then exec /bin/bash "$0" "$@"; fi
set +o posix 2>/dev/null
set -o pipefail

#================================ CONFIG ======================================
# [ADDED] Everything v1 hardcoded inline now lives here.
# [CHANGED v2.1] These are now BUILT-IN DEFAULTS. Put your site's values in
#   config.env next to this script (copy config.env.example). Any key that
#   config.env leaves out keeps the default below.
#   Host defaults are placeholders on purpose: a run without config.env
#   reports node 2 and GoldenGate as CRIT instead of looking healthy.

# --- Hosts ------------------------------------------- [CHANGED] were inline
NODE2_HOST="CHANGE_ME_NODE2_IP";  NODE2_PORT=22
GG_HOST="CHANGE_ME_GG_IP";    GG_PORT=22
SSH_TIMEOUT=60          # seconds per remote call                       [ADDED]
SQL_TIMEOUT=300         # seconds for the whole sqlplus block           [ADDED]
CRS_TIMEOUT=60          # seconds for crsctl              [CHANGED v2.1] was inline
ACTIVESESSION_TIMEOUT=120  # seconds for activesession.sh [CHANGED v2.1] was inline
# [ADDED] BatchMode: fail fast instead of waiting on a password prompt
# Not configurable on purpose: every ssh call must keep these options.
SSH_OPTS=(-q -o BatchMode=yes -o ConnectTimeout=10)

# --- Toggles ----------------------------------------------------- [ADDED v2.1]
CHECK_GG=1              # 0 = skip GoldenGate (host has none, e.g. pre-prod)
CHECK_DG=1              # 0 = skip Data Guard sync (database has no standby)

# --- Paths --------------------------------------------------------------------
SCRIPTS_DIR="/home/oracle/scripts"
# [CHANGED v2.1] blank = derived from SCRIPTS_DIR after config.env is read
#~ GG_SCRIPT="$SCRIPTS_DIR/gg2.sh"
#~ ACTIVESESSION_SCRIPT="$SCRIPTS_DIR/activesession.sh"
GG_SCRIPT=""            # blank = $SCRIPTS_DIR/gg2.sh (path on the GG host)
ACTIVESESSION_SCRIPT="" # blank = $SCRIPTS_DIR/activesession.sh
SFTP_FILE="/home/oracle/sftp_output"
SERVER_FILE="/home/oracle/server_checklist"
# [ADDED] Grid home for crsctl. Auto-detected from olr.loc; set by hand if blank.
# [CHANGED v2.1] detection moved below, after config.env is read
#~ GRID_HOME="$(awk -F= '/^crs_home/{print $2}' /etc/oracle/olr.loc 2>/dev/null)"
#~ GRID_HOME="${GRID_HOME:-/u01/app/19.0.0/grid}"
GRID_HOME=""            # blank = auto-detect

# --- History log (for trends, and for Splunk later) ----------------- [ADDED]
WRITE_HISTORY=1
LOG_DIR="/home/oracle/checklist_history"
LOG_RETENTION_DAYS=30

# --- Mail ----------------------------------------------------------- [ADDED]
# Comma-separated. Leave MAIL_CC empty if not needed.
MAIL_TO=""
MAIL_CC=""
MAIL_FROM=""            # e.g. the shared mailbox address; must be allowed by the relay
SUBJECT_TAG="CHANGE_ME_ENV"       # matches current subject: Monitoring Checklist | ENV | date | time

# --- Database ------------------------------------------------------------------
APP_USER="CHANGE_ME_APP_SCHEMA"
EXPECTED_INSTANCES=2                                                    # [ADDED]

# --- Thresholds  (WARN / CRIT) ----------------------------------------------
# Values marked "v1" keep the v1 number so results stay comparable.
CPU_WARN=60;     CPU_CRIT=85        # %          v1: 60 = "High"
MEM_WARN=75;     MEM_CRIT=90        # %          v1: 75 = "High"
SWAP_WARN=10;    SWAP_CRIT=30       # %                                  [ADDED]
LOAD_WARN=1.0;   LOAD_CRIT=2.0      # load average per core              [ADDED]
FS_WARN=80;      FS_CRIT=90         # % per mount                        [ADDED]
TEMP_WARN=75;    TEMP_CRIT=90       # %          v1
TS_WARN=85;      TS_CRIT=95         # % of max size incl. autoextend     [ADDED]
FRA_WARN=80;     FRA_CRIT=90        # % net of reclaimable               [ADDED]
ASM_WARN=80;     ASM_CRIT=90        # %                                  [ADDED]
LIMIT_WARN=80;   LIMIT_CRIT=90      # % of processes / sessions param    [ADDED]
ACTIVE_MAX=18                       # APP_USER active sessions   v1
INACTIVE_MAX=1000                   # APP_USER inactive sessions v1
GAP_WARN=10;     GAP_CRIT=100       # archive log sequences      v1
LAG_WARN_MIN=15; LAG_CRIT_MIN=60    # minutes behind, only when GAP > 0  [ADDED]
RESTART_WARN_DAYS=1                 # instance up less than this = WARN  [ADDED]
BLOCK_SECS=300                      # blocked longer than this = WARN    [ADDED]
LONG_QUERY_SECS=1800                # active call longer than this = WARN[ADDED]
# Users excluded from the long-call check. Replace GGADMIN with your actual
# GoldenGate DB user; its sessions stay ACTIVE permanently.
LONG_QUERY_EXCLUDE="'SYS','SYSTEM','GGADMIN'"
CHECK_RMAN=1                        # set 0 if backups run on the DR side[ADDED]
DB_BACKUP_MAX_HRS=26;  ARCH_BACKUP_MAX_HRS=6   # set to your backup policy
CHECK_ALERTLOG=1;      ALERT_WINDOW_HRS=4      # local instance only     [ADDED]
GG_LAG_WARN=60;        GG_LAG_CRIT=300         # seconds                 [ADDED]
GG_CKPT_WARN_MIN=5;    GG_CKPT_CRIT_MIN=15     # checkpoint age, minutes [ADDED]
STALE_MIN=60            # static input file older than this = CRIT       [ADDED]
                        # set to roughly 2x how often its producer job runs
SFTP_LOG_WARN_MB=1024   # sftp.log size; at 1003M today it has no rotation [ADDED]

#============================ CONFIG FILE [ADDED v2.1] ========================
# config.env is READ as data, never executed with "source". It may hold only
# KEY=value lines for the keys in CONFIG_TYPE, and each value must match its
# type. Why: several values are pasted into the SQL sent as SYSDBA. If the
# file were sourced, or values were unchecked, an edit to config.env could
# run any command, or add a write statement to the read-only SQL without
# tools/check-readonly-sql.sh ever seeing it.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.env"
CONFIG_STATE=""                 # filled by load_config, reported as the CONFIG row

declare -A CONFIG_TYPE=(
    [NODE2_HOST]=host [NODE2_PORT]=int [GG_HOST]=host [GG_PORT]=int
    [SSH_TIMEOUT]=int [SQL_TIMEOUT]=int [CRS_TIMEOUT]=int [ACTIVESESSION_TIMEOUT]=int
    [CHECK_GG]=bool [CHECK_DG]=bool [CHECK_RMAN]=bool [CHECK_ALERTLOG]=bool [WRITE_HISTORY]=bool
    [SCRIPTS_DIR]=path [GG_SCRIPT]=path? [ACTIVESESSION_SCRIPT]=path? [SFTP_FILE]=path
    [SERVER_FILE]=path [GRID_HOME]=path? [LOG_DIR]=path [LOG_RETENTION_DAYS]=int
    [MAIL_TO]=mail [MAIL_CC]=mail [MAIL_FROM]=mail [SUBJECT_TAG]=text
    [APP_USER]=dbname [EXPECTED_INSTANCES]=int [LONG_QUERY_EXCLUDE]=dbnamelist
    [CPU_WARN]=num [CPU_CRIT]=num [MEM_WARN]=num [MEM_CRIT]=num
    [SWAP_WARN]=num [SWAP_CRIT]=num [LOAD_WARN]=num [LOAD_CRIT]=num
    [FS_WARN]=num [FS_CRIT]=num [TEMP_WARN]=num [TEMP_CRIT]=num
    [TS_WARN]=num [TS_CRIT]=num [FRA_WARN]=num [FRA_CRIT]=num
    [ASM_WARN]=num [ASM_CRIT]=num [LIMIT_WARN]=num [LIMIT_CRIT]=num
    [ACTIVE_MAX]=int [INACTIVE_MAX]=int [GAP_WARN]=int [GAP_CRIT]=int
    [LAG_WARN_MIN]=int [LAG_CRIT_MIN]=int [RESTART_WARN_DAYS]=num
    [BLOCK_SECS]=int [LONG_QUERY_SECS]=int
    [DB_BACKUP_MAX_HRS]=int [ARCH_BACKUP_MAX_HRS]=int [ALERT_WINDOW_HRS]=int
    [GG_LAG_WARN]=int [GG_LAG_CRIT]=int [GG_CKPT_WARN_MIN]=int [GG_CKPT_CRIT_MIN]=int
    [STALE_MIN]=int [SFTP_LOG_WARN_MB]=int
)

valid_value() {                 # valid_value TYPE VALUE -> 0 if VALUE fits TYPE
    local t="$1" v="$2"
    local re_name='[A-Za-z][A-Za-z0-9_$#]*'
    case "$t" in
        int)        [[ "$v" =~ ^[0-9]+$ ]] ;;
        num)        [[ "$v" =~ ^[0-9]+(\.[0-9]+)?$ ]] ;;
        bool)       [[ "$v" =~ ^[01]$ ]] ;;
        host)       [[ "$v" =~ ^[A-Za-z0-9][A-Za-z0-9._:-]*$ ]] ;;
        path)       [[ "$v" =~ ^/[A-Za-z0-9._/+-]*$ ]] ;;
        path\?)     [ -z "$v" ] || valid_value path "$v" ;;
        mail)       [[ "$v" =~ ^[A-Za-z0-9@._+,\ -]*$ ]] ;;
        text)       [[ "$v" =~ ^[A-Za-z0-9._\ -]*$ ]] ;;
        dbname)     [[ "$v" =~ ^${re_name}$ ]] ;;
        dbnamelist) [[ "$v" =~ ^\'${re_name}\'(,\ *\'${re_name}\')*$ ]] ;;
        *)          return 1 ;;
    esac
}

load_config() {
    local line n=0 key val type
    if [ ! -e "$CONFIG_FILE" ]; then
        CONFIG_STATE="missing"; return 0
    fi
    if [ ! -r "$CONFIG_FILE" ]; then
        echo "config.env: cannot read $CONFIG_FILE" >&2; exit 64
    fi
    while IFS= read -r line || [ -n "$line" ]; do
        n=$((n + 1))
        line="${line%$'\r'}"                         # tolerate Windows line endings
        [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
        if [[ "$line" =~ ^[[:space:]]*([A-Z0-9_]+)=\"([^\"]*)\"[[:space:]]*(#.*)?$ ]] ||
           [[ "$line" =~ ^[[:space:]]*([A-Z0-9_]+)=\'([^\']*)\'[[:space:]]*(#.*)?$ ]] ||
           [[ "$line" =~ ^[[:space:]]*([A-Z0-9_]+)=([^[:space:]\"\'#]*)[[:space:]]*(#.*)?$ ]]; then
            key="${BASH_REMATCH[1]}"; val="${BASH_REMATCH[2]}"
        else
            echo "config.env line $n: not a KEY=value line: $line" >&2; exit 64
        fi
        type="${CONFIG_TYPE[$key]:-}"
        if [ -z "$type" ]; then
            echo "config.env line $n: unknown key $key (see config.env.example)" >&2; exit 64
        fi
        if ! valid_value "$type" "$val"; then
            echo "config.env line $n: $key=\"$val\" is not a valid $type value (see config.env.example)" >&2
            exit 64
        fi
        printf -v "$key" '%s' "$val"
    done < "$CONFIG_FILE"
    CONFIG_STATE="loaded"
}

#=============================== HELPERS ======================================
# [ADDED] v1 printed lines as it went. v2 stores every result first, so it can
# compute an overall status, a summary, exit codes, and several output formats.
R_SECTION=(); R_KEY=(); R_VALUE=(); R_STATUS=()
add() { R_SECTION+=("$1"); R_KEY+=("$2"); R_VALUE+=("$3"); R_STATUS+=("$4"); }

rank() { case "$1" in CRIT) echo 2;; WARN) echo 1;; *) echo 0;; esac; }

worst() {                       # worst status of all arguments
    local s w=OK
    for s in "$@"; do [ "$(rank "$s")" -gt "$(rank "$w")" ] && w=$s; done
    echo "$w"
}

rate() {                        # rate VALUE WARN CRIT -> OK | WARN | CRIT
    # Empty value means the metric could not be measured: WARN, never OK.
    awk -v v="$1" -v w="$2" -v c="$3" 'BEGIN {
        if (v == "") { print "WARN"; exit }
        if (v+0 > c+0) print "CRIT"; else if (v+0 > w+0) print "WARN"; else print "OK" }'
}

trim() {
    local s="$*"
    s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

file_age_min() {                # minutes since file was modified
    local m; m=$(stat -c %Y "$1" 2>/dev/null) || return 1
    echo $(( ( $(date +%s) - m ) / 60 ))
}

to_mb() {                       # 1003M / 1.2G / 500K -> MB
    awk -v s="$1" 'BEGIN { n=s+0; u=toupper(substr(s,length(s)))
        if (u=="G") n*=1024; else if (u=="K") n/=1024; else if (u=="T") n*=1048576
        printf "%d", n }'
}

#============================ 1. DATABASE =====================================
# v1 section "# 1. Capture SQLPlus output into a variable"
check_db() {
    local out rc line got=0 sql_rman="" sql_alert="" sql_dg=""
    local re='^([^|]+)\|([^|]*)\|([^|]*)\|(OK|WARN|CRIT|INFO)$'

    # [ADDED] RMAN backup age. Set CHECK_RMAN=0 if backups run on the standby,
    # otherwise this reports CRIT on the primary every time.
    if [ "$CHECK_RMAN" = 1 ]; then
        sql_rman=$(cat <<EOSQL
-- [ADDED] RMAN: last successful DB backup
SELECT 'RMAN BACKUP|Last DB backup (full/incr)|'||NVL(TO_CHAR(MAX(end_time),'DD-MM-YYYY HH24:MI'),'NONE')||'|'||CASE WHEN MAX(end_time) IS NULL OR (SYSDATE-MAX(end_time))*24 > $DB_BACKUP_MAX_HRS THEN 'CRIT' ELSE 'OK' END FROM v\$rman_backup_job_details WHERE status IN ('COMPLETED','COMPLETED WITH WARNINGS') AND input_type IN ('DB FULL','DB INCR');
-- [ADDED] RMAN: last successful archivelog backup
SELECT 'RMAN BACKUP|Last archivelog backup|'||NVL(TO_CHAR(MAX(end_time),'DD-MM-YYYY HH24:MI'),'NONE')||'|'||CASE WHEN MAX(end_time) IS NULL OR (SYSDATE-MAX(end_time))*24 > $ARCH_BACKUP_MAX_HRS THEN 'WARN' ELSE 'OK' END FROM v\$rman_backup_job_details WHERE status IN ('COMPLETED','COMPLETED WITH WARNINGS') AND input_type = 'ARCHIVELOG';
-- [ADDED] RMAN: failed jobs in the last 24 hours
SELECT 'RMAN BACKUP|Failed jobs (24h)|'||COUNT(*)||'|'||CASE WHEN COUNT(*) > 0 THEN 'WARN' ELSE 'OK' END FROM v\$rman_backup_job_details WHERE status LIKE '%FAILED%' AND start_time > SYSDATE - 1;
EOSQL
)
    fi

    # [ADDED] Alert log ORA- errors. v\$diag_alert_ext reads the LOCAL
    # instance's log only. Node 2's alert log is not covered yet.
    if [ "$CHECK_ALERTLOG" = 1 ]; then
        sql_alert=$(cat <<EOSQL
-- [ADDED] Alert log: ORA- count and latest message in the window
SELECT 'ALERT LOG|ORA- errors last ${ALERT_WINDOW_HRS}h (local instance)|'||COUNT(*)||CASE WHEN COUNT(*) > 0 THEN ', latest: '||SUBSTR(REPLACE(REPLACE(REPLACE(MAX(message_text) KEEP (DENSE_RANK LAST ORDER BY originating_timestamp),'|','/'),CHR(10),' '),CHR(13),' '),1,150) END||'|'||CASE WHEN COUNT(*) > 0 THEN 'WARN' ELSE 'OK' END FROM v\$diag_alert_ext WHERE originating_timestamp > SYSTIMESTAMP - INTERVAL '$ALERT_WINDOW_HRS' HOUR AND component_id = 'rdbms' AND message_text LIKE '%ORA-%';
EOSQL
)
    fi

    # [ADDED v2.1] Data Guard sync. Set CHECK_DG=0 when the database has no
    # standby; otherwise every thread reports CRIT "DR=NONE".
    if [ "$CHECK_DG" = 1 ]; then
        sql_dg=$(cat <<EOSQL
-- DB SYNC STATUS
-- [FIXED] three problems in v1:
--   a) no dest_id filter: rows from local and standby destinations mixed
--   b) INNER JOIN: a thread with no applied log vanished from the output
--   c) gap counted sequences only, with no time component
-- Now: standby destination only, LEFT JOIN (missing thread = CRIT), and a
-- minutes-behind figure. Lag only counts when GAP > 0, so a quiet thread
-- that has not switched logs for hours does not raise a false alarm.
-- Uses the lowest-numbered active standby destination.
--~ ... FROM (SELECT MAX(sequence#) ... FROM v\$archived_log GROUP BY thread#) pr JOIN (... WHERE applied = 'YES' ...) dr ...
WITH sd AS (SELECT MIN(dest_id) dest_id FROM v\$archive_dest WHERE target = 'STANDBY' AND status <> 'INACTIVE'),
rl AS (SELECT resetlogs_change# r FROM v\$database),
pr AS (SELECT thread#, MAX(sequence#) seq FROM v\$archived_log, rl WHERE standby_dest = 'NO' AND resetlogs_change# = rl.r GROUP BY thread#),
dr AS (SELECT l.thread#, MAX(l.sequence#) seq, MAX(l.next_time) t FROM v\$archived_log l, sd, rl WHERE l.dest_id = sd.dest_id AND l.applied = 'YES' AND l.resetlogs_change# = rl.r GROUP BY l.thread#)
SELECT 'DB SYNC STATUS|Thread '||pr.thread#||'|PR='||pr.seq||' DR='||NVL(TO_CHAR(dr.seq),'NONE')||' GAP='||NVL(TO_CHAR(pr.seq-dr.seq),'?')||' LAG='||CASE WHEN dr.seq IS NULL THEN '?' WHEN pr.seq-dr.seq <= 0 THEN '0' ELSE TO_CHAR(ROUND((SYSDATE-dr.t)*1440)) END||'min|'||
CASE WHEN dr.seq IS NULL THEN 'CRIT'
     WHEN pr.seq-dr.seq > $GAP_CRIT OR (pr.seq-dr.seq > 0 AND (SYSDATE-dr.t)*1440 > $LAG_CRIT_MIN) THEN 'CRIT'
     WHEN pr.seq-dr.seq > $GAP_WARN OR (pr.seq-dr.seq > 0 AND (SYSDATE-dr.t)*1440 > $LAG_WARN_MIN) THEN 'WARN'
     ELSE 'OK' END
FROM pr LEFT JOIN dr ON dr.thread# = pr.thread# ORDER BY pr.thread#;
EOSQL
)
    fi

    # [CHANGED] heredoc is now unquoted (EOF, was 'EOF') so thresholds from
    # CONFIG expand inside the SQL. Side effect: every \$ in a view name is
    # escaped as \$, e.g. GV\$DATABASE.
    # [CHANGED] each check is now its own statement. In v1 one UNION ALL meant
    # a single failing query killed every DB row.
    # [ADDED] -L: try the login once and exit instead of re-prompting.
    # [ADDED] timeout: a hung DB can no longer hang the script.
    #~ out_sql=$(sqlplus -s / as sysdba << 'EOF'
    out=$(timeout "$SQL_TIMEOUT" sqlplus -s -L / as sysdba <<EOF 2>&1
SET TRIMSPOOL ON
SET TRIMOUT ON
SET VERIFY OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SET HEADING OFF
SET TAB OFF
SET DEFINE OFF
SET SQLBLANKLINES ON
SET LINESIZE 1000
--~ SET LINESIZE 500                      [CHANGED] 1000 stops long rows wrapping
-- Output format for every row:  SECTION|KEY|VALUE|STATUS
-- [CHANGED] v1 started rows with '| ' and spread them over 4-5 columns.

-- [ADDED] DB name, used in the summary and mail subject
SELECT 'META|DB_NAME|'||name||'|INFO' FROM v\$database;

-- DB STATUS: open mode
-- [FIXED] v1 checked only one instance (WHERE ROWNUM = 1). Now every instance.
--~ SELECT '| DB STATUS', '| OPEN_MODE', '| ' || OPEN_MODE, ... FROM GV\$DATABASE WHERE ROWNUM = 1
SELECT 'DB STATUS|OPEN_MODE inst '||inst_id||'|'||open_mode||'|'||CASE WHEN open_mode = 'READ WRITE' THEN 'OK' ELSE 'CRIT' END FROM gv\$database ORDER BY inst_id;

-- DB STATUS: log mode  [CHANGED] status words only. LOG_MODE is DB-wide, one row is right.
SELECT 'DB STATUS|LOG_MODE|'||log_mode||'|'||CASE WHEN log_mode = 'ARCHIVELOG' THEN 'OK' ELSE 'CRIT' END FROM v\$database;

-- INSTANCE STATUS: one row per running instance
-- [CHANGED] adds host name, uptime to 1 decimal, and WARN on a recent restart
SELECT 'INSTANCE STATUS|Instance '||inst_id||' ('||instance_name||' on '||host_name||')|'||status||', up '||TO_CHAR(ROUND(SYSDATE-startup_time,1),'FM9990.0')||' days|'||CASE WHEN status <> 'OPEN' THEN 'CRIT' WHEN SYSDATE-startup_time < $RESTART_WARN_DAYS THEN 'WARN' ELSE 'OK' END FROM gv\$instance ORDER BY inst_id;

-- [FIXED] a down instance returns NO row from GV\$INSTANCE, so v1 never showed
-- 'Not Running'. Count the open instances against the expected number.
SELECT 'INSTANCE STATUS|Instances OPEN|'||COUNT(*)||' of $EXPECTED_INSTANCES|'||CASE WHEN COUNT(*) < $EXPECTED_INSTANCES THEN 'CRIT' ELSE 'OK' END FROM gv\$instance WHERE status = 'OPEN';

-- TEMP TABLESPACE USAGE
-- [FIXED] v1 divided v\$temp_extent_pool.bytes_cached by file size.
--   bytes_cached = extents Oracle keeps after sorts finish, not space in use,
--   and v\$ = this instance only. It sits near its high-water mark, which is
--   why v1 showed the same 92.88% two hours apart.
--   Now: used blocks from gv\$sort_segment (all instances) against max size
--   including autoextend.
--~ ... SUM(bytes_cached) bytes FROM v\$temp_extent_pool GROUP BY tablespace_name) t ...
SELECT 'TEMP USAGE|'||t.tablespace_name||'|Used='||TO_CHAR(ROUND(NVL(u.used_bytes,0)/t.max_bytes*100,2),'FM990.00')||'% of '||ROUND(t.max_bytes/1073741824,1)||'G|'||CASE WHEN NVL(u.used_bytes,0)/t.max_bytes*100 > $TEMP_CRIT THEN 'CRIT' WHEN NVL(u.used_bytes,0)/t.max_bytes*100 > $TEMP_WARN THEN 'WARN' ELSE 'OK' END
FROM (SELECT tablespace_name, SUM(CASE WHEN autoextensible = 'YES' THEN GREATEST(bytes,maxbytes) ELSE bytes END) max_bytes FROM dba_temp_files GROUP BY tablespace_name) t
LEFT JOIN (SELECT ss.tablespace_name, SUM(ss.used_blocks*ts.block_size) used_bytes FROM gv\$sort_segment ss JOIN dba_tablespaces ts ON ts.tablespace_name = ss.tablespace_name GROUP BY ss.tablespace_name) u
ON u.tablespace_name = t.tablespace_name WHERE t.max_bytes > 0;

-- [ADDED] Top TEMP consumer, so a WARN/CRIT row comes with a name to chase
SELECT 'TEMP USAGE|Top consumer|'||s.username||' sid '||s.sid||' inst '||s.inst_id||': '||ROUND(u.blocks*t.block_size/1048576)||'M, sql_id '||NVL(u.sql_id,'-')||'|INFO' FROM gv\$tempseg_usage u JOIN gv\$session s ON s.inst_id = u.inst_id AND s.saddr = u.session_addr AND s.serial# = u.session_num JOIN dba_tablespaces t ON t.tablespace_name = u.tablespace ORDER BY u.blocks DESC FETCH FIRST 1 ROWS ONLY;

-- [ADDED] Permanent tablespaces: top 5 by % of max size (autoextend aware).
-- UNDO excluded on purpose: it fills and recycles by design.
SELECT 'TABLESPACE USAGE|'||m.tablespace_name||'|Used='||TO_CHAR(ROUND(m.used_percent,2),'FM990.00')||'% of max|'||CASE WHEN m.used_percent > $TS_CRIT THEN 'CRIT' WHEN m.used_percent > $TS_WARN THEN 'WARN' ELSE 'OK' END FROM dba_tablespace_usage_metrics m JOIN dba_tablespaces t ON t.tablespace_name = m.tablespace_name WHERE t.contents = 'PERMANENT' ORDER BY m.used_percent DESC FETCH FIRST 5 ROWS ONLY;

-- SESSION COUNT for APP_USER
-- [FIXED] v1 grouped existing sessions, so with zero ACTIVE sessions no
-- ACTIVE row existed and 'No Active Session' could never print. Now every
-- instance x {ACTIVE, INACTIVE} pair always produces a row.
-- [CHANGED] KILLED/SNIPED no longer fall into "High Session".
-- [CHANGED] "High Session" -> WARN.
--~ SELECT ... FROM GV\$SESSION WHERE USERNAME = 'APPSCHEMA' GROUP BY STATUS, INST_ID
SELECT 'SESSION COUNT|Inst '||i.inst_id||' '||st.s||'|'||NVL(c.cnt,0)||'|'||CASE WHEN st.s = 'ACTIVE' AND NVL(c.cnt,0) = 0 THEN 'WARN' WHEN st.s = 'ACTIVE' AND c.cnt > $ACTIVE_MAX THEN 'WARN' WHEN st.s = 'INACTIVE' AND NVL(c.cnt,0) > $INACTIVE_MAX THEN 'WARN' ELSE 'OK' END
FROM gv\$instance i CROSS JOIN (SELECT 'ACTIVE' s FROM dual UNION ALL SELECT 'INACTIVE' FROM dual) st
LEFT JOIN (SELECT inst_id, status, COUNT(*) cnt FROM gv\$session WHERE username = '$APP_USER' GROUP BY inst_id, status) c ON c.inst_id = i.inst_id AND c.status = st.s
ORDER BY i.inst_id, st.s;

-- [ADDED] processes / sessions against their init.ora limits
SELECT 'SESSION LIMIT|Inst '||inst_id||' '||resource_name||'|'||current_utilization||' of '||TRIM(limit_value)||'|'||CASE WHEN current_utilization > TO_NUMBER(TRIM(limit_value))*$LIMIT_CRIT/100 THEN 'CRIT' WHEN current_utilization > TO_NUMBER(TRIM(limit_value))*$LIMIT_WARN/100 THEN 'WARN' ELSE 'OK' END FROM gv\$resource_limit WHERE resource_name IN ('processes','sessions') AND TRIM(limit_value) <> 'UNLIMITED' ORDER BY inst_id, resource_name;

-- [ADDED] Sessions blocked longer than BLOCK_SECS
SELECT 'BLOCKING|Sessions blocked > ${BLOCK_SECS}s|'||COUNT(*)||'|'||CASE WHEN COUNT(*) > 0 THEN 'WARN' ELSE 'OK' END FROM gv\$session WHERE blocking_session IS NOT NULL AND seconds_in_wait > $BLOCK_SECS;

-- [ADDED] User calls active longer than LONG_QUERY_SECS
SELECT 'LONG CALLS|Active calls > ${LONG_QUERY_SECS}s|'||COUNT(*)||'|'||CASE WHEN COUNT(*) > 0 THEN 'WARN' ELSE 'OK' END FROM gv\$session WHERE type = 'USER' AND status = 'ACTIVE' AND username IS NOT NULL AND username NOT IN ($LONG_QUERY_EXCLUDE) AND last_call_et > $LONG_QUERY_SECS;

-- [ADDED] Archive destinations. An ERROR or DEFERRED standby destination
-- means redo has stopped shipping, even if the sequence gap still looks small.
SELECT 'ARCHIVE DEST|Dest '||dest_id||' -> '||destination||'|'||status||CASE WHEN error IS NOT NULL THEN ': '||REPLACE(error,'|','/') END||'|'||CASE WHEN status = 'VALID' THEN 'OK' ELSE 'CRIT' END FROM v\$archive_dest WHERE status <> 'INACTIVE' AND destination IS NOT NULL ORDER BY dest_id;

-- [CHANGED v2.1] DB SYNC STATUS moved to \$sql_dg above (CHECK_DG toggle)
$sql_dg

-- [ADDED] Fast Recovery Area, net of reclaimable space.
-- In ARCHIVELOG mode a full FRA stops the database.
SELECT 'FRA USAGE|'||name||'|Used='||TO_CHAR(ROUND((space_used-space_reclaimable)/space_limit*100,2),'FM990.00')||'% of '||ROUND(space_limit/1073741824)||'G|'||CASE WHEN (space_used-space_reclaimable)/space_limit*100 > $FRA_CRIT THEN 'CRIT' WHEN (space_used-space_reclaimable)/space_limit*100 > $FRA_WARN THEN 'WARN' ELSE 'OK' END FROM v\$recovery_file_dest WHERE space_limit > 0;
SELECT 'FRA USAGE|FRA|not configured; archive space covered by ASM/filesystem rows|INFO' FROM dual WHERE NOT EXISTS (SELECT 1 FROM v\$recovery_file_dest WHERE space_limit > 0);

-- [ADDED] ASM diskgroups. _stat view skips disk discovery, so it is cheap.
-- usable_file_mb < 0 means a disk failure could not be fully re-mirrored.
SELECT 'ASM DISKGROUP|'||name||'|Used='||TO_CHAR(ROUND((1-free_mb/total_mb)*100,2),'FM990.00')||'%, usable free '||ROUND(usable_file_mb/1024)||'G|'||CASE WHEN usable_file_mb < 0 OR (1-free_mb/total_mb)*100 > $ASM_CRIT THEN 'CRIT' WHEN (1-free_mb/total_mb)*100 > $ASM_WARN THEN 'WARN' ELSE 'OK' END FROM v\$asm_diskgroup_stat WHERE total_mb > 0 ORDER BY name;

$sql_rman
$sql_alert
EXIT;
EOF
)
    rc=$?
    DB_NAME="?"

    # [FIXED] v1 piped everything through awk -F'|' 'NF > 1 {...}'. Error
    # lines contain no '|', so ORA-01034 etc. disappeared without a trace.
    # Now: valid rows are stored, error lines become CRIT rows.
    #~ (echo "$out_sql"; echo "$line1"; echo "$line2") | awk -F'|' ' NF > 1 { ... }'
    while IFS= read -r line; do
        [ -z "$(trim "$line")" ] && continue
        if [[ "$line" =~ $re ]]; then
            if [ "${BASH_REMATCH[1]}" = META ]; then DB_NAME="${BASH_REMATCH[3]}"; continue; fi
            add "${BASH_REMATCH[1]}" "$(trim "${BASH_REMATCH[2]}")" "$(trim "${BASH_REMATCH[3]}")" "${BASH_REMATCH[4]}"
            got=1
        elif [[ "$line" =~ ^ERROR\ at\ line ]]; then
            continue                # the ORA- line that follows carries the detail
        elif [[ "$line" =~ (ORA-|SP2-|ERROR) ]]; then
            add "DB QUERY" "sqlplus error" "$(trim "$line")" "CRIT"
        fi
    done <<< "$out"

    if [ "$rc" -eq 124 ]; then
        add "DB QUERY" "sqlplus" "timed out after ${SQL_TIMEOUT}s" "CRIT"
    elif [ "$got" -eq 0 ]; then
        add "DB QUERY" "sqlplus" "no rows returned (rc=$rc); database may be down" "CRIT"
    fi
    # [ADDED v2.1] say so when the Data Guard check was switched off
    [ "$CHECK_DG" = 1 ] || add "DB SYNC STATUS" "Data Guard" "check disabled (CHECK_DG=0)" "INFO"
}

#========================== 2. CLUSTERWARE ===================================
# [ADDED] Any resource whose TARGET is ONLINE but STATE is not.
# Covers instances, listeners, SCAN, VIPs, ASM, diskgroups in one pass.
check_crs() {
    local crsctl="$GRID_HOME/bin/crsctl" out rc bad r s rest st
    if [ ! -x "$crsctl" ]; then
        add "CLUSTERWARE" "crsctl" "not found at $crsctl; set GRID_HOME" "WARN"; return
    fi
    #~ out=$(timeout 60 "$crsctl" stat res -t 2>&1); rc=$?
    out=$(timeout "$CRS_TIMEOUT" "$crsctl" stat res -t 2>&1); rc=$?     # [CHANGED v2.1]
    if [ "$rc" -ne 0 ]; then
        add "CLUSTERWARE" "crsctl stat res -t" "failed rc=$rc" "CRIT"; return
    fi
    bad=$(awk '
        /^-+$/ || /^Name / || /^Local Resources/ || /^Cluster Resources/ { next }
        /^[^ \t]/ { res=$1; next }
        {
            t=""; s=""; rest=""
            for (i=1; i<=NF; i++) {
                if ($i ~ /^(ONLINE|OFFLINE|INTERMEDIATE|UNKNOWN)$/ && s == "") {
                    if (t == "") t=$i; else { s=$i; for (j=i+1; j<=NF; j++) rest=rest" "$j }
                }
            }
            if (t == "ONLINE" && s != "" && s != "ONLINE") print res, s, rest
        }' <<< "$out")
    if [ -z "$bad" ]; then
        add "CLUSTERWARE" "Resources with TARGET=ONLINE" "all ONLINE" "OK"
    else
        while read -r r s rest; do
            if [ "$s" = OFFLINE ]; then st=CRIT; else st=WARN; fi
            add "CLUSTERWARE" "$r" "target ONLINE, state $s $(trim "$rest")" "$st"
        done <<< "$bad"
    fi
}

#=========================== 3. OS + FILESYSTEMS ==============================
# [CHANGED] one function runs locally for node 1 and over a single ssh for
# node 2. v1 used three separate ssh calls for node 2.
os_collect() {
    local cpu mem swap load cores
    # [CHANGED] 3 x 1s samples (was 1 x 1s); LC_ALL=C keeps the "Average:" label in English
    #~ u1=$(sar -u 1 1 | awk '/Average:/ {print 100 - $NF}')
    cpu=$(LC_ALL=C sar -u 1 3 2>/dev/null | awk '/^Average/ {printf "%.2f", 100 - $NF}')
    # [CHANGED] (total - available) / total. v1 used used/total.
    #~ m1=$(free -m | awk '/^Mem/ {printf("%.2f%\n", $3/$2*100)}')
    mem=$(LC_ALL=C free -m | awk '/^Mem:/ { if ($2 > 0) printf "%.2f", ($2-$7)/$2*100 }')
    # [ADDED] swap, load, cores
    swap=$(LC_ALL=C free -m | awk '/^Swap:/ { if ($2 > 0) printf "%.2f", $3/$2*100; else print "0.00" }')
    load=$(cut -d' ' -f1 /proc/loadavg)
    cores=$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN)
    echo "OS|$cpu|$mem|$swap|$load|$cores"
    # [ADDED] local filesystems only (-l). Skipping NFS also avoids hangs on a dead mount.
    df -P -l -x tmpfs -x devtmpfs -x squashfs -x iso9660 2>/dev/null |
        awk 'NR > 1 { gsub("%", "", $5); print "FS|" $6 "|" $5 }'
}

process_os() {
    local node="$1" out="$2" rc="${3:-0}" line cpu mem swap load cores lpc
    local s_cpu s_mem s_swap s_load why="" st tag mnt pct fs_st
    local fs_count=0 fs_max=0 fs_max_mnt=""

    line=$(grep '^OS|' <<< "$out" | head -1)
    # [FIXED] v1: "If node2 is down, set defaults to avoid awk errors"
    #   u2=${u2:-0}; m2=${m2:-0}  ->  CPU 0%, Mem 0, status "Normal".
    #   A dead node looked healthy. Now: no data = CRIT.
    #~ u2=${u2:-0}; m2=${m2:-0}
    if [ "$rc" -ne 0 ] || [ -z "$line" ]; then
        add "OS UTILIZATION" "$node" "NO DATA (unreachable or command failed, rc=$rc)" "CRIT"
        add "FILESYSTEM" "$node" "NO DATA" "CRIT"
        return
    fi
    IFS='|' read -r _ cpu mem swap load cores <<< "$line"
    lpc=$(awk -v l="$load" -v c="$cores" 'BEGIN { if (c > 0) printf "%.2f", l/c }')

    # [CHANGED] v1: single High/Normal from (u > 60 || m > 75).
    # Now each metric rated WARN/CRIT, row shows which one tripped.
    #~ s1=$(awk -v u="$u1" -v m="$m1" 'BEGIN {if (u > 60 || m > 75) print "High"; else print "Normal"}')
    s_cpu=$(rate "$cpu"  "$CPU_WARN"  "$CPU_CRIT")
    s_mem=$(rate "$mem"  "$MEM_WARN"  "$MEM_CRIT")
    s_swap=$(rate "$swap" "$SWAP_WARN" "$SWAP_CRIT")
    s_load=$(rate "$lpc"  "$LOAD_WARN" "$LOAD_CRIT")
    [ "$s_cpu"  != OK ] && why+=" CPU"
    [ "$s_mem"  != OK ] && why+=" Mem"
    [ "$s_swap" != OK ] && why+=" Swap"
    [ "$s_load" != OK ] && why+=" Load"
    st=$(worst "$s_cpu" "$s_mem" "$s_swap" "$s_load")
    add "OS UTILIZATION" "$node" \
        "CPU: ${cpu:-?}% Mem: ${mem:-?}% Swap: ${swap:-?}% Load/core: ${lpc:-?}${why:+ (flagged:$why)}" "$st"

    # [ADDED] filesystems: list only mounts over WARN, plus one summary row
    while IFS='|' read -r tag mnt pct; do
        [ "$tag" = FS ] || continue
        [[ "$pct" =~ ^[0-9]+$ ]] || continue
        fs_count=$((fs_count + 1))
        if [ "$pct" -gt "$fs_max" ]; then fs_max=$pct; fs_max_mnt=$mnt; fi
        fs_st=$(rate "$pct" "$FS_WARN" "$FS_CRIT")
        [ "$fs_st" != OK ] && add "FILESYSTEM" "$node $mnt" "Used=${pct}%" "$fs_st"
    done <<< "$out"
    if [ "$fs_count" -eq 0 ]; then
        add "FILESYSTEM" "$node" "no filesystems read" "WARN"
    else
        add "FILESYSTEM" "$node" "$fs_count checked, highest ${fs_max}% on $fs_max_mnt" \
            "$(rate "$fs_max" "$FS_WARN" "$FS_CRIT")"
    fi
}

check_os() {
    local out rc
    # Node 1 (local)
    process_os "Node 1" "$(os_collect)" 0

    # Node 2 (remote)
    # [CHANGED] one ssh, wrapped in timeout. The function definition is sent
    # over stdin, so node 2 needs no copy of this script.
    #~ u2=$(ssh -q -p 22 CHANGE_ME_NODE2_IP "sar -u 1 1" | awk '/Average:/ {print 100 - $NF}')
    #~ m2=$(ssh -q -p 22 CHANGE_ME_NODE2_IP "free -m | awk ...")
    # [REMOVED] dead code: #m1=$(sar -r 1 1 ...) and #m2=$(ssh ... "sar -r 1 1" ...)
    out=$(timeout "$SSH_TIMEOUT" ssh "${SSH_OPTS[@]}" -p "$NODE2_PORT" "$NODE2_HOST" "bash -s" \
          <<< "$(declare -f os_collect); os_collect" 2>/dev/null)
    rc=$?
    process_os "Node 2" "$out" "$rc"
}

#============================== 4. GOLDENGATE =================================
# [CHANGED] v1 printed gg2.sh output as-is, with no thresholds and no
# failure handling. Now parsed: status, lag and checkpoint age are rated.
# Expects gg2.sh lines like:
#   "X_EXTRACT1","RUNNING","2026-09-20 15:37","00:00:04","2026-10-02 23:51:09","18.25 (798...)"
# NOTE gg2.sh reports extracts only. Manager, pumps and replicats are not
# covered until gg2.sh is extended ("info all" in ggsci).
#~ echo -e "=====,=====,Oracle_GoldenGate,=====,====="
#~ ssh -q -p 22 CHANGE_ME_GG_IP "sh /home/oracle/scripts/gg2.sh"
check_gg() {
    local out rc line name status started lag ckpt scn lag_s ck_epoch age st found=0
    out=$(timeout "$SSH_TIMEOUT" ssh "${SSH_OPTS[@]}" -p "$GG_PORT" "$GG_HOST" "sh $GG_SCRIPT" 2>&1)
    rc=$?
    if [ "$rc" -ne 0 ] || [ -z "$(trim "$out")" ]; then
        add "GOLDENGATE" "$GG_HOST" "no output (unreachable or gg2.sh failed, rc=$rc)" "CRIT"; return
    fi
    while IFS= read -r line; do
        line=$(trim "${line//\"/}")
        [ -z "$line" ] && continue
        case "$line" in Extract_Name*|*Last_Started*) continue ;; esac
        IFS=',' read -r name status started lag ckpt scn <<< "$line"
        name=$(trim "$name"); status=$(trim "$status"); started=$(trim "$started")
        lag=$(trim "$lag");   ckpt=$(trim "$ckpt");     scn=$(trim "$scn")
        if [ -z "$status" ] || [ -z "$lag" ]; then
            add "GOLDENGATE" "unparsed line" "$line" "WARN"; continue
        fi
        found=1
        lag_s=$(awk -F: '{ print $1*3600 + $2*60 + $3 }' <<< "$lag")
        ck_epoch=$(date -d "$ckpt" +%s 2>/dev/null)
        if [ -n "$ck_epoch" ]; then age=$(( ( $(date +%s) - ck_epoch ) / 60 )); else age=""; fi
        st=OK; [ "$status" != RUNNING ] && st=CRIT
        st=$(worst "$st" "$(rate "$lag_s" "$GG_LAG_WARN" "$GG_LAG_CRIT")" \
                         "$(rate "$age" "$GG_CKPT_WARN_MIN" "$GG_CKPT_CRIT_MIN")")
        add "GOLDENGATE" "$name" \
            "$status, lag $lag, checkpoint $ckpt (${age:-?}m ago), started $started, SCN $scn" "$st"
    done <<< "$out"
    [ "$found" -eq 0 ] && add "GOLDENGATE" "Extracts" "no extract rows in gg2.sh output" "CRIT"
}

#========================= 5. STATIC INPUT FILES ===============================
# [ADDED] freshness check shared by both files below.
# Returns 1 (and adds a CRIT row) if the file is missing or stale.
fresh_or_flag() {
    local section="$1" file="$2" age
    if ! age=$(file_age_min "$file"); then
        add "$section" "$file" "file missing" "CRIT"; return 1
    fi
    if [ "$age" -gt "$STALE_MIN" ]; then
        add "$section" "$file" "STALE: last updated ${age}m ago; producer job may have stopped" "CRIT"
        return 1
    fi
    return 0
}

# SFTP log
# [CHANGED] v1 did "cat /home/oracle/sftp_output" and trusted it blindly.
#~ echo -e "=====,=====,SFTP_LOG,=====,====="
#~ cat /home/oracle/sftp_output
# Expects:  /var/log/sftp.log , Oct 2 23:50 , 1003M , Normal
check_sftp() {
    local line path mod size status st
    fresh_or_flag "SFTP LOG" "$SFTP_FILE" || return
    while IFS= read -r line; do
        [ -z "$(trim "$line")" ] && continue
        case "$(trim "$line")" in PATH*) continue ;; esac
        IFS=',' read -r path mod size status <<< "$line"
        path=$(trim "$path"); mod=$(trim "$mod"); size=$(trim "$size"); status=$(trim "$status")
        if [ -z "$size" ]; then add "SFTP LOG" "unparsed line" "$(trim "$line")" "WARN"; continue; fi
        st=OK; [ "${status,,}" != normal ] && st=WARN
        # [ADDED] own size threshold; the producer's threshold is unknown
        st=$(worst "$st" "$(rate "$(to_mb "$size")" "$SFTP_LOG_WARN_MB" 999999999)")
        add "SFTP LOG" "$path" "size $size, modified $mod, producer says: $status" "$st"
    done < "$SFTP_FILE"
}

# Active sessions (separate script)
# [CHANGED] wrapped in timeout and parsed instead of printed raw.
#~ echo -e "=====,=====,Active_Sessions,=====,====="
#~ sh /home/oracle/scripts/activesession.sh
# Expects data line: 02Oct2026 ,2151 - 2351 ,2331 --> 20 rows ,NORMAL ,2200 --> 6 rows ,NORMAL
check_activesessions() {
    local out rc line win hi s1 lo s2 st found=0
    #~ out=$(timeout 120 sh "$ACTIVESESSION_SCRIPT" 2>&1); rc=$?
    out=$(timeout "$ACTIVESESSION_TIMEOUT" sh "$ACTIVESESSION_SCRIPT" 2>&1); rc=$?   # [CHANGED v2.1]
    if [ "$rc" -ne 0 ]; then
        add "ACTIVE SESSIONS" "activesession.sh" "failed or timed out (rc=$rc)" "CRIT"; return
    fi
    while IFS= read -r line; do
        [ -z "$(trim "$line")" ] && continue
        case "$(trim "$line")" in Date*) continue ;; esac
        IFS=',' read -r _ win hi s1 lo s2 <<< "$line"   # [CHANGED v2.1] unused date -> _ (shellcheck)
        s1=$(trim "$s1"); s2=$(trim "$s2")
        if [ -z "$s1" ]; then add "ACTIVE SESSIONS" "unparsed line" "$(trim "$line")" "WARN"; continue; fi
        found=1
        st=OK; { [ "${s1^^}" != NORMAL ] || { [ -n "$s2" ] && [ "${s2^^}" != NORMAL ]; }; } && st=WARN
        add "ACTIVE SESSIONS" "Last 2h ($(trim "$win"))" \
            "highest $(trim "$hi") [$s1], lowest $(trim "$lo") [${s2:-?}]" "$st"
    done <<< "$out"
    [ "$found" -eq 0 ] && add "ACTIVE SESSIONS" "activesession.sh" "no data rows" "WARN"
}

# Application servers
# [CHANGED] v1 did "cat /home/oracle/server_checklist".
#~ echo -e "=====,=====,Application Server Status,=====,====="
#~ cat /home/oracle/server_checklist
# Expects: 9 ,9 ,0 ,All Application servers are accessible!
# NOTE the "Inaccessble" typo lives in the producer of server_checklist,
# not in this script. Ideally the producer also lists failed servers by name.
check_appservers() {
    local line total acc inacc st found=0
    fresh_or_flag "APP SERVERS" "$SERVER_FILE" || return
    while IFS= read -r line; do
        [ -z "$(trim "$line")" ] && continue
        case "$(trim "$line")" in Total*) continue ;; esac
        IFS=',' read -r total acc inacc _ <<< "$line"   # [CHANGED v2.1] unused message -> _ (shellcheck)
        total=$(trim "$total"); acc=$(trim "$acc"); inacc=$(trim "$inacc")
        if ! [[ "$total" =~ ^[0-9]+$ && "$acc" =~ ^[0-9]+$ ]]; then
            add "APP SERVERS" "unparsed line" "$(trim "$line")" "WARN"; continue
        fi
        found=1
        st=OK; { [ "$acc" -lt "$total" ] || [ "${inacc:-0}" != 0 ]; } && st=CRIT
        add "APP SERVERS" "Accessible" "$acc of $total, inaccessible ${inacc:-?}" "$st"
    done < "$SERVER_FILE"
    [ "$found" -eq 0 ] && add "APP SERVERS" "$SERVER_FILE" "no data rows" "WARN"
}

#=============================== OUTPUT =======================================
summarise() {
    local s c=0 w=0 o=0
    for s in "${R_STATUS[@]}"; do
        case "$s" in CRIT) c=$((c+1)) ;; WARN) w=$((w+1)) ;; OK) o=$((o+1)) ;; esac
    done
    OVERALL=OK; [ "$w" -gt 0 ] && OVERALL=WARN; [ "$c" -gt 0 ] && OVERALL=CRIT
    SUMMARY="CRIT=$c WARN=$w OK=$o"
}

# [FIXED] v1 joined fields with "," without quoting, so a value containing a
# comma pushed later fields into the wrong columns.
csv() {
    local f="$1"
    if [[ "$f" == *[,\"]* ]]; then f="\"${f//\"/\"\"}\""; fi
    printf '%s' "$f"
}

print_csv() {
    local i
    echo "SECTION,DETAIL_KEY,VALUE,DESCRIPTION"      # v1 header kept; DESCRIPTION now holds the status
    echo "SUMMARY,$(csv "$HOST / $DB_NAME / $RUN_TS"),$SUMMARY,$OVERALL"   # [ADDED]
    for i in "${!R_SECTION[@]}"; do
        printf '%s,%s,%s,%s\n' "$(csv "${R_SECTION[$i]}")" "$(csv "${R_KEY[$i]}")" \
            "$(csv "${R_VALUE[$i]}")" "${R_STATUS[$i]}"
    done
}

print_table() {                                       # [ADDED]
    local i
    {
        printf 'SECTION\tKEY\tVALUE\tSTATUS\n'
        printf 'SUMMARY\t%s\t%s\t%s\n' "$HOST / $DB_NAME / $RUN_TS" "$SUMMARY" "$OVERALL"
        for i in "${!R_SECTION[@]}"; do
            printf '%s\t%s\t%s\t%s\n' "${R_SECTION[$i]}" "${R_KEY[$i]}" "${R_VALUE[$i]}" "${R_STATUS[$i]}"
        done
    } | if command -v column >/dev/null; then column -t -s $'\t'; else cat; fi
}

html_escape() { local s="$1"; s=${s//&/&amp;}; s=${s//</&lt;}; s=${s//>/&gt;}; printf '%s' "$s"; }
status_color() {
    case "$1" in CRIT) echo "#ffc7ce" ;; WARN) echo "#ffeb9c" ;; OK) echo "#c6efce" ;; *) echo "#ffffff" ;; esac
}

# [ADDED] HTML built by the script. Replaces the manual CSV -> Excel -> Outlook
# paste that produced the misaligned table in the current mail.
build_html() {
    local i td='style="border:1px solid #999;padding:3px 6px"' issues=""
    for i in "${!R_SECTION[@]}"; do
        case "${R_STATUS[$i]}" in CRIT|WARN)
            issues+="<li><b>${R_STATUS[$i]}</b> $(html_escape "${R_SECTION[$i]} / ${R_KEY[$i]}: ${R_VALUE[$i]}")</li>" ;;
        esac
    done
    echo '<html><body style="font-family:Calibri,Arial,sans-serif;font-size:11pt">'
    echo '<p>Dear Team,</p>'
    echo "<p><b>Overall: <span style=\"background:$(status_color "$OVERALL");padding:2px 8px\">$OVERALL</span></b>"
    echo "&nbsp; $SUMMARY<br>Host: $HOST &nbsp; DB: $(html_escape "$DB_NAME") &nbsp; Run: $RUN_TS</p>"
    [ -n "$issues" ] && echo "<p><b>Needs attention</b></p><ul>$issues</ul>"
    echo '<table style="border-collapse:collapse;font-size:10pt">'
    echo "<tr style=\"background:#d9d9d9\"><th $td>Section</th><th $td>Check</th><th $td>Value</th><th $td>Status</th></tr>"
    for i in "${!R_SECTION[@]}"; do
        echo "<tr><td $td>$(html_escape "${R_SECTION[$i]}")</td><td $td>$(html_escape "${R_KEY[$i]}")</td><td $td>$(html_escape "${R_VALUE[$i]}")</td><td style=\"border:1px solid #999;padding:3px 6px;background:$(status_color "${R_STATUS[$i]}")\">${R_STATUS[$i]}</td></tr>"
    done
    echo '</table><p style="color:#777;font-size:9pt">Generated by checklist.sh v2</p></body></html>'
}

# [ADDED] Sends through the server's local MTA, which must relay to the
# internal Exchange/SMTP server. Recipients receive it in Outlook as normal.
send_mail() {
    local sm=/usr/sbin/sendmail subject
    if [ -z "$MAIL_TO" ]; then echo "MAIL_TO is empty in CONFIG; mail not sent" >&2; return 1; fi
    if [ ! -x "$sm" ]; then echo "$sm not found; mail not sent" >&2; return 1; fi
    subject="[$OVERALL] Monitoring Checklist | $SUBJECT_TAG | $(date +%d-%m-%Y) | $(date +%H:%M)"
    {
        [ -n "$MAIL_FROM" ] && echo "From: $MAIL_FROM"
        echo "To: $MAIL_TO"
        [ -n "$MAIL_CC" ] && echo "Cc: $MAIL_CC"
        echo "Subject: $subject"
        echo "MIME-Version: 1.0"
        echo "Content-Type: text/html; charset=UTF-8"
        echo
        build_html
    } | "$sm" -t -oi
    local rc=$?
    # rc 0 = handed to the local MTA, not proof of delivery. Check /var/log/maillog.
    if [ "$rc" -eq 0 ]; then echo "Mail queued to: $MAIL_TO" >&2; else echo "sendmail failed rc=$rc" >&2; fi
    return "$rc"
}

# [ADDED] One key=value line per check per run. Gives trend history now,
# and a Splunk forwarder can ingest the directory later with no changes.
write_history() {
    local f i v
    mkdir -p "$LOG_DIR" 2>/dev/null || return
    f="$LOG_DIR/checklist_$(date +%Y%m%d).log"
    for i in "${!R_SECTION[@]}"; do
        v=${R_VALUE[$i]//\"/\'}
        printf 'ts="%s" host=%s db=%s section="%s" key="%s" value="%s" status=%s\n' \
            "$RUN_TS" "$HOST" "$DB_NAME" "${R_SECTION[$i]}" "${R_KEY[$i]}" "$v" "${R_STATUS[$i]}" >> "$f"
    done
    printf 'ts="%s" host=%s db=%s section="SUMMARY" key="overall" value="%s" status=%s\n' \
        "$RUN_TS" "$HOST" "$DB_NAME" "$SUMMARY" "$OVERALL" >> "$f"
    find "$LOG_DIR" -name 'checklist_*.log' -mtime +"$LOG_RETENTION_DAYS" -delete 2>/dev/null
}

#================================ MAIN ========================================
MODE=csv; SEND_MAIL=0; NO_HISTORY=0
for arg in "$@"; do
    case "$arg" in
        --table)          MODE=table ;;
        --html)           MODE=html ;;
        --mail)           SEND_MAIL=1 ;;
        --mail-if-issues) SEND_MAIL=2 ;;
        #~ --no-history)     WRITE_HISTORY=0 ;;
        --no-history)     NO_HISTORY=1 ;;                  # [CHANGED v2.1] applied after config.env
        #~ -h|--help)        sed -n '2,30p' "$0"; exit 0 ;;
        -h|--help)        sed -n '2,/^# CHANGELOG v1/p' "$0" | sed '$d'; exit 0 ;;   # [CHANGED v2.1]
        *) echo "Unknown option: $arg (try --help)" >&2; exit 64 ;;
    esac
done

# [ADDED v2.1] read config.env, then fill the values derived from it
load_config
[ "$NO_HISTORY" = 1 ] && WRITE_HISTORY=0
GG_SCRIPT="${GG_SCRIPT:-$SCRIPTS_DIR/gg2.sh}"
ACTIVESESSION_SCRIPT="${ACTIVESESSION_SCRIPT:-$SCRIPTS_DIR/activesession.sh}"
if [ -z "$GRID_HOME" ]; then
    GRID_HOME="$(awk -F= '/^crs_home/{print $2}' /etc/oracle/olr.loc 2>/dev/null)"
    GRID_HOME="${GRID_HOME:-/u01/app/19.0.0/grid}"
fi

# [ADDED] Lock: a second copy exits instead of stacking up behind a hung ssh.
exec 9>"/tmp/checklist_$(id -un).lock"
if command -v flock >/dev/null && ! flock -n 9; then
    echo "checklist.sh is already running" >&2; exit 3
fi

HOST=$(hostname -s)
RUN_TS=$(date '+%d-%m-%Y %H:%M:%S')

# [ADDED v2.1] first row: which configuration this run used
if [ "$CONFIG_STATE" = loaded ]; then
    add "CONFIG" "config.env" "loaded from $CONFIG_FILE" "INFO"
else
    add "CONFIG" "config.env" "not found in $SCRIPT_DIR; built-in defaults used" "WARN"
fi

check_db
check_crs
check_os
#~ check_gg
# [ADDED v2.1] CHECK_GG=0 for clusters with no GoldenGate
if [ "$CHECK_GG" = 1 ]; then
    check_gg
else
    add "GOLDENGATE" "GoldenGate" "check disabled (CHECK_GG=0)" "INFO"
fi
check_sftp
check_activesessions
check_appservers

summarise
case "$MODE" in
    csv)   print_csv ;;
    table) print_table ;;
    html)  build_html ;;
esac

[ "$WRITE_HISTORY" = 1 ] && write_history
if [ "$SEND_MAIL" = 1 ] || { [ "$SEND_MAIL" = 2 ] && [ "$OVERALL" != OK ]; }; then
    send_mail
fi

exit "$(rank "$OVERALL")"
