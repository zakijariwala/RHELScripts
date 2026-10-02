# backup-check.sh: Fast Recovery Area and RMAN backups

Fast recovery area use and rman backup age.

| | |
|---|---|
| Runs on | any one database node |
| Runs as | oracle |
| Folder on the server | `/home/oracle/scripts/oracle-rac/backup-check` |
| Needs | `CHECK_RMAN=0` in config.env if this database has no RMAN backups (pre-production) or backs up on the standby |
| Run time | 5 to 20 seconds |
| Rows it prints | [FRA USAGE](../RUNBOOK.md#fra-usage), [RMAN BACKUP](../RUNBOOK.md#rman-backup) |

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
**oracle** on **any one database node**:

1. Create the folder and open a new file.

   ```
   mkdir -p /home/oracle/scripts/oracle-rac/backup-check && cd /home/oracle/scripts/oracle-rac/backup-check && vi backup-check.sh
   ```

2. Type the script from [backup-check.sh](backup-check.sh), one section at a time
   (`#== S01 ...`, `#== S02 ...`). After each section, save with `:w` and
   check that section's hash against the [checksum table](#checksums).

3. Check the syntax.

   ```
   bash -n backup-check.sh && echo SYNTAX OK
   ```

   Expected: `SYNTAX OK`. Anything else names the line to fix.

4. Check the whole-file hash.

   ```
   awk '{gsub(/\r/,"")}NF{$1=$1;print}' backup-check.sh | sha256sum | cut -c1-12
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
| `FRA_WARN` | WARN above this | `80` | default |
| `FRA_CRIT` | CRIT above this | `90` | default |
| `CHECK_RMAN` | 1 = check RMAN backups, 0 = skip | `1` | default |
| `DB_BACKUP_MAX_HRS` | threshold, see RUNBOOK | `26` | default |
| `ARCH_BACKUP_MAX_HRS` | threshold, see RUNBOOK | `6` | default |
| `SQL_TIMEOUT` | seconds per sqlplus call | `300` | default |

Any key you leave out keeps its default or its detected value. Thresholds
are explained row by row in the [RUNBOOK](../RUNBOOK.md); change them only
when a senior asks.

```
vi /home/oracle/scripts/oracle-rac/backup-check/config.env
```

A wrong key or value stops the script with exit code 65 and a message that
names the key.

## Check the configuration

Before the first real run, print what the script will use and test its
connections. This runs no checks.

```
cd /home/oracle/scripts/oracle-rac/backup-check && bash backup-check.sh --check-config
```

Sample output (from a test run against fake data):

<!-- sample:check-config:start -->
```
SECTION  KEY                                              VALUE                                                               STATUS
CONFIG   ORACLE_SID                                       DEMODB1 [detected]                                                  INFO
CONFIG   FRA_WARN                                         80 [default]                                                        INFO
CONFIG   FRA_CRIT                                         90 [default]                                                        INFO
CONFIG   CHECK_RMAN                                       1 [default]                                                         INFO
CONFIG   DB_BACKUP_MAX_HRS                                26 [default]                                                        INFO
CONFIG   ARCH_BACKUP_MAX_HRS                              6 [default]                                                         INFO
CONFIG   SQL_TIMEOUT                                      300 [default]                                                       INFO
CONFIG   checks                                           FRA used percent, last DB backup, last archivelog backup, failures  INFO
TEST     sqlplus login                                    DEMODB1 OPEN                                                        OK
SUMMARY  racnode1 backup-check 1.0.0 2026-10-02 20:18:52  CRIT=0 WARN=0 OK=1                                                  OK
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
cd /home/oracle/scripts/oracle-rac/backup-check && bash backup-check.sh
```

Sample output (from a test run against fake data):

<!-- sample:run:start -->
```
SECTION      KEY                                              VALUE                 STATUS
FRA USAGE    +FRA                                             Used=41.22% of 2048G  OK
RMAN BACKUP  Last DB backup (full/incr)                       01-10-2026 23:40      OK
RMAN BACKUP  Last archivelog backup                           02-10-2026 18:05      OK
RMAN BACKUP  Failed jobs (24h)                                0                     OK
SUMMARY      racnode1 backup-check 1.0.0 2026-10-02 20:18:52  CRIT=0 WARN=0 OK=4    OK
```
<!-- sample:run:end -->

The last line is the summary. `bash backup-check.sh --csv` prints the same rows
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
`backup-check.sh` version 1.0.0, 167 lines.

| Part | Hash |
|---|---|
| whole file | `30e479080ab6` |
| S00 | `b875f928546a` |
| S01 settings | `d728013c3a80` |
| S02 helpers | `d9deb6ab5c4d` |
| S03 output | `490cbc0df2aa` |
| S04 config | `ccb68e13b2fd` |
| S05 options | `869fb9d9b1f7` |
| S06 sql | `ec246e907298` |
| S07 fra | `75bb944021c8` |
| S08 rman | `8e33d57ec5be` |
| S09 main | `2557985dd5f4` |
<!-- checksums:end -->
