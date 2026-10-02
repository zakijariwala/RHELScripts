# disk-check.sh: Disk and inode use, read-only filesystems, SCSI and multipath paths

Disk and inode use, read-only filesystems, scsi and multipath paths.

| | |
|---|---|
| Runs on | any RHEL server |
| Runs as | oracle on database nodes; your own login elsewhere (no root) |
| Folder on the server | `$HOME/scripts/linux/disk-check` |
| Needs | nothing |
| Run time | 2 to 5 seconds |
| Rows it prints | [FILESYSTEM](../RUNBOOK.md#filesystem), [INODES](../RUNBOOK.md#inodes), [READ ONLY FS](../RUNBOOK.md#read-only-fs), [SCSI PATH](../RUNBOOK.md#scsi-path), [MULTIPATH](../RUNBOOK.md#multipath) |

Contents: [Safety](#safety) · [Type it](#type-it) · [Configure](#configure) ·
[Check the configuration](#check-the-configuration) · [Run](#run) ·
[Checksums](#checksums) · [Changes](CHANGELOG.md)

## Safety

**Reads:** `df -P -l`, `df -P -i -l`, `/proc/mounts`, `/sys/block/*/device/state`, `/sys/block/dm-*/dm/` and `slaves/`.

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
   mkdir -p $HOME/scripts/linux/disk-check && cd $HOME/scripts/linux/disk-check && vi disk-check.sh
   ```

2. Type the script from [disk-check.sh](disk-check.sh), one section at a time
   (`#== S01 ...`, `#== S02 ...`). After each section, save with `:w` and
   check that section's hash against the [checksum table](#checksums).

3. Check the syntax.

   ```
   bash -n disk-check.sh && echo SYNTAX OK
   ```

   Expected: `SYNTAX OK`. Anything else names the line to fix.

4. Check the whole-file hash.

   ```
   awk '{gsub(/\r/,"")}NF{$1=$1;print}' disk-check.sh | sha256sum | cut -c1-12
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
| `FS_WARN` | WARN above this | `80` | default |
| `FS_CRIT` | CRIT above this | `90` | default |
| `INODE_WARN` | inode use % above which = WARN | `80` | default |
| `INODE_CRIT` | inode use % above which = CRIT | `90` | default |
| `MPATH_MIN` | running paths a multipath device needs; fewer = WARN | `2` | default |
| `PROC_DIR` | where /proc is; leave the default | `/proc` | default |
| `SYS_DIR` | where /sys is; leave the default | `/sys` | default |

Any key you leave out keeps its default or its detected value. Thresholds
are explained row by row in the [RUNBOOK](../RUNBOOK.md); change them only
when a senior asks.

```
vi $HOME/scripts/linux/disk-check/config.env
```

A wrong key or value stops the script with exit code 65 and a message that
names the key.

## Check the configuration

Before the first real run, print what the script will use and test its
connections. This runs no checks.

```
cd $HOME/scripts/linux/disk-check && bash disk-check.sh --check-config
```

Sample output (from a test run against fake data):

<!-- sample:check-config:start -->
```
SECTION  KEY                                            VALUE                                                               STATUS
CONFIG   FS_WARN                                        80 [default]                                                        INFO
CONFIG   FS_CRIT                                        90 [default]                                                        INFO
CONFIG   INODE_WARN                                     80 [default]                                                        INFO
CONFIG   INODE_CRIT                                     90 [default]                                                        INFO
CONFIG   MPATH_MIN                                      2 [default]                                                         INFO
CONFIG   PROC_DIR                                       /home/oracle/proc [config]                                          INFO
CONFIG   SYS_DIR                                        /home/oracle/sys [config]                                           INFO
CONFIG   checks                                         space and inodes per mount, read-only filesystems, SCSI, multipath  INFO
TEST     /home/oracle/proc/mounts                       readable                                                            OK
TEST     /home/oracle/sys/block                         readable                                                            OK
SUMMARY  racnode1 disk-check 1.0.0 2026-10-02 23:39:15  CRIT=0 WARN=0 OK=2                                                  OK
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
cd $HOME/scripts/linux/disk-check && bash disk-check.sh
```

Sample output (from a test run against fake data):

<!-- sample:run:start -->
```
SECTION       KEY                                            VALUE                           STATUS
FILESYSTEM    /u01                                           Used=83%                        WARN
FILESYSTEM    local                                          5 checked, highest 83% on /u01  WARN
INODES        local                                          4 checked, highest 9% on /u01   OK
READ-ONLY FS  local                                          none read-only                  OK
SCSI PATH     all                                            5 paths running                 OK
MULTIPATH     mpatha0                                        2 of 2 paths running            OK
MULTIPATH     mpatha1                                        2 of 2 paths running            OK
SUMMARY       racnode1 disk-check 1.0.0 2026-10-02 23:39:15  CRIT=0 WARN=2 OK=5              WARN
```
<!-- sample:run:end -->

The last line is the summary. `bash disk-check.sh --csv` prints the same rows
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
`disk-check.sh` version 1.0.0, 165 lines.

| Part | Hash |
|---|---|
| whole file | `2b2a6d94c18f` |
| S00 | `b875f928546a` |
| S01 settings | `31c7adaad0c7` |
| S02 helpers | `d9deb6ab5c4d` |
| S03 output | `490cbc0df2aa` |
| S04 config | `ccb68e13b2fd` |
| S05 options | `869fb9d9b1f7` |
| S06 filesystems | `f03bf3f65129` |
| S07 paths | `8d2c9e87b81d` |
| S08 multipath | `9100d59b1c65` |
| S09 main | `279a08b6b977` |
<!-- checksums:end -->
