# space-check.sh: TEMP, tablespaces and ASM diskgroups

Temp, permanent tablespaces and asm diskgroups, percent used.

| | |
|---|---|
| Runs on | any one database node |
| Runs as | oracle |
| Folder on the server | `/home/oracle/scripts/oracle-rac/space-check` |
| Needs | nothing beyond a running instance on this node |
| Run time | 5 to 30 seconds |
| Rows it prints | [TEMP USAGE](../RUNBOOK.md#temp-usage), [TABLESPACE USAGE](../RUNBOOK.md#tablespace-usage), [ASM DISKGROUP](../RUNBOOK.md#asm-diskgroup) |

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
   mkdir -p /home/oracle/scripts/oracle-rac/space-check && cd /home/oracle/scripts/oracle-rac/space-check && vi space-check.sh
   ```

2. Type the script from [space-check.sh](space-check.sh), one section at a time
   (`#== S01 ...`, `#== S02 ...`). After each section, save with `:w` and
   check that section's hash against the [checksum table](#checksums).

3. Check the syntax.

   ```
   bash -n space-check.sh && echo SYNTAX OK
   ```

   Expected: `SYNTAX OK`. Anything else names the line to fix.

4. Check the whole-file hash.

   ```
   awk '{gsub(/\r/,"")}NF{$1=$1;print}' space-check.sh | sha256sum | cut -c1-12
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
| `TEMP_WARN` | WARN above this | `75` | default |
| `TEMP_CRIT` | CRIT above this | `90` | default |
| `TS_WARN` | WARN above this | `85` | default |
| `TS_CRIT` | CRIT above this | `95` | default |
| `ASM_WARN` | WARN above this | `80` | default |
| `ASM_CRIT` | CRIT above this | `90` | default |
| `SQL_TIMEOUT` | seconds per sqlplus call | `300` | default |

Any key you leave out keeps its default or its detected value. Thresholds
are explained row by row in the [RUNBOOK](../RUNBOOK.md); change them only
when a senior asks.

```
vi /home/oracle/scripts/oracle-rac/space-check/config.env
```

A wrong key or value stops the script with exit code 65 and a message that
names the key.

## Check the configuration

Before the first real run, print what the script will use and test its
connections. This runs no checks.

```
cd /home/oracle/scripts/oracle-rac/space-check && bash space-check.sh --check-config
```

Sample output (from a test run against fake data):

<!-- sample:check-config:start -->
```
SECTION  KEY                                             VALUE                                                           STATUS
CONFIG   ORACLE_SID                                      DEMODB1 [detected]                                              INFO
CONFIG   TEMP_WARN                                       75 [default]                                                    INFO
CONFIG   TEMP_CRIT                                       90 [default]                                                    INFO
CONFIG   TS_WARN                                         85 [default]                                                    INFO
CONFIG   TS_CRIT                                         95 [default]                                                    INFO
CONFIG   ASM_WARN                                        80 [default]                                                    INFO
CONFIG   ASM_CRIT                                        90 [default]                                                    INFO
CONFIG   SQL_TIMEOUT                                     300 [default]                                                   INFO
CONFIG   checks                                          TEMP, top TEMP consumer, 5 fullest tablespaces, ASM diskgroups  INFO
TEST     sqlplus login                                   DEMODB1 OPEN                                                    OK
SUMMARY  racnode1 space-check 1.0.0 2026-10-02 23:39:18  CRIT=0 WARN=0 OK=1                                              OK
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
cd /home/oracle/scripts/oracle-rac/space-check && bash space-check.sh
```

Sample output (from a test run against fake data):

<!-- sample:run:start -->
```
SECTION           KEY                                             VALUE                                                  STATUS
TEMP USAGE        TEMP                                            Used=78.40% of 64G                                     WARN
TEMP USAGE        Top consumer                                    APPUSER sid 1234 inst 2: 41210M, sql_id 7h35uxf5uhmm1  INFO
TABLESPACE USAGE  APP_DATA                                        Used=86.12% of max                                     WARN
TABLESPACE USAGE  SYSAUX                                          Used=61.04% of max                                     OK
TABLESPACE USAGE  APP_INDEX                                       Used=54.90% of max                                     OK
TABLESPACE USAGE  SYSTEM                                          Used=12.33% of max                                     OK
TABLESPACE USAGE  USERS                                           Used=0.10% of max                                      OK
ASM DISKGROUP     DATA                                            Used=71.80%, usable free 1410G                         OK
ASM DISKGROUP     FRA                                             Used=43.10%, usable free 1162G                         OK
ASM DISKGROUP     OCR                                             Used=8.20%, usable free 3G                             OK
SUMMARY           racnode1 space-check 1.0.0 2026-10-02 23:39:18  CRIT=0 WARN=2 OK=7                                     WARN
```
<!-- sample:run:end -->

The last line is the summary. `bash space-check.sh --csv` prints the same rows
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
`space-check.sh` version 1.0.0, 172 lines.

| Part | Hash |
|---|---|
| whole file | `97016dd76888` |
| S00 | `b875f928546a` |
| S01 settings | `93423e2d770b` |
| S02 helpers | `d9deb6ab5c4d` |
| S03 output | `490cbc0df2aa` |
| S04 config | `ccb68e13b2fd` |
| S05 options | `869fb9d9b1f7` |
| S06 sql | `ec246e907298` |
| S07 temp | `53ce5fa1dc3f` |
| S08 space | `a45844304c99` |
| S09 main | `dc940171aaff` |
<!-- checksums:end -->
