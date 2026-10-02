# dr-check.sh: Archive destinations and Data Guard

Archive destinations and data guard gap and lag, run on the primary.

| | |
|---|---|
| Runs on | a node of the PRIMARY database |
| Runs as | oracle |
| Folder on the server | `/home/oracle/scripts/oracle-rac/dr-check` |
| Needs | a standby, or `STANDBY_DEST=none` in config.env |
| Run time | 5 to 20 seconds |
| Rows it prints | [ARCHIVE DEST](../RUNBOOK.md#archive-dest), [DB SYNC STATUS](../RUNBOOK.md#db-sync-status) |

Contents: [Safety](#safety) · [Type it](#type-it) · [Configure](#configure) ·
[Check the configuration](#check-the-configuration) · [Run](#run) ·
[Checksums](#checksums) · [Changes](CHANGELOG.md)

## Safety

**Reads:** the database through `sqlplus -s -L / as sysdba` (SELECT only); `ps` to find the instance.

**Writes:** nothing. The script prints to the screen only. It creates,
changes and deletes no file, on this host or any other, and sends no SQL
other than `SELECT`, `WITH`, SQL*Plus `SET`, `DEFINE` and `EXIT`. CI proves
this on every change with `tools/check-no-write.sh` and
`tools/check-readonly-sql.sh`; your typed copy matches the checked copy
when its hashes match the [checksum table](#checksums). How to check it
yourself: [docs/safety.md](../../../docs/safety.md).

## Type it

Follow [docs/typing-guide.md](../../../docs/typing-guide.md). In short, as
**oracle** on **a node of the PRIMARY database**:

1. Create the folder and open a new file.

   ```
   mkdir -p /home/oracle/scripts/oracle-rac/dr-check && cd /home/oracle/scripts/oracle-rac/dr-check && vi dr-check.sh
   ```

2. Type the script from [dr-check.sh](dr-check.sh), one section at a time
   (`#== S01 ...`, `#== S02 ...`). After each section, save with `:w` and
   check that section's hash against the [checksum table](#checksums).

3. Check the syntax.

   ```
   bash -n dr-check.sh && echo SYNTAX OK
   ```

   Expected: `SYNTAX OK`. Anything else names the line to fix.

4. Check the whole-file hash.

   ```
   awk '{gsub(/\r/,"")}NF{$1=$1;print}' dr-check.sh | sha256sum | cut -c1-12
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
| `STANDBY_DEST` | dest_id of the standby, or none | (blank) | detected from v$archive_dest; set it on production |
| `GAP_WARN` | WARN above this | `10` | default |
| `GAP_CRIT` | CRIT above this | `100` | default |
| `LAG_WARN_MIN` | threshold, see RUNBOOK | `15` | default |
| `LAG_CRIT_MIN` | threshold, see RUNBOOK | `60` | default |
| `SQL_TIMEOUT` | seconds per sqlplus call | `300` | default |

Any key you leave out keeps its default or its detected value. Thresholds
are explained row by row in the [RUNBOOK](../RUNBOOK.md); change them only
when a senior asks.

```
vi /home/oracle/scripts/oracle-rac/dr-check/config.env
```

A wrong key or value stops the script with exit code 65 and a message that
names the key.

## Check the configuration

Before the first real run, print what the script will use and test its
connections. This runs no checks.

```
cd /home/oracle/scripts/oracle-rac/dr-check && bash dr-check.sh --check-config
```

Sample output (from a test run against fake data):

<!-- sample:check-config:start -->
```
SECTION  KEY                                          VALUE                                                              STATUS
CONFIG   ORACLE_SID                                   DEMODB1 [detected]                                                 INFO
CONFIG   STANDBY_DEST                                 (empty) [default]                                                  INFO
CONFIG   GAP_WARN                                     10 [default]                                                       INFO
CONFIG   GAP_CRIT                                     100 [default]                                                      INFO
CONFIG   LAG_WARN_MIN                                 15 [default]                                                       INFO
CONFIG   LAG_CRIT_MIN                                 60 [default]                                                       INFO
CONFIG   SQL_TIMEOUT                                  300 [default]                                                      INFO
CONFIG   checks                                       archive destinations, standby destination, gap and lag per thread  INFO
TEST     standby destination                          detected 2, configured auto                                        OK
SUMMARY  racnode1 dr-check 1.0.0 2026-10-02 20:18:52  CRIT=0 WARN=0 OK=1                                                 OK
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
cd /home/oracle/scripts/oracle-rac/dr-check && bash dr-check.sh
```

Sample output (from a test run against fake data):

<!-- sample:run:start -->
```
SECTION         KEY                                          VALUE                             STATUS
ARCHIVE DEST    Dest 1 -> USE_DB_RECOVERY_FILE_DEST          VALID                             OK
ARCHIVE DEST    Dest 2 -> DEMODB_DR                          VALID                             OK
DB SYNC STATUS  standby destination                          detected 2, configured auto       INFO
DB SYNC STATUS  Thread 1                                     PR=48211 DR=48210 GAP=1 LAG=4min  OK
DB SYNC STATUS  Thread 2                                     PR=47102 DR=47102 GAP=0 LAG=0min  OK
SUMMARY         racnode1 dr-check 1.0.0 2026-10-02 20:18:52  CRIT=0 WARN=0 OK=4                OK
```
<!-- sample:run:end -->

The last line is the summary. `bash dr-check.sh --csv` prints the same rows
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
`dr-check.sh` version 1.0.0, 186 lines.

| Part | Hash |
|---|---|
| whole file | `0a2493577b65` |
| S00 | `b875f928546a` |
| S01 settings | `d781b2773950` |
| S02 helpers | `d9deb6ab5c4d` |
| S03 output | `490cbc0df2aa` |
| S04 config | `ccb68e13b2fd` |
| S05 options | `869fb9d9b1f7` |
| S06 sql | `ec246e907298` |
| S07 dest | `a252c90d6e25` |
| S08 sync | `cbc6ca91aab7` |
| S09 main | `51a1b6b428bc` |
<!-- checksums:end -->
