# db-check.sh: Database status, instances and sessions

Database status, instances, app sessions, limits, blocking, long calls.

| | |
|---|---|
| Runs on | any one database node (node 1 is fine) |
| Runs as | oracle |
| Folder on the server | `/home/oracle/scripts/oracle-rac/db-check` |
| Needs | nothing beyond a running instance on this node |
| Run time | 5 to 20 seconds |
| Rows it prints | [DB STATUS](../RUNBOOK.md#db-status), [INSTANCE STATUS](../RUNBOOK.md#instance-status), [SESSION COUNT](../RUNBOOK.md#session-count), [SESSION LIMIT](../RUNBOOK.md#session-limit), [BLOCKING](../RUNBOOK.md#blocking), [LONG CALLS](../RUNBOOK.md#long-calls) |

Contents: [Safety](#safety) · [Type it](#type-it) · [Configure](#configure) ·
[Check the configuration](#check-the-configuration) · [Run](#run) ·
[Checksums](#checksums) · [Changes](CHANGELOG.md)

## Safety

**Reads:** the database through `sqlplus -s -L / as sysdba` (SELECT only); `ps` to find the instance; `/etc/oracle/olr.loc` and `olsnodes` to count nodes.

**Writes:** nothing. The script prints to the screen only. It creates,
changes and deletes no file, on this host or any other, and sends no SQL
other than `SELECT`, `WITH`, SQL*Plus `SET`, `DEFINE` and `EXIT`. CI proves
this on every change with `tools/check-no-write.sh` and
`tools/check-readonly-sql.sh`; your typed copy matches the checked copy
when its hashes match the [checksum table](#checksums). How to check it
yourself: [docs/safety.md](../../../docs/safety.md).

## Type it

Follow [docs/typing-guide.md](../../../docs/typing-guide.md). In short, as
**oracle** on **any one database node**:

1. Create the folder and open a new file.

   ```
   mkdir -p /home/oracle/scripts/oracle-rac/db-check && cd /home/oracle/scripts/oracle-rac/db-check && vi db-check.sh
   ```

2. Type the script from [db-check.sh](db-check.sh), one section at a time
   (`#== S01 ...`, `#== S02 ...`). After each section, save with `:w` and
   check that section's hash against the [checksum table](#checksums).

3. Check the syntax.

   ```
   bash -n db-check.sh && echo SYNTAX OK
   ```

   Expected: `SYNTAX OK`. Anything else names the line to fix.

4. Check the whole-file hash.

   ```
   awk '{gsub(/\r/,"")}NF{$1=$1;print}' db-check.sh | sha256sum | cut -c1-12
   ```

   Expected: the "whole file" hash in the [checksum table](#checksums).

## Configure

The script reads `config.env` from its own folder: `KEY=value` lines, no
spaces around `=`, no quotes, no comments. Type only the keys you need.
Every value comes from the inventory sheet; the mapping, and the command
that confirms each value on the server, is in
[docs/config-from-inventory.md](../../../docs/config-from-inventory.md).

| Key | Meaning | Default | Where the value comes from |
|---|---|---|---|
| `ORACLE_SID` | instance name on this node | (blank) | detected from the running ora_pmon process |
| `APP_USER` | application schema, in capitals | (blank) | **required**, you type it |
| `GRID_HOME` | Grid Infrastructure home | (blank) | detected from /etc/oracle/olr.loc |
| `EXPECTED_INSTANCES` | instances that must be OPEN | (blank) | detected: number of nodes from olsnodes |
| `RESTART_WARN_DAYS` | threshold, see RUNBOOK | `1` | default |
| `ACTIVE_MAX` | threshold, see RUNBOOK | `18` | default |
| `INACTIVE_MAX` | threshold, see RUNBOOK | `1000` | default |
| `LIMIT_WARN` | WARN above this | `80` | default |
| `LIMIT_CRIT` | CRIT above this | `90` | default |
| `BLOCK_SECS` | threshold, see RUNBOOK | `300` | default |
| `LONG_QUERY_SECS` | threshold, see RUNBOOK | `1800` | default |
| `LONG_QUERY_SKIP` | users the long-call check ignores, comma separated | `SYS,SYSTEM,GGADMIN` | default |
| `SQL_TIMEOUT` | seconds per sqlplus call | `300` | default |

Any key you leave out keeps its default or its detected value. Thresholds
are explained row by row in the [RUNBOOK](../RUNBOOK.md); change them only
when a senior asks.

```
vi /home/oracle/scripts/oracle-rac/db-check/config.env
```

A wrong key or value stops the script with exit code 65 and a message that
names the key.

## Check the configuration

Before the first real run, print what the script will use and test its
connections. This runs no checks.

```
cd /home/oracle/scripts/oracle-rac/db-check && bash db-check.sh --check-config
```

Sample output (from a test run against fake data):

<!-- sample:check-config:start -->
```
SECTION  KEY                                          VALUE                                                                   STATUS
CONFIG   ORACLE_SID                                   DEMODB1 [detected]                                                      INFO
CONFIG   APP_USER                                     APPUSER [config]                                                        INFO
CONFIG   GRID_HOME                                    /u01/app/19.0.0/grid [config]                                           INFO
CONFIG   EXPECTED_INSTANCES                           2 [detected]                                                            INFO
CONFIG   RESTART_WARN_DAYS                            1 [default]                                                             INFO
CONFIG   ACTIVE_MAX                                   18 [default]                                                            INFO
CONFIG   INACTIVE_MAX                                 1000 [default]                                                          INFO
CONFIG   LIMIT_WARN                                   80 [default]                                                            INFO
CONFIG   LIMIT_CRIT                                   90 [default]                                                            INFO
CONFIG   BLOCK_SECS                                   300 [default]                                                           INFO
CONFIG   LONG_QUERY_SECS                              1800 [default]                                                          INFO
CONFIG   LONG_QUERY_SKIP                              SYS,SYSTEM,GGADMIN [default]                                            INFO
CONFIG   SQL_TIMEOUT                                  300 [default]                                                           INFO
CONFIG   checks                                       open mode, log mode, instances, sessions, limits, blocking, long calls  INFO
TEST     login, APP_USER exists                       APPUSER                                                                 OK
SUMMARY  racnode1 db-check 1.0.0 2026-10-02 23:39:16  CRIT=0 WARN=0 OK=1                                                      OK
```
<!-- sample:check-config:end -->

Read every `CONFIG` row. `[detected]` means the script found the value on
this server, `[config]` that it came from config.env, `[default]` that
nothing set it. A `MISMATCH` row (WARN) means config.env and the server
disagree: trust the server, and tell the senior which inventory row is
wrong. Every `TEST` row must be OK.

Attach this output to the [approval checklist](../../../docs/approval-checklist.md)
and wait for the senior's approval before the first run.

## Run

Only after approval:

```
cd /home/oracle/scripts/oracle-rac/db-check && bash db-check.sh
```

Sample output (from a test run against fake data):

<!-- sample:run:start -->
```
SECTION          KEY                                          VALUE                STATUS
DATABASE         name                                         DEMODB               INFO
DB STATUS        OPEN_MODE inst 1                             READ WRITE           OK
DB STATUS        OPEN_MODE inst 2                             READ WRITE           OK
DB STATUS        LOG_MODE                                     ARCHIVELOG           OK
INSTANCE STATUS  Instance 1 (DEMODB1 on racnode1)             OPEN, up 41.3 days   OK
INSTANCE STATUS  Instance 2 (DEMODB2 on racnode2)             OPEN, up 41.3 days   OK
INSTANCE STATUS  Instances OPEN                               2 of 2               OK
SESSION COUNT    Inst 1 ACTIVE                                9                    OK
SESSION COUNT    Inst 1 INACTIVE                              412                  OK
SESSION COUNT    Inst 2 ACTIVE                                11                   OK
SESSION COUNT    Inst 2 INACTIVE                              398                  OK
SESSION LIMIT    Inst 1 processes                             612 of 1500          OK
SESSION LIMIT    Inst 1 sessions                              655 of 2272          OK
SESSION LIMIT    Inst 2 processes                             598 of 1500          OK
SESSION LIMIT    Inst 2 sessions                              640 of 2272          OK
BLOCKING         Sessions blocked > 300s                      0                    OK
LONG CALLS       Active calls > 1800s                         0                    OK
SUMMARY          racnode1 db-check 1.0.0 2026-10-02 23:39:17  CRIT=0 WARN=0 OK=16  OK
```
<!-- sample:run:end -->

The last line is the summary. `bash db-check.sh --csv` prints the same rows
as CSV. Then:

```
echo $?
```

`0` all OK, `1` at least one WARN, `2` at least one CRIT, `64` bad option,
`65` bad or missing config. For every WARN or CRIT row, follow its entry in
the [RUNBOOK](../RUNBOOK.md). [docs/reading-output.md](../../../docs/reading-output.md)
explains the columns.

## Checksums

Compare your typed copy with these hashes as the
[typing guide](../../../docs/typing-guide.md#verify-a-section) shows. They
change with every version; the [CHANGELOG](CHANGELOG.md) lists what to
retype.

<!-- checksums:start -->
`db-check.sh` version 1.0.0, 200 lines.

| Part | Hash |
|---|---|
| whole file | `1cce9909eed4` |
| S00 | `b875f928546a` |
| S01 settings | `5ad3b2168845` |
| S02 helpers | `d9deb6ab5c4d` |
| S03 output | `490cbc0df2aa` |
| S04 config | `ccb68e13b2fd` |
| S05 options | `869fb9d9b1f7` |
| S06 sql | `ec246e907298` |
| S07 status | `da0c506f2e77` |
| S08 sessions | `94a074836b91` |
| S09 load | `c09ce4487e97` |
| S10 main | `3f4ed7c1d68c` |
<!-- checksums:end -->
