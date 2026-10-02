# node-check.sh: CPU, memory, swap, load, filesystems and alert log on every node

Cpu, memory, swap, load, filesystems, alert log ora- on every node.

| | |
|---|---|
| Runs on | node 1 (it reaches the other nodes over ssh) |
| Runs as | oracle |
| Folder on the server | `/home/oracle/scripts/oracle-rac/node-check` |
| Needs | passwordless ssh as oracle from node 1 to every other node; the `sysstat` package on every node |
| Run time | 15 to 60 seconds |
| Rows it prints | [OS UTILIZATION](../RUNBOOK.md#os-utilization), [FILESYSTEM](../RUNBOOK.md#filesystem), [ALERT LOG](../RUNBOOK.md#alert-log) |

Contents: [Safety](#safety) · [Type it](#type-it) · [Configure](#configure) ·
[Check the configuration](#check-the-configuration) · [Run](#run) ·
[Checksums](#checksums) · [Changes](CHANGELOG.md)

## Safety

**Reads:** `sar -u 1 3`, `free -m`, `/proc/loadavg`, `nproc`, `df -P -l`, `ps` and the alert log (through `sqlplus`, SELECT only) on every node. Other nodes: one `ssh ... bash -s` call each, which sends the `collect` function and runs it there; nothing is copied to or written on the other node.

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
   mkdir -p /home/oracle/scripts/oracle-rac/node-check && cd /home/oracle/scripts/oracle-rac/node-check && vi node-check.sh
   ```

2. Type the script from [node-check.sh](node-check.sh), one section at a time
   (`#== S01 ...`, `#== S02 ...`). After each section, save with `:w` and
   check that section's hash against the [checksum table](#checksums).

3. Check the syntax.

   ```
   bash -n node-check.sh && echo SYNTAX OK
   ```

   Expected: `SYNTAX OK`. Anything else names the line to fix.

4. Check the whole-file hash.

   ```
   awk '{gsub(/\r/,"")}NF{$1=$1;print}' node-check.sh | sha256sum | cut -c1-12
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
| `SSH_TIMEOUT` | seconds per ssh call | `150` | default |
| `SQL_TIMEOUT` | seconds per sqlplus call | `120` | default |
| `CPU_WARN` | WARN above this | `60` | default |
| `CPU_CRIT` | CRIT above this | `85` | default |
| `MEM_WARN` | WARN above this | `75` | default |
| `MEM_CRIT` | CRIT above this | `90` | default |
| `SWAP_WARN` | WARN above this | `10` | default |
| `SWAP_CRIT` | CRIT above this | `30` | default |
| `LOAD_WARN` | WARN above this | `1.0` | default |
| `LOAD_CRIT` | CRIT above this | `2.0` | default |
| `FS_WARN` | WARN above this | `80` | default |
| `FS_CRIT` | CRIT above this | `90` | default |
| `CHECK_ALERTLOG` | 1 = count alert log ORA- errors, 0 = skip | `1` | default |
| `ALERT_WINDOW_HRS` | hours of alert log to read | `4` | default |

Any key you leave out keeps its default or its detected value. Thresholds
are explained row by row in the [RUNBOOK](../RUNBOOK.md); change them only
when a senior asks.

```
vi /home/oracle/scripts/oracle-rac/node-check/config.env
```

A wrong key or value stops the script with exit code 65 and a message that
names the key.

## Check the configuration

Before the first real run, print what the script will use and test its
connections. This runs no checks.

```
cd /home/oracle/scripts/oracle-rac/node-check && bash node-check.sh --check-config
```

Sample output (from a test run against fake data):

<!-- sample:check-config:start -->
```
SECTION  KEY                                            VALUE                                                                  STATUS
CONFIG   NODES                                          racnode1,racnode2 [detected]                                           INFO
CONFIG   GRID_HOME                                      /u01/app/19.0.0/grid [config]                                          INFO
CONFIG   SSH_PORT                                       22 [default]                                                           INFO
CONFIG   SSH_TIMEOUT                                    150 [default]                                                          INFO
CONFIG   SQL_TIMEOUT                                    120 [default]                                                          INFO
CONFIG   CPU_WARN                                       60 [default]                                                           INFO
CONFIG   CPU_CRIT                                       85 [default]                                                           INFO
CONFIG   MEM_WARN                                       75 [default]                                                           INFO
CONFIG   MEM_CRIT                                       90 [default]                                                           INFO
CONFIG   SWAP_WARN                                      10 [default]                                                           INFO
CONFIG   SWAP_CRIT                                      30 [default]                                                           INFO
CONFIG   LOAD_WARN                                      1.0 [default]                                                          INFO
CONFIG   LOAD_CRIT                                      2.0 [default]                                                          INFO
CONFIG   FS_WARN                                        80 [default]                                                           INFO
CONFIG   FS_CRIT                                        90 [default]                                                           INFO
CONFIG   CHECK_ALERTLOG                                 1 [default]                                                            INFO
CONFIG   ALERT_WINDOW_HRS                               4 [default]                                                            INFO
CONFIG   checks                                         per node: CPU, memory, swap, load, filesystems, alert log ORA- errors  INFO
TEST     racnode1                                       this host                                                              OK
TEST     ssh racnode2                                   login works                                                            OK
SUMMARY  racnode1 node-check 1.0.0 2026-10-02 23:39:17  CRIT=0 WARN=0 OK=2                                                     OK
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
cd /home/oracle/scripts/oracle-rac/node-check && bash node-check.sh
```

Sample output (from a test run against fake data):

<!-- sample:run:start -->
```
SECTION         KEY                                            VALUE                                                                          STATUS
FILESYSTEM      racnode1 /u01                                  Used=83%                                                                       WARN
OS UTILIZATION  racnode1                                       CPU: 26.63% Mem: 76.24% Swap: 0.73% Load/core: 0.01 (flagged: Mem)             WARN
FILESYSTEM      racnode1                                       5 checked, highest 83% on /u01                                                 WARN
ALERT LOG       racnode1                                       0 ORA- in 4h                                                                   OK
OS UTILIZATION  racnode2                                       CPU: 18.98% Mem: 52.83% Swap: 0.00% Load/core: 0.01                            OK
FILESYSTEM      racnode2                                       5 checked, highest 70% on /u01                                                 OK
ALERT LOG       racnode2                                       2 ORA- in 4h, latest: ORA-00060: deadlock detected while waiting for resource  WARN
SUMMARY         racnode1 node-check 1.0.0 2026-10-02 23:39:18  CRIT=0 WARN=4 OK=3                                                             WARN
```
<!-- sample:run:end -->

The last line is the summary. `bash node-check.sh --csv` prints the same rows
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
`node-check.sh` version 1.0.0, 198 lines.

| Part | Hash |
|---|---|
| whole file | `bc2851b5c52f` |
| S00 | `b875f928546a` |
| S01 settings | `b993fb00e77c` |
| S02 helpers | `d9deb6ab5c4d` |
| S03 output | `490cbc0df2aa` |
| S04 config | `ccb68e13b2fd` |
| S05 options | `869fb9d9b1f7` |
| S06 collect | `a918cdde4ebd` |
| S07 rate | `816d7451ab1c` |
| S08 os | `8e1af50dd82a` |
| S09 alert | `b2aef2327ece` |
| S10 main | `a6c0c582bd1a` |
<!-- checksums:end -->
