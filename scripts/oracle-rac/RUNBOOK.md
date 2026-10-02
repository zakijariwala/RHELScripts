# RUNBOOK: Oracle RAC scripts

One entry per row any script in `scripts/oracle-rac/` can print. Find the
row by its SECTION (first column), then its KEY (second column). Each
entry names the script that prints it.

Each entry says what the row means, how the script measured it, and what
to do at WARN and CRIT. Thresholds appear by their `config.env` key with
the default in brackets, for example `TEMP_WARN` (75).

## How to act on a row

- **CRIT**: act now. Follow the CRIT steps below. If they say "call the
  on-call DBA", phone them; do not wait for mail.
- **WARN**: look today. Follow the WARN steps. If the row is still WARN at
  the next run and you do not know why, tell the DBA team.
- **OK**: nothing to do.
- **INFO**: a fact with no limit. Nothing to do.

Every command on this page reads only. Run them as **oracle** on **node 1**
unless the entry says otherwise. Type them; do not paste. Fixing the cause (adding space, killing a
session, restarting a service) belongs to the DBA or Linux team under their
procedures, not to this runbook.

When you report a row to anyone, give the whole row and the SUMMARY row,
which is the last row and names host, script, version and run time.

The SQL commands below use this form; copy the whole line:

```
sqlplus -s / as sysdba <<< "SELECT ... FROM v\$something;"
```

## Contents

