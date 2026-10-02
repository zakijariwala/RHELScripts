# host-check.sh: Pending reboot, time sync, processes, systemd, kernel log

Reboot pending, time sync, processes, systemd units, kdump, kernel log.

| | |
|---|---|
| Runs on | any RHEL server: database nodes, app1 to app10, web1 to web4 |
| Runs as | oracle on database nodes; your own login elsewhere (no root) |
| Folder on the server | `$HOME/scripts/linux/host-check` |
| Needs | the user in group `systemd-journal` (or `adm`) to read the kernel log; site agent names in `PROCS` |
| Run time | 5 to 15 seconds |
| Rows it prints | [KERNEL](../RUNBOOK.md#kernel), [TIME SYNC](../RUNBOOK.md#time-sync), [PROCESS](../RUNBOOK.md#process), [SYSTEMD](../RUNBOOK.md#systemd), [KERNEL LOG](../RUNBOOK.md#kernel-log) |

Contents: [Safety](#safety) · [Type it](#type-it) · [Configure](#configure) ·
[Check the configuration](#check-the-configuration) · [Run](#run) ·
[Checksums](#checksums) · [Changes](CHANGELOG.md)

## Safety

**Reads:** `uname -r`, `rpm -q --last kernel-core`, `needs-restarting -r`, `chronyc tracking`, `pgrep -xc`, `systemctl list-units --state=failed`, `systemctl is-active kdump`, `journalctl -k -p err`, `id`.

**Writes:** nothing. The script prints to the screen only. It creates,
changes and deletes no file, on this host or any other, and sends no SQL
other than `SELECT`, `WITH`, SQL*Plus `SET`, `DEFINE` and `EXIT`. CI proves
this on every change with `tools/check-no-write.sh` and
`tools/check-readonly-sql.sh`; your typed copy matches the checked copy
when its hashes match the [checksum table](#checksums). How to check it
yourself: [docs/safety.md](../../../docs/safety.md).

## Type it

Follow [docs/typing-guide.md](../../../docs/typing-guide.md). In short, as
**oracle** on **any RHEL server: database nodes, app1 to app10, web1 to web4**:

1. Create the folder and open a new file.

   ```
   mkdir -p $HOME/scripts/linux/host-check && cd $HOME/scripts/linux/host-check && vi host-check.sh
   ```

2. Type the script from [host-check.sh](host-check.sh), one section at a time
   (`#== S01 ...`, `#== S02 ...`). After each section, save with `:w` and
   check that section's hash against the [checksum table](#checksums).

3. Check the syntax.

   ```
   bash -n host-check.sh && echo SYNTAX OK
   ```

   Expected: `SYNTAX OK`. Anything else names the line to fix.

4. Check the whole-file hash.

   ```
   awk '{gsub(/\r/,"")}NF{$1=$1;print}' host-check.sh | sha256sum | cut -c1-12
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
| `PROCS` | process names that must run, comma separated | `crond,chronyd,sshd` | site agents come from the inventory |
| `TIME_WARN_MS` | clock offset in ms above which = WARN | `100` | default |
| `TIME_CRIT_MS` | clock offset in ms above which = CRIT | `1000` | default |
| `CHECK_KDUMP` | 1 = kdump must be active, 0 = skip | `1` | default |
| `KLOG_HRS` | hours of kernel log to read | `24` | default |

Any key you leave out keeps its default or its detected value. Thresholds
are explained row by row in the [RUNBOOK](../RUNBOOK.md); change them only
when a senior asks.

```
vi $HOME/scripts/linux/host-check/config.env
```

A wrong key or value stops the script with exit code 65 and a message that
names the key.

## Check the configuration

Before the first real run, print what the script will use and test its
connections. This runs no checks.

```
cd $HOME/scripts/linux/host-check && bash host-check.sh --check-config
```

Sample output (from a test run against fake data):

<!-- sample:check-config:start -->
```
SECTION  KEY                                            VALUE                                                               STATUS
CONFIG   PROCS                                          crond,chronyd,sshd [default]                                        INFO
CONFIG   TIME_WARN_MS                                   100 [default]                                                       INFO
CONFIG   TIME_CRIT_MS                                   1000 [default]                                                      INFO
CONFIG   CHECK_KDUMP                                    1 [default]                                                         INFO
CONFIG   KLOG_HRS                                       24 [default]                                                        INFO
CONFIG   checks                                         kernel, reboot, chrony, processes, failed units, kdump, kernel log  INFO
TEST     uname                                          found                                                               OK
TEST     rpm                                            found                                                               OK
TEST     chronyc                                        found                                                               OK
TEST     pgrep                                          found                                                               OK
TEST     systemctl                                      found                                                               OK
TEST     journalctl                                     found                                                               OK
SUMMARY  racnode1 host-check 1.0.0 2026-10-02 23:39:16  CRIT=0 WARN=0 OK=6                                                  OK
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
cd $HOME/scripts/linux/host-check && bash host-check.sh
```

Sample output (from a test run against fake data):

<!-- sample:run:start -->
```
SECTION     KEY                                            VALUE                                           STATUS
KERNEL      running                                        4.18.0-553.el8_10.x86_64, the newest installed  OK
KERNEL      needs-restarting                               no reboot needed                                OK
TIME SYNC   chrony                                         offset 0.04 ms, source C0000201 (192.0.2.1)     OK
PROCESS     crond                                          1 running                                       OK
PROCESS     chronyd                                        1 running                                       OK
PROCESS     sshd                                           1 running                                       OK
SYSTEMD     failed units                                   none                                            OK
SYSTEMD     kdump                                          active                                          OK
KERNEL LOG  errors                                         0 in 24h                                        OK
SUMMARY     racnode1 host-check 1.0.0 2026-10-02 23:39:16  CRIT=0 WARN=0 OK=9                              OK
```
<!-- sample:run:end -->

The last line is the summary. `bash host-check.sh --csv` prints the same rows
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
`host-check.sh` version 1.0.0, 190 lines.

| Part | Hash |
|---|---|
| whole file | `706f6721fec4` |
| S00 | `b875f928546a` |
| S01 settings | `f86244e4e8a0` |
| S02 helpers | `d9deb6ab5c4d` |
| S03 output | `490cbc0df2aa` |
| S04 config | `ccb68e13b2fd` |
| S05 options | `869fb9d9b1f7` |
| S06 kernel | `8643e2bf8437` |
| S07 time | `550af2011882` |
| S08 procs | `79826669e5a0` |
| S09 systemd | `ec4bd2df9a8f` |
| S10 klog | `508287dc5022` |
| S11 main | `149899d522d7` |
<!-- checksums:end -->
