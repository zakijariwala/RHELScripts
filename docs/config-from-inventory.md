# Config from the inventory sheet

Every script reads `config.env` from its own folder. This page says where
each value comes from in the team's inventory sheet, and how to confirm it
on the server before you type it.

**The repo owner fills in** the `CHANGE_ME_` sheet and column names below
with the real ones from the team's inventory workbook.

## Rules

1. Type only the keys a script's README lists, and only the ones you need.
   Leave out any key whose default or detected value is right.
2. One `KEY=value` per line. No spaces around `=`. No quotes. No comments.
3. Confirm every value with the command in the table, on the server, as
   **oracle** on **node 1**, unless the row says otherwise.
4. **When the server and the sheet disagree, the server wins.** Type the
   server's value, and tell the senior which inventory row is wrong so it
   gets corrected.
5. Keys marked "detected" need no typing: the script finds the value. Type
   them only to override, and `--check-config` then shows `MISMATCH` if the
   server says otherwise.

## Mapping

| Key | Used by | Inventory sheet | Column | Example | Confirm on the server | On mismatch |
|---|---|---|---|---|---|---|
| `APP_USER` | db-check | `CHANGE_ME_SHEET_DATABASES` | `CHANGE_ME_COL_APP_SCHEMA` | `APPUSER` | `sqlplus -s / as sysdba <<< "SELECT username FROM dba_users WHERE oracle_maintained = 'N';"` lists it | type the server's spelling, in capitals |
| `ORACLE_SID` (detected) | db, space, dr, backup | `CHANGE_ME_SHEET_DATABASES` | `CHANGE_ME_COL_INSTANCE` | `DEMODB1` | `ps -eo args \| grep '^ora_pmon_'` shows `ora_pmon_DEMODB1` | leave it out; the script detects it |
| `GRID_HOME` (detected) | db, node, crs, proc | `CHANGE_ME_SHEET_CLUSTERS` | `CHANGE_ME_COL_GRID_HOME` | `/u01/app/19.0.0/grid` | `grep crs_home /etc/oracle/olr.loc` | leave it out |
| `EXPECTED_INSTANCES` (detected) | db-check | `CHANGE_ME_SHEET_CLUSTERS` | `CHANGE_ME_COL_NODE_COUNT` | `2` | `$GRID_HOME/bin/olsnodes \| wc -l` | type the sheet's value only if the database runs on fewer nodes than the cluster has |
| `NODES` (detected) | node-check, proc-check | `CHANGE_ME_SHEET_CLUSTERS` | `CHANGE_ME_COL_NODE_NAMES` | `racnode1,racnode2` | `$GRID_HOME/bin/olsnodes` | leave it out |
| `STANDBY_DEST` | dr-check | `CHANGE_ME_SHEET_DATABASES` | `CHANGE_ME_COL_DR_DEST` | `2`, or `none` | `sqlplus -s / as sysdba <<< "SELECT dest_id, destination FROM v\$archive_dest WHERE target = 'STANDBY';"` | production: type the server's `dest_id`. No standby: type `none` |
| `CHECK_RMAN` | backup-check | `CHANGE_ME_SHEET_DATABASES` | `CHANGE_ME_COL_BACKUP_POLICY` | `1`, or `0` | `sqlplus -s / as sysdba <<< 'SELECT MAX(end_time) FROM v$rman_backup_job_details;'` shows a recent date | `0` when backups run on the standby or not at all |
| `GG_HOST` | gg-check | `CHANGE_ME_SHEET_GOLDENGATE` | `CHANGE_ME_COL_GG_HOST` | `gghost01` | `ssh -o BatchMode=yes CHANGE_ME_GG_HOST hostname` prints the host name | type the name that works with ssh |
| `GG_SCRIPT` | gg-check | `CHANGE_ME_SHEET_GOLDENGATE` | `CHANGE_ME_COL_GG_SCRIPT` | `/home/oracle/scripts/gg2.sh` | `ssh -o BatchMode=yes CHANGE_ME_GG_HOST ls -l /home/oracle/scripts/gg2.sh` | type the path that exists |
| `LONG_QUERY_SKIP` | db-check | `CHANGE_ME_SHEET_GOLDENGATE` | `CHANGE_ME_COL_GG_DB_USER` | `SYS,SYSTEM,GGADMIN` | `sqlplus -s / as sysdba <<< 'SELECT username FROM dba_users;'` lists the GoldenGate user | replace `GGADMIN` with the real GoldenGate database user |
| `SSH_PORT` | node, gg, proc | `CHANGE_ME_SHEET_SERVERS` | `CHANGE_ME_COL_SSH_PORT` | `22` | `ssh -o BatchMode=yes racnode2 hostname` works without `-p` | leave it out when ssh works on the default port |
| `PROCS` | host-check | `CHANGE_ME_SHEET_SERVERS` | `CHANGE_ME_COL_AGENTS` | `crond,chronyd,sshd,CHANGE_ME_AGENT` | `ps -eo comm \| sort -u` lists each name exactly | type the names `ps` shows; at most 15 characters each |
| `CHECK_HUGEPAGES` | hw-check | `CHANGE_ME_SHEET_SERVERS` | `CHANGE_ME_COL_ROLE` | `1` on database servers, `0` on app and web | `grep HugePages_Total /proc/meminfo` | `0` where the server runs no database |
| `LISTENERS` | proc-check | `CHANGE_ME_SHEET_DATABASES` | `CHANGE_ME_COL_LISTENER` | `LISTENER` | `ps -eo args \| grep '[t]nslsnr'` shows the name after `tnslsnr` | type the local listener name; SCAN listeners never go here |
| `CHECK_ASM` | proc-check | `CHANGE_ME_SHEET_DATABASES` | `CHANGE_ME_COL_STORAGE` | `1` | `ps -eo args \| grep '^asm_pmon'` | `0` only when the database uses no ASM |
| `SFTP_FILE` | inputs-check | `CHANGE_ME_SHEET_JOBS` | `CHANGE_ME_COL_SFTP_OUTPUT` | `/home/oracle/sftp_output` | `ls -l /home/oracle/sftp_output` shows a time in the last hour | type the path that exists |
| `SERVER_FILE` | inputs-check | `CHANGE_ME_SHEET_JOBS` | `CHANGE_ME_COL_SERVER_CHECKLIST` | `/home/oracle/server_checklist` | `ls -l /home/oracle/server_checklist` | type the path that exists |
| `ACTIVESESSION_SCRIPT` | inputs-check | `CHANGE_ME_SHEET_JOBS` | `CHANGE_ME_COL_ACTIVESESSION` | `/home/oracle/scripts/activesession.sh` | `ls -l /home/oracle/scripts/activesession.sh` | type the path that exists |

Thresholds (`..._WARN`, `..._CRIT`, `..._MAX`, timeouts) do not come from
the inventory. Each script's README lists its defaults, and the
[RUNBOOK](../scripts/oracle-rac/RUNBOOK.md) explains them. Change one only
when a senior asks, and write the change on the approval checklist.

## Example config.env

For `db-check` on a cluster where detection works, the whole file is one
line:

```
APP_USER=APPUSER
```

For `dr-check` on production with the standby on destination 2:

```
STANDBY_DEST=2
```

For `dr-check` on pre-production with no standby:

```
STANDBY_DEST=none
```

Then run the script with `--check-config` and check every row before you
ask for approval.