[SUMMARY](#summary) ·
[CONFIG and TEST](#config-and-test) ·
[DB QUERY](#db-query) ·
[DATABASE](#database) ·
[DB STATUS](#db-status) ·
[INSTANCE STATUS](#instance-status) ·
[TEMP USAGE](#temp-usage) ·
[TABLESPACE USAGE](#tablespace-usage) ·
[SESSION COUNT](#session-count) ·
[SESSION LIMIT](#session-limit) ·
[BLOCKING](#blocking) ·
[LONG CALLS](#long-calls) ·
[ARCHIVE DEST](#archive-dest) ·
[DB SYNC STATUS](#db-sync-status) ·
[FRA USAGE](#fra-usage) ·
[ASM DISKGROUP](#asm-diskgroup) ·
[RMAN BACKUP](#rman-backup) ·
[ALERT LOG](#alert-log) ·
[CLUSTERWARE](#clusterware) ·
[OS UTILIZATION](#os-utilization) ·
[FILESYSTEM](#filesystem) ·
[GOLDENGATE](#goldengate) ·
[SFTP LOG](#sftp-log) ·
[ACTIVE SESSIONS](#active-sessions) ·
[APP SERVERS](#app-servers)

---

## SUMMARY

Every script, last row.

| KEY | VALUE | STATUS |
|---|---|---|
| `racnode1 db-check 1.0.0 2026-10-02 19:30:01` (host, script, version, time) | `CRIT=0 WARN=2 OK=41` | worst status of all rows |

**Meaning.** Counts the rows by status. INFO rows are not counted. The
STATUS decides the exit code: OK 0, WARN 1, CRIT 2.

**Action.** Read every WARN and CRIT row above it.

## CONFIG and TEST

Every script, only with `--check-config`. These rows describe the setup;
no check ran.

| SECTION | KEY | VALUE | STATUS |
|---|---|---|---|
| CONFIG | a config key, for example `ORACLE_SID` | `DEMODB1 [detected]`, `[config]` or `[default]` | INFO |
| CONFIG | a config key | `DEMODB2 [MISMATCH, detected DEMODB1]` | WARN |
| CONFIG | `checks` | the checks a real run performs | INFO |
| TEST | what was tested, for example `ssh racnode2` | `login works` | OK |
| TEST | | `login failed`, `not found`, `missing or not readable` | CRIT |

**WARN (MISMATCH).** config.env says one value, the server another. The
script uses the config.env value. Trust the server: correct config.env,
and tell the senior which inventory row is wrong
([docs/config-from-inventory.md](../../docs/config-from-inventory.md)).

**CRIT (TEST).** The real run would fail. Fix what the row names before
asking for approval: the ssh login (passwordless ssh as oracle), a path in
config.env, or the instance name.

A config.env that the script cannot read gives no rows at all: the script
prints `NAME: config.env: ...` and stops with exit code 65. The message
names the key.

## DB QUERY

`db-check`, `space-check`, `dr-check`, `backup-check`. These rows appear
only when a database call failed. One of them means some database rows
are missing.

| KEY | VALUE | STATUS |
|---|---|---|
| `error` | an Oracle error line, for example `ORA-01034: ORACLE not available` | CRIT |
| `sqlplus` | `timed out` | CRIT |
| `sqlplus` | `cannot run sqlplus, rc=127` | CRIT |
| `sqlplus` | `no output, rc=N` | CRIT |
| `unparsed line` | a line sqlplus printed that the script cannot read | WARN |

**How measured.** Each group of queries runs in one `sqlplus -s -L / as
sysdba` call with a time limit of `SQL_TIMEOUT` (300) seconds. A line with
`ORA-` or `SP2-` becomes an `error` row.

**What to do:**

| Value contains | Meaning | Do this |
|---|---|---|
| `ORA-01034: ORACLE not available` | the instance on this node is down | Run `crs-check.sh`. Call the on-call DBA. |
| `ORA-01017` or `ORA-01031` | the oracle Linux user cannot log in as SYSDBA | Check you are oracle: `id` must list `dba`. Tell the DBA team. |
| `ORA-00942: table or view does not exist` | a view this database lacks (Oracle older than 12.2) | Report to the repo owner with the Oracle version. |
| `ORA-00904`, `ORA-00933`, `SP2-` | a query is broken, or a config value is wrong | Run `--check-config` and look for a strange value. Then report to the repo owner with the full output. |
| `timed out` | the database answered too slowly | Run `db-check.sh` and look at BLOCKING. Call the on-call DBA if the database is busy. |
| `cannot run sqlplus, rc=127` | sqlplus is not on the PATH | Become oracle with `sudo -iu oracle` (login shell), not `sudo -u oracle`. |
| `no output, rc=N` | sqlplus returned nothing | The database may be starting or stopping. Run again in 5 minutes. If it repeats, call the on-call DBA. |
| `unparsed line` | sqlplus printed something unexpected | Report the row to the repo owner. The other rows are still valid. |

## DATABASE

`db-check`.

| KEY | VALUE | STATUS |
|---|---|---|
| `name` | database name, for example `DEMODB` | INFO |

The name of the database the script connected to. Check it is the one you
meant.

## DB STATUS

`db-check`.

| KEY | VALUE | STATUS |
|---|---|---|
| `OPEN_MODE inst 1` (one row per running instance) | `READ WRITE` | OK |
| | `MOUNTED`, `READ ONLY` or anything else | CRIT |
| `LOG_MODE` | `ARCHIVELOG` | OK |
| | `NOARCHIVELOG` | CRIT |

**Meaning.** OPEN_MODE says whether users can read and write on that
instance. LOG_MODE says whether the database keeps [archive logs](../../docs/glossary.md#archive-log),
which backups and Data Guard depend on.

**How measured.** `gv$database.open_mode` per instance; `v$database.log_mode`.

**CRIT (OPEN_MODE).** Users cannot write on that instance. Call the on-call
DBA. Mention whether one or both instances show it.

**CRIT (LOG_MODE).** Point-in-time recovery and Data Guard have stopped
working. Call the on-call DBA. A production database never runs this way
on purpose.

## INSTANCE STATUS

`db-check`.

| KEY | VALUE | STATUS |
|---|---|---|
| `Instance 1 (DEMODB1 on racnode1)` (one per running instance) | `OPEN, up 41.3 days` | OK |
| | `OPEN, up 0.2 days` (less than `RESTART_WARN_DAYS` (1)) | WARN |
| | `MOUNTED, up ...` or any status other than OPEN | CRIT |
| `Instances OPEN` | `2 of 2` | OK |
| | `1 of 2` (fewer than `EXPECTED_INSTANCES` (2)) | CRIT |

**Meaning.** Which [instances](../../docs/glossary.md#instance) run, on
which host, and for how long. An instance that is down has no row of its
own; the `Instances OPEN` row catches it.

**How measured.** `gv$instance`: status and `startup_time`.

**WARN (recent restart).** The instance restarted within the last day.
Planned (patching, a change)? Then nothing to do; it clears tomorrow. Not
planned? Tell the DBA team today: an unplanned restart means a crash or an
eviction.

**CRIT (not OPEN, or `1 of 2`).** One node no longer serves the database.
Users keep working on the other node, with half the capacity and no
fallback left. Call the on-call DBA. Look at the `CLUSTERWARE` rows: they
usually show which resource failed.

## TEMP USAGE

`space-check`.

| KEY | VALUE | STATUS |
|---|---|---|
| tablespace name, for example `TEMP` | `Used=12.40% of 64G` | OK |
| | above `TEMP_WARN` (75) | WARN |
| | above `TEMP_CRIT` (90) | CRIT |
| `Top consumer` | `APPUSER sid 1234 inst 2: 41210M, sql_id 7h35uxf5uhmm1` | INFO |

**Meaning.** How much of the [TEMP tablespace](../../docs/glossary.md#tablespace)
sorts and hash joins use right now, against its maximum size. When TEMP
fills, queries fail with `ORA-01652`. The `Top consumer` row names the
session using the most, so a WARN comes with a name. No `Top consumer`
row means no session uses TEMP.

**How measured.** Used blocks from `gv$sort_segment` (all instances) against
the size of the temp files, counting autoextend up to `maxbytes`. v1 used a
different measure that stayed high after sorts finished; v2 numbers run
lower.

**WARN.** Rerun in 10 minutes. TEMP use rises and falls with batch jobs.
If it stays above the limit, send the `Top consumer` row to the DBA team.

**CRIT.** Queries are close to failing. Send the `Top consumer` row to the
on-call DBA now. They decide whether to add space or stop the session.

## TABLESPACE USAGE

`space-check`.

| KEY | VALUE | STATUS |
|---|---|---|
| tablespace name (the 5 fullest) | `Used=61.04% of max` | OK |
| | above `TS_WARN` (85) | WARN |
| | above `TS_CRIT` (95) | CRIT |

**Meaning.** How full the permanent tablespaces are, against the largest
size their files may grow to. A full tablespace stops inserts with
`ORA-01653` or `ORA-01654`. UNDO and TEMP are left out: UNDO fills and
recycles by design, TEMP has its own row.

**How measured.** `dba_tablespace_usage_metrics.used_percent`, which already
counts autoextend. Only the 5 fullest appear.

**WARN.** Tell the DBA team today. Include the row. They plan the space.

**CRIT.** Call the on-call DBA. At 95% of the maximum, one large load can
fill it.

## SESSION COUNT

`db-check`.

| KEY | VALUE | STATUS |
|---|---|---|
| `Inst 1 ACTIVE` | `9` | OK |
| | `0` | WARN |
| | above `ACTIVE_MAX` (18) | WARN |
| `Inst 1 INACTIVE` | `412` | OK |
| | above `INACTIVE_MAX` (1000) | WARN |

One ACTIVE and one INACTIVE row per instance, always, even at zero.

**Meaning.** Sessions of the application schema (`APP_USER`) on each
instance. ACTIVE = running a call now. INACTIVE = connected and idle.

**How measured.** `gv$session` counted by instance and status, for
`username = APP_USER`.

**WARN (ACTIVE = 0).** The application runs no work on that instance. In
business hours this often means the application lost its connections or
all its traffic moved to the other node. Ask the application support team
whether the application is up. Check `APP SERVERS`.

**WARN (ACTIVE above limit).** More work in flight than normal: a slow
query, a lock, or a traffic spike. Check `BLOCKING` and `LONG CALLS`. If
either is WARN, tell the DBA team.

**WARN (INACTIVE above limit).** The application opens connections and
does not close them (a connection leak). Over time this hits the
`SESSION LIMIT`. Tell the application support team and the DBA team.

**WARN on every row, every run.** `APP_USER` in `config.env` is probably
wrong. Oracle stores user names in capitals. `--check-config` tests it.

## SESSION LIMIT

`db-check`.

| KEY | VALUE | STATUS |
|---|---|---|
| `Inst 1 processes`, `Inst 1 sessions` (per instance) | `612 of 1500` | OK |
| | above `LIMIT_WARN` (80) % of the limit | WARN |
| | above `LIMIT_CRIT` (90) % of the limit | CRIT |

**Meaning.** Oracle refuses new connections when `processes` or `sessions`
reaches its limit (`ORA-00020`, `ORA-00018`).

**How measured.** `gv$resource_limit.current_utilization` against
`limit_value`.

**WARN.** Check `SESSION COUNT` for a jump in INACTIVE sessions. Tell the
DBA team.

**CRIT.** New logins are close to failing. Call the on-call DBA.

## BLOCKING

`db-check`.

| KEY | VALUE | STATUS |
|---|---|---|
| `Sessions blocked > 300s` | `0` | OK |
| | `1` or more | WARN |

**Meaning.** Sessions that have waited longer than `BLOCK_SECS` (300) for a
lock another session holds. The blocked users see a hang.

**How measured.** `gv$session` rows with `blocking_session` set and
`seconds_in_wait` above the limit.

**WARN.** List who blocks whom and send it to the DBA team:

```
sqlplus -s / as sysdba <<< "SELECT inst_id, sid, username, blocking_instance, blocking_session, seconds_in_wait, event FROM gv\$session WHERE blocking_session IS NOT NULL;"
```

Do not kill sessions yourself.

## LONG CALLS

`db-check`.

| KEY | VALUE | STATUS |
|---|---|---|
| `Active calls > 1800s` | `0` | OK |
| | `1` or more | WARN |

**Meaning.** User sessions running one call for longer than
`LONG_QUERY_SECS` (1800, half an hour). Often a runaway query; sometimes a
planned batch job.

**How measured.** `gv$session`, type USER, status ACTIVE, `last_call_et`
above the limit, users in `LONG_QUERY_SKIP` left out.

**WARN.** List them:

```
sqlplus -s / as sysdba <<< "SELECT inst_id, sid, username, sql_id, last_call_et FROM gv\$session WHERE type='USER' AND status='ACTIVE' AND username IS NOT NULL AND last_call_et > 1800;"
```

A known batch user every night at the same time? Ask the DBA team to add
it to `LONG_QUERY_SKIP`. Anything else: send the list to the DBA team.

## ARCHIVE DEST

`dr-check`.

| KEY | VALUE | STATUS |
|---|---|---|
| `Dest 1 -> USE_DB_RECOVERY_FILE_DEST` (one per active destination) | `VALID` | OK |
| `Dest 2 -> DEMODB_DR` | `ERROR: ORA-16191: ...`, `DEFERRED`, `DISABLED`, anything other than VALID | CRIT |

**Meaning.** Where the database writes or ships its archive logs. Dest 1
is usually local disk (the FRA). A second destination is usually the Data
Guard standby. An ERROR on the standby destination means redo has stopped
shipping, even while `DB SYNC STATUS` still looks fine.

**How measured.** `v$archive_dest`, every destination not INACTIVE.

**CRIT on the local destination.** Archiving has failed. When the online
redo logs fill, the database stops all changes. Call the on-call DBA now.

**CRIT on the standby destination.** The standby falls behind from this
moment. Call the on-call DBA. The error text (`ORA-...`) tells them why;
include it.

## DB SYNC STATUS

`dr-check`.

| KEY | VALUE | STATUS |
|---|---|---|
| `standby destination` | `detected 2, configured auto` (or `configured 2`) | INFO |
| | `detected none, configured auto` | WARN |
| | `detected none, configured 2`, or detected differs from configured | CRIT / WARN |
| | `..., configured none` | INFO |
| `Thread 1` (one per [thread](../../docs/glossary.md#thread)) | `PR=48211 DR=48210 GAP=1 LAG=4min` | OK |
| | `GAP` above `GAP_WARN` (10), or behind more than `LAG_WARN_MIN` (15) minutes | WARN |
| | `GAP` above `GAP_CRIT` (100), or behind more than `LAG_CRIT_MIN` (60) minutes | CRIT |
| | `DR=NONE GAP=? LAG=?min` | CRIT |
| `Data Guard` | `not checked, STANDBY_DEST=none` | INFO |

**Meaning.** How far the [standby](../../docs/glossary.md#standby) is
behind production. PR = newest archive log sequence on production. DR =
newest sequence the standby has applied. GAP = PR minus DR. LAG = minutes
since the newest applied log, counted only when GAP is above 0, so a quiet
thread at night shows no false alarm.

**How measured.** `v$archived_log` on production: produced logs, and logs
marked applied for the standby destination. The destination is
`STANDBY_DEST` from config.env, or the lowest-numbered active standby
destination when that is blank.

**standby destination WARN or CRIT.** No standby destination was found,
or it differs from config.env. On production, call the on-call DBA: redo
may have stopped shipping. On a database without a standby, set
`STANDBY_DEST=none`.

**Thread WARN.** The standby is behind. Check `ARCHIVE DEST` for an
error. Run again in 15 minutes; a batch job can cause a short gap. Still
WARN? Tell the DBA team.

**Thread CRIT.** In a disaster now, the DR site would lose that much data.
Call the on-call DBA.

**Thread CRIT with `DR=NONE`.** The standby has applied no log of that
thread. Call the on-call DBA.

## FRA USAGE

`backup-check`.

| KEY | VALUE | STATUS |
|---|---|---|
| FRA location, for example `+FRA` | `Used=41.22% of 2048G` | OK |
| | above `FRA_WARN` (80) | WARN |
| | above `FRA_CRIT` (90) | CRIT |
| `FRA` | `not configured` | INFO |

**Meaning.** How full the [Fast Recovery Area](../../docs/glossary.md#fra)
is, after subtracting files Oracle may delete on its own (already backed
up, or obsolete). A full FRA in ARCHIVELOG mode stops all changes in the
database (`ORA-00257`).

**How measured.** `v$recovery_file_dest`: `space_used` minus
`space_reclaimable`, against `space_limit`.

**WARN.** Usually archive logs that RMAN has not yet backed up. Check the
`RMAN BACKUP` rows. Tell the DBA team.

**CRIT.** Call the on-call DBA now. At 100% the database stops.

## ASM DISKGROUP

`space-check`.

| KEY | VALUE | STATUS |
|---|---|---|
| diskgroup name, for example `DATA` | `Used=71.80%, usable free 1410G` | OK |
| | above `ASM_WARN` (80) | WARN |
| | above `ASM_CRIT` (90), or usable free below 0 | CRIT |

**Meaning.** How full each [ASM](../../docs/glossary.md#asm) diskgroup is.
"Usable free" is the space left after keeping enough room to rebuild
mirror copies if one disk fails. Below 0 means a disk failure now would
leave some data with one copy.

**How measured.** `v$asm_diskgroup_stat`: `free_mb`, `total_mb`,
`usable_file_mb`.

**WARN.** Tell the DBA team and the storage team. Adding disks takes days.

**CRIT.** Call the on-call DBA. Files in a full diskgroup cannot grow.

## RMAN BACKUP

`backup-check`.

| KEY | VALUE | STATUS |
|---|---|---|
| `RMAN` | `not checked, CHECK_RMAN=0` | INFO |
| `Last DB backup (full/incr)` | `01-10-2026 23:40` | OK |
| | older than `DB_BACKUP_MAX_HRS` (26) hours, or `NONE` | CRIT |
| `Last archivelog backup` | `02-10-2026 18:05` | OK |
| | older than `ARCH_BACKUP_MAX_HRS` (6) hours, or `NONE` | WARN |
| `Failed jobs (24h)` | `0` | OK |
| | `1` or more | WARN |

**Meaning.** When [RMAN](../../docs/glossary.md#rman) last finished a good
backup of the database and of the archive logs, and how many backup jobs
failed in the last day.

**How measured.** `v$rman_backup_job_details`, status COMPLETED or
COMPLETED WITH WARNINGS.

**CRIT (DB backup).** Last night's backup did not finish. Tell the backup
team and the DBA team today. `NONE` every run on this database? Backups
run elsewhere (on the standby, for example) or not at all (pre-production);
set `CHECK_RMAN=0`.

**WARN (archivelog backup).** Archive logs pile up in the FRA. Check
`FRA USAGE`. Tell the backup team.

**WARN (failed jobs).** List them for the backup team:

```
sqlplus -s / as sysdba <<< "SELECT start_time, input_type, status FROM v\$rman_backup_job_details WHERE start_time > SYSDATE-1 ORDER BY start_time;"
```

## ALERT LOG

`node-check`, one row per node. Absent when `CHECK_ALERTLOG=0`.

| KEY | VALUE | STATUS |
|---|---|---|
| node host name, for example `racnode1` | `0 ORA- in 4h` | OK |
| | `3 ORA- in 4h, latest: ORA-00060: deadlock detected ...` | WARN |
| | `no ora_pmon process, alert log not read` | WARN |
| | `query failed: ...` | WARN |

**Meaning.** How many lines with `ORA-` the [alert log](../../docs/glossary.md#alert-log)
of the instance on that node recorded in the last `ALERT_WINDOW_HRS` (4)
hours, and the newest one.

**How measured.** On each node, `v$diag_alert_ext` (component `rdbms`)
through that node's own sqlplus. The script finds the instance from its
`ora_pmon_` process.

**WARN (ORA- errors).** Read the error number and send it to the DBA team.
Some are routine (`ORA-00060` deadlocks are an application issue; `ORA-03136`
is a client timeout). `ORA-00600`, `ORA-07445`, `ORA-04031` or `ORA-01578`
are serious: call the on-call DBA. To see all of them, as oracle on that
node:

```
sqlplus -s / as sysdba <<< "SELECT originating_timestamp, message_text FROM v\$diag_alert_ext WHERE originating_timestamp > SYSTIMESTAMP - INTERVAL '4' HOUR AND message_text LIKE '%ORA-%';"
```

**WARN (no ora_pmon process).** No database instance runs on that node.
Run `crs-check.sh` and `db-check.sh`.

**WARN (query failed).** The value shows the first error line. Report it
to the repo owner.

## CLUSTERWARE

`crs-check`.

| KEY | VALUE | STATUS |
|---|---|---|
| `Resources with TARGET=ONLINE` | `all ONLINE` | OK |
| resource name, for example `ora.LISTENER.lsnr` | `target ONLINE, state OFFLINE racnode2 ...` | CRIT |
| | `target ONLINE, state INTERMEDIATE ...` or `UNKNOWN` | WARN |
| `crsctl` | `not found at /u01/app/19.0.0/grid/bin/crsctl, set GRID_HOME` | WARN |
| `crsctl stat res -t` | `failed, rc=N` | CRIT |

**Meaning.** [Clusterware](../../docs/glossary.md#clusterware) runs the
instances, listeners, ASM, virtual IPs and SCAN listeners. Each resource
has a TARGET (the state it should be in) and a STATE (the state it is in).
A row appears for each resource that should be ONLINE and is not.

**How measured.** `crsctl stat res -t` from the Grid home, time limit
`CRS_TIMEOUT` (60) seconds.

**CRIT (OFFLINE).** That resource has stopped on that node. Listener: new
connections to that node fail. `.db`: the instance is down. `.vip`: the
node's virtual IP has moved. Call the on-call DBA with the row.

**WARN (INTERMEDIATE).** The resource is starting, stopping or partly
working. Rerun in 5 minutes. Still there? Tell the DBA team.

**WARN (crsctl not found).** The script could not find the Grid home. Set
`GRID_HOME` in `config.env` (find it with `grep crs_home /etc/oracle/olr.loc`).

**CRIT (failed, rc=N).** Clusterware did not answer. On node 1, as your user:

```
ps -ef | grep -c '[o]hasd'
```

`0` means the Clusterware stack is down on node 1. Call the on-call DBA.

## OS UTILIZATION

`node-check`, one row per node.

| KEY | VALUE | STATUS |
|---|---|---|
| node host name, for example `racnode1` | `CPU: 26.63% Mem: 52.83% Swap: 0.00% Load/core: 0.41` | OK |
| | the same with `(flagged: Mem)` naming each metric over its WARN limit | WARN |
| | the same with a metric over its CRIT limit | CRIT |
| | `CPU: ?%` or another `?` (a value could not be read) | WARN |
| | `NO DATA, unreachable or failed, rc=N` | CRIT |

**Meaning.** Load on each node. The `flagged:` list names the metrics over
their limits.

| Metric | Measured with | Limits |
|---|---|---|
| CPU | `sar -u 1 3`: 100 minus average idle over 3 seconds | `CPU_WARN` (60), `CPU_CRIT` (85) |
| Mem | `free -m`: (total minus available) / total | `MEM_WARN` (75), `MEM_CRIT` (90) |
| Swap | `free -m`: swap used / swap total | `SWAP_WARN` (10), `SWAP_CRIT` (30) |
| Load/core | 1-minute load average / CPU cores | `LOAD_WARN` (1.0), `LOAD_CRIT` (2.0) |

Other nodes are measured over one ssh call each; they need no copy of the
script.

**WARN or CRIT (CPU, Load).** Find the top processes on that node, as your
user:

```
top -b -n 1 | head -20
```

Mostly `oracle` processes? Send the output to the DBA team. Something
else? Send it to the Linux team.

**WARN or CRIT (Mem, Swap).** Swap use on a database server slows
everything. Send `free -m` and the `top` output to the Linux team and the
DBA team.

**WARN (`?`).** `sar` is missing on that node (CPU shows `?`). Ask the
Linux team to install sysstat: [docs/offline-install.md](../../docs/offline-install.md).

**CRIT (`NO DATA`).** The script could not reach that node. The node it
runs on never shows this row.

| rc | Meaning | Do this |
|---|---|---|
| 255 | ssh failed: host down, network, or key refused | `ping -c 3` the node. No reply: call the on-call Linux admin and DBA. Reply: run `node-check.sh --check-config` and read its TEST row. |
| 124 | ssh connected and hung for `SSH_TIMEOUT` (150) seconds | the node is overloaded or a mount hangs. Call the on-call Linux admin. |

## FILESYSTEM

`node-check`.

| KEY | VALUE | STATUS |
|---|---|---|
| node host name (summary, always present) | `5 checked, highest 70% on /u01` | OK, or the status of the fullest mount |
| node and mount, for example `racnode1 /u01` (only mounts over a limit) | `Used=83%` | WARN above `FS_WARN` (80) |
| | `Used=93%` | CRIT above `FS_CRIT` (90) |
| node host name | `no filesystems read` | WARN |

**Meaning.** Disk space on each local filesystem of each node. Network
mounts (NFS) are skipped, so a dead NFS server cannot hang the script.

**How measured.** `df -P -l`, the `Capacity` column.

**WARN.** Find what grew on that mount, as your user on that node
(replace `/u01` with the mount from the row):

```
sudo du -xh --max-depth=2 /u01 2>/dev/null | sort -h | tail -15
```

Oracle paths (`/u01/app/oracle/diag`, trace files, audit files)? Tell the
DBA team. OS paths (`/var/log`)? Tell the Linux team. Do not delete files
yourself.

**CRIT.** Same as WARN, and phone the team. A full `/u01` stops the
database from writing trace and audit files; a full `/` or `/var` can stop
the server.

**WARN (no filesystems read).** `df` returned nothing usable. Run
`df -P -l` on that node and send the output to the repo owner.

## GOLDENGATE

`gg-check`. Not run on pre-production, which has no GoldenGate.

| KEY | VALUE | STATUS |
|---|---|---|
| extract name, for example `X_EXTRACT1` | `RUNNING, lag 00:00:04, checkpoint 1m ago, started ..., SCN ...` | OK |
| | lag above `GG_LAG_WARN` (60) seconds, checkpoint older than `GG_CKPT_WARN_MIN` (5) minutes, lag not `HH:MM:SS`, or checkpoint unreadable (`?m ago`) | WARN |
| | status not RUNNING (`ABENDED`, `STOPPED`), lag above `GG_LAG_CRIT` (300) s, or checkpoint older than `GG_CKPT_CRIT_MIN` (15) min | CRIT |
| `unparsed line` | a line of `gg2.sh` output the script could not split | WARN |
| `Extracts` | `no extract rows in output` | CRIT |
| the GoldenGate host | `no output, unreachable or failed, rc=N` | CRIT |

**Meaning.** The state of each [GoldenGate](../../docs/glossary.md#goldengate)
extract. Lag = how far behind the extract reads. Checkpoint age = how long
since the extract last recorded its position; a stuck extract stops
updating it while still showing RUNNING. Pumps and replicats are not
covered: `gg2.sh` reports extracts only.

**How measured.** `ssh GG_HOST "sh GG_SCRIPT"`, one line per extract.
Checkpoint age uses node 1's clock; if the GoldenGate host runs in another
time zone, the age is wrong.

**CRIT (ABENDED or STOPPED).** Replication has stopped. Call the on-call
DBA or GoldenGate admin.

**WARN or CRIT (lag, checkpoint).** Replication runs behind. Run again in
5 minutes. Rising? Call the GoldenGate admin.

**CRIT (no output).** rc=255: ssh to the GoldenGate host failed; run
`gg-check.sh --check-config`. rc=124: `gg2.sh` hung. Other rc: `gg2.sh`
failed; ask the GoldenGate admin to run it by hand.

**CRIT (no extract rows) or WARN (unparsed line).** `gg2.sh` changed its
output format. Send its output to the repo owner.

## SFTP LOG

`inputs-check`.

| KEY | VALUE | STATUS |
|---|---|---|
| `/var/log/sftp.log` | `size 1003M, modified Oct 2 23:50, producer says: Normal` | OK |
| | size above `SFTP_LOG_WARN_MB` (1024), or producer status not `Normal` | WARN |
| `/home/oracle/sftp_output` | `file missing` | CRIT |
| `/home/oracle/sftp_output` | `STALE: last updated 95m ago, producer job stopped?` | CRIT |
| `unparsed line` | a line of `sftp_output` the script could not split | WARN |

**Meaning.** Size of the SFTP server's log. Another job writes the
measurement into `sftp_output`; this script reads that file and checks it
is fresh. The log has no rotation, so it grows until the disk fills.

**WARN (size).** Ask the Linux team to rotate or archive `/var/log/sftp.log`.

**CRIT (file missing or STALE).** The job that writes `sftp_output` has
stopped, so nobody measures the log. Find the job (`crontab -l` as oracle,
or ask the team that owns it) and tell its owner. STALE fires after
`STALE_MIN` (60) minutes.

**WARN (unparsed line).** The producer job changed its format. Send the
file to the repo owner.

## ACTIVE SESSIONS

`inputs-check`.

| KEY | VALUE | STATUS |
|---|---|---|
| `Last 2h (2151 - 2351)` | `highest 2331 --> 20 rows [NORMAL], lowest 2200 --> 6 rows [NORMAL]` | OK |
| | either status not `NORMAL` | WARN |
| `activesession.sh` | `failed or timed out, rc=N` | CRIT |
| `activesession.sh` | `no data rows` | WARN |
| `unparsed line` | a line the script could not split | WARN |

**Meaning.** The highest and lowest active session counts in the last 2
hours, with the time of each, as `activesession.sh` reports them. The
`[...]` status comes from `activesession.sh` itself; this script does not
set its limits.

**WARN (not NORMAL).** Look at the time of the peak and compare with
`SESSION COUNT` and `BLOCKING`. Tell the DBA team.

**CRIT (failed).** rc=127: `activesession.sh` not found at
`ACTIVESESSION_SCRIPT`. rc=124: it ran longer than `ACTIVESESSION_TIMEOUT`
(120) seconds. Other rc: run `sh /home/oracle/scripts/activesession.sh` by
hand and send the output to its owner.

## APP SERVERS

`inputs-check`.

| KEY | VALUE | STATUS |
|---|---|---|
| `Accessible` | `9 of 9, inaccessible 0` | OK |
| | fewer accessible than total, or inaccessible above 0 | CRIT |
| `/home/oracle/server_checklist` | `file missing` | CRIT |
| `/home/oracle/server_checklist` | `STALE: last updated 95m ago, producer job stopped?` | CRIT |
| `/home/oracle/server_checklist` | `no data rows` | WARN |
| `unparsed line` | a line the script could not split | WARN |

**Meaning.** How many application servers the producer job could reach.
The file gives counts only, not names.

**CRIT (fewer accessible).** Some application servers are down or cut
off. Ask the application support team which ones; the file does not say.

**CRIT (file missing or STALE).** Same as SFTP LOG: the producer job has
stopped. Tell its owner.

**WARN (no data rows, unparsed line).** The producer changed its format.
Send the file to the repo owner.
