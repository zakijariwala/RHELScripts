# proc-check.sh: Database, ASM, listener and Clusterware processes

Database, asm, listener and clusterware processes on every node.

| | |
|---|---|
| Runs on | node 1 (it reaches the other nodes over ssh) |
| Runs as | oracle |
| Folder on the server | `/home/oracle/scripts/oracle-rac/proc-check` |
| Needs | passwordless ssh as oracle from node 1 to every other node |
| Run time | 2 to 20 seconds |
| Rows it prints | [DB PROCESS](../RUNBOOK.md#db-process), [LISTENER](../RUNBOOK.md#listener), [CRS PROCESS](../RUNBOOK.md#crs-process) |

Contents: [Safety](#safety) · [Type it](#type-it) · [Configure](#configure) ·
[Check the configuration](#check-the-configuration) · [Run](#run) ·
[Checksums](#checksums) · [Changes](CHANGELOG.md)

## Safety

**Reads:** `ps -eo args=` and `ps -eo comm=` on every node; other nodes through one `ssh ... bash -s` call each, nothing copied or written there.

**Writes:** nothing. The script prints to the screen only. It creates,
changes and deletes no file, on this host or any other, and sends no SQL
other than `SELECT`, `WITH`, SQL*Plus `SET`, `DEFINE` and `EXIT`. CI proves
this on every change with `tools/check-no-write.sh` and
`tools/check-readonly-sql.sh`; your typed copy matches the checked copy
when its hashes match the [checksum table](#checksums). How to check it
yourself: [docs/safety.md](../../../docs/safety.md).

## Type it

Follow [docs/typing-guide.md](../../../docs/typing-guide.md). In short, as
**oracle** on **node 1**:

1. Create the folder and open a new file.

   ```
   mkdir -p /home/oracle/scripts/oracle-rac/proc-check && cd /home/oracle/scripts/oracle-rac/proc-check && vi proc-check.sh
   ```

2. Type the script from [proc-check.sh](proc-check.sh), one section at a time
   (`#== S01 ...`, `#== S02 ...`). After each section, save with `:w` and
   check that section's hash against the [checksum table](#checksums).

3. Check the syntax.

   ```
   bash -n proc-check.sh && echo SYNTAX OK
   ```

   Expected: `SYNTAX OK`. Anything else names the line to fix.

4. Check the whole-file hash.

   ```
   awk '{gsub(/\r/,"")}NF{$1=$1;print}' proc-check.sh | sha256sum | cut -c1-12
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
| `NODES` | nodes to check, comma separated | (blank) | detected from olsnodes |
| `GRID_HOME` | Grid Infrastructure home | (blank) | detected from /etc/oracle/olr.loc |
| `SSH_PORT` | ssh port of the other hosts | `22` | default |
| `SSH_TIMEOUT` | seconds per ssh call | `60` | default |
| `LISTENERS` | local listener names that must run, comma separated | `LISTENER` | default |
| `CRS_DAEMONS` | Clusterware daemons that must run, comma separated | `$CRS_DAEMONS,mdnsd.bin,octssd.bin,osysmond.bin` | default |
| `CHECK_ASM` | 1 = an ASM instance must run, 0 = skip | `1` | default |

Any key you leave out keeps its default or its detected value. Thresholds
are explained row by row in the [RUNBOOK](../RUNBOOK.md); change them only
when a senior asks.

```
vi /home/oracle/scripts/oracle-rac/proc-check/config.env
```

A wrong key or value stops the script with exit code 65 and a message that
names the key.

## Check the configuration

Before the first real run, print what the script will use and test its
connections. This runs no checks.

```
cd /home/oracle/scripts/oracle-rac/proc-check && bash proc-check.sh --check-config
```

Sample output (from a test run against fake data):

<!-- sample:check-config:start -->
```
SECTION  KEY                                            VALUE                                                                                                  STATUS
CONFIG   NODES                                          racnode1,racnode2 [detected]                                                                           INFO
CONFIG   GRID_HOME                                      /u01/app/19.0.0/grid [config]                                                                          INFO
CONFIG   SSH_PORT                                       22 [default]                                                                                           INFO
CONFIG   SSH_TIMEOUT                                    60 [default]                                                                                           INFO
CONFIG   LISTENERS                                      LISTENER [default]                                                                                     INFO
CONFIG   CRS_DAEMONS                                    ohasd.bin,ocssd.bin,crsd.bin,evmd.bin,gpnpd.bin,gipcd.bin,mdnsd.bin,octssd.bin,osysmond.bin [default]  INFO
CONFIG   CHECK_ASM                                      1 [default]                                                                                            INFO
CONFIG   checks                                         per node: instance pmon, ASM pmon, local listener, CRS daemons                                         INFO
TEST     racnode1                                       this host                                                                                              OK
TEST     ssh racnode2                                   login works                                                                                            OK
SUMMARY  racnode1 proc-check 1.0.0 2026-10-02 23:39:18  CRIT=0 WARN=0 OK=2                                                                                     OK
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
cd /home/oracle/scripts/oracle-rac/proc-check && bash proc-check.sh
```

Sample output (from a test run against fake data):

<!-- sample:run:start -->
```
SECTION      KEY                                            VALUE               STATUS
DB PROCESS   racnode1 pmon                                  DEMODB1             OK
DB PROCESS   racnode1 asm                                   +ASM1               OK
LISTENER     racnode1 LISTENER                              running             OK
LISTENER     racnode1 others                                LISTENER_SCAN2      INFO
CRS PROCESS  racnode1                                       all running         OK
DB PROCESS   racnode2 pmon                                  DEMODB2             OK
DB PROCESS   racnode2 asm                                   +ASM2               OK
LISTENER     racnode2 LISTENER                              running             OK
LISTENER     racnode2 others                                LISTENER_SCAN1      INFO
CRS PROCESS  racnode2                                       all running         OK
SUMMARY      racnode1 proc-check 1.0.0 2026-10-02 23:39:18  CRIT=0 WARN=0 OK=8  OK
```
<!-- sample:run:end -->

The last line is the summary. `bash proc-check.sh --csv` prints the same rows
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
`proc-check.sh` version 1.0.0, 153 lines.

| Part | Hash |
|---|---|
| whole file | `8e68e57df575` |
| S00 | `b875f928546a` |
| S01 settings | `b2cb3fe781b4` |
| S02 helpers | `d9deb6ab5c4d` |
| S03 output | `490cbc0df2aa` |
| S04 config | `ccb68e13b2fd` |
| S05 options | `869fb9d9b1f7` |
| S06 collect | `7aa43f9f8b84` |
| S07 rows | `7d4f6b6ac5ab` |
| S08 main | `2cc550bd178d` |
<!-- checksums:end -->
