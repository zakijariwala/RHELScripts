# hw-check.sh: Network bonding and HugePages

Network bonding slaves, hugepages and transparent hugepages.

| | |
|---|---|
| Runs on | any RHEL server |
| Runs as | oracle on database nodes; your own login elsewhere (no root) |
| Folder on the server | `$HOME/scripts/linux/hw-check` |
| Needs | `CHECK_HUGEPAGES=0` in config.env on app and web servers |
| Run time | 1 to 2 seconds |
| Rows it prints | [BONDING](../RUNBOOK.md#bonding), [HUGEPAGES](../RUNBOOK.md#hugepages) |

Contents: [Safety](#safety) · [Type it](#type-it) · [Configure](#configure) ·
[Check the configuration](#check-the-configuration) · [Run](#run) ·
[Checksums](#checksums) · [Changes](CHANGELOG.md)

## Safety

**Reads:** `/proc/net/bonding/*`, `/proc/meminfo`, `/sys/kernel/mm/transparent_hugepage/enabled`.

**Writes:** nothing. The script prints to the screen only. It creates,
changes and deletes no file, on this host or any other, and sends no SQL
other than `SELECT`, `WITH`, SQL*Plus `SET`, `DEFINE` and `EXIT`. CI proves
this on every change with `tools/check-no-write.sh` and
`tools/check-readonly-sql.sh`; your typed copy matches the checked copy
when its hashes match the [checksum table](#checksums). How to check it
yourself: [docs/safety.md](../../../docs/safety.md).

## Type it

Follow [docs/typing-guide.md](../../../docs/typing-guide.md). In short, as
**oracle** on **any RHEL server**:

1. Create the folder and open a new file.

   ```
   mkdir -p $HOME/scripts/linux/hw-check && cd $HOME/scripts/linux/hw-check && vi hw-check.sh
   ```

2. Type the script from [hw-check.sh](hw-check.sh), one section at a time
   (`#== S01 ...`, `#== S02 ...`). After each section, save with `:w` and
   check that section's hash against the [checksum table](#checksums).

3. Check the syntax.

   ```
   bash -n hw-check.sh && echo SYNTAX OK
   ```

   Expected: `SYNTAX OK`. Anything else names the line to fix.

4. Check the whole-file hash.

   ```
   awk '{gsub(/\r/,"")}NF{$1=$1;print}' hw-check.sh | sha256sum | cut -c1-12
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
| `CHECK_HUGEPAGES` | 1 = check HugePages (DB servers), 0 = skip (app, web) | `1` | default |
| `PROC_DIR` | where /proc is; leave the default | `/proc` | default |
| `SYS_DIR` | where /sys is; leave the default | `/sys` | default |

Any key you leave out keeps its default or its detected value. Thresholds
are explained row by row in the [RUNBOOK](../RUNBOOK.md); change them only
when a senior asks.

```
vi $HOME/scripts/linux/hw-check/config.env
```

A wrong key or value stops the script with exit code 65 and a message that
names the key.

## Check the configuration

Before the first real run, print what the script will use and test its
connections. This runs no checks.

```
cd $HOME/scripts/linux/hw-check && bash hw-check.sh --check-config
```

Sample output (from a test run against fake data):

<!-- sample:check-config:start -->
```
SECTION  KEY                                          VALUE                                                        STATUS
CONFIG   CHECK_HUGEPAGES                              1 [default]                                                  INFO
CONFIG   PROC_DIR                                     /home/oracle/proc [config]                                   INFO
CONFIG   SYS_DIR                                      /home/oracle/sys [config]                                    INFO
CONFIG   checks                                       every bond and its slaves, HugePages, transparent hugepages  INFO
TEST     /home/oracle/proc/meminfo                    readable                                                     OK
TEST     /home/oracle/sys/kernel/mm                   readable                                                     OK
SUMMARY  racnode1 hw-check 1.0.0 2026-10-02 23:39:16  CRIT=0 WARN=0 OK=2                                           OK
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
cd $HOME/scripts/linux/hw-check && bash hw-check.sh
```

Sample output (from a test run against fake data):

<!-- sample:run:start -->
```
SECTION    KEY                                          VALUE                                    STATUS
BONDING    bond0                                        2 of 2 slaves up                         OK
HUGEPAGES  configured                                   40960 x 2048kB, free 1024, reserved 512  OK
HUGEPAGES  transparent                                  never                                    OK
SUMMARY    racnode1 hw-check 1.0.0 2026-10-02 23:39:16  CRIT=0 WARN=0 OK=3                       OK
```
<!-- sample:run:end -->

The last line is the summary. `bash hw-check.sh --csv` prints the same rows
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
`hw-check.sh` version 1.0.0, 145 lines.

| Part | Hash |
|---|---|
| whole file | `aeff77e33af7` |
| S00 | `b875f928546a` |
| S01 settings | `c563a01cc9ed` |
| S02 helpers | `d9deb6ab5c4d` |
| S03 output | `490cbc0df2aa` |
| S04 config | `ccb68e13b2fd` |
| S05 options | `869fb9d9b1f7` |
| S06 bonding | `2e4f9d31b33d` |
| S07 memory | `5f56ef869f49` |
| S08 main | `1b27488449e5` |
<!-- checksums:end -->
