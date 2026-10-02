# gg-check.sh: GoldenGate extracts

Goldengate extracts via gg2.sh on the goldengate host, over ssh.

| | |
|---|---|
| Runs on | node 1 (it reaches the GoldenGate host over ssh) |
| Runs as | oracle |
| Folder on the server | `/home/oracle/scripts/oracle-rac/gg-check` |
| Needs | passwordless ssh as oracle from node 1 to the GoldenGate host. **Pre-production has no GoldenGate: do not type or run this script there.** |
| Run time | 2 to 20 seconds |
| Rows it prints | [GOLDENGATE](../RUNBOOK.md#goldengate) |

Contents: [Safety](#safety) · [Type it](#type-it) · [Configure](#configure) ·
[Check the configuration](#check-the-configuration) · [Run](#run) ·
[Checksums](#checksums) · [Changes](CHANGELOG.md)

## Safety

**Reads:** the output of `sh gg2.sh`, run on the GoldenGate host over one ssh call.

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
   mkdir -p /home/oracle/scripts/oracle-rac/gg-check && cd /home/oracle/scripts/oracle-rac/gg-check && vi gg-check.sh
   ```

2. Type the script from [gg-check.sh](gg-check.sh), one section at a time
   (`#== S01 ...`, `#== S02 ...`). After each section, save with `:w` and
   check that section's hash against the [checksum table](#checksums).

3. Check the syntax.

   ```
   bash -n gg-check.sh && echo SYNTAX OK
   ```

   Expected: `SYNTAX OK`. Anything else names the line to fix.

4. Check the whole-file hash.

   ```
   awk '{gsub(/\r/,"")}NF{$1=$1;print}' gg-check.sh | sha256sum | cut -c1-12
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
| `GG_HOST` | GoldenGate host name or IP | (blank) | **required**, you type it |
| `SSH_PORT` | ssh port of the other hosts | `22` | default |
| `SSH_TIMEOUT` | seconds per ssh call | `60` | default |
| `GG_SCRIPT` | path of gg2.sh on the GoldenGate host | `/home/oracle/scripts/gg2.sh` | default |
| `GG_LAG_WARN` | WARN above this | `60` | default |
| `GG_LAG_CRIT` | CRIT above this | `300` | default |
| `GG_CKPT_WARN_MIN` | threshold, see RUNBOOK | `5` | default |
| `GG_CKPT_CRIT_MIN` | threshold, see RUNBOOK | `15` | default |

Any key you leave out keeps its default or its detected value. Thresholds
are explained row by row in the [RUNBOOK](../RUNBOOK.md); change them only
when a senior asks.

```
vi /home/oracle/scripts/oracle-rac/gg-check/config.env
```

A wrong key or value stops the script with exit code 65 and a message that
names the key.

## Check the configuration

Before the first real run, print what the script will use and test its
connections. This runs no checks.

```
cd /home/oracle/scripts/oracle-rac/gg-check && bash gg-check.sh --check-config
```

Sample output (from a test run against fake data):

<!-- sample:check-config:start -->
```
SECTION  KEY                                          VALUE                                              STATUS
CONFIG   GG_HOST                                      gghost01 [config]                                  INFO
CONFIG   SSH_PORT                                     22 [default]                                       INFO
CONFIG   SSH_TIMEOUT                                  60 [default]                                       INFO
CONFIG   GG_SCRIPT                                    /home/oracle/scripts/gg2.sh [default]              INFO
CONFIG   GG_LAG_WARN                                  60 [default]                                       INFO
CONFIG   GG_LAG_CRIT                                  300 [default]                                      INFO
CONFIG   GG_CKPT_WARN_MIN                             5 [default]                                        INFO
CONFIG   GG_CKPT_CRIT_MIN                             15 [default]                                       INFO
CONFIG   checks                                       per extract: status, lag, checkpoint age           INFO
TEST     ssh gghost01                                 login works, /home/oracle/scripts/gg2.sh readable  OK
SUMMARY  racnode1 gg-check 1.0.0 2026-10-02 23:39:17  CRIT=0 WARN=0 OK=1                                 OK
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
cd /home/oracle/scripts/oracle-rac/gg-check && bash gg-check.sh
```

Sample output (from a test run against fake data):

<!-- sample:run:start -->
```
SECTION     KEY                                          VALUE                                                                                        STATUS
GOLDENGATE  X_EXTRACT1                                   RUNNING, lag 00:00:04, checkpoint 1m ago, started 2026-09-20 15:37, SCN 18.25 (79891234567)  OK
SUMMARY     racnode1 gg-check 1.0.0 2026-10-02 23:39:17  CRIT=0 WARN=0 OK=1                                                                           OK
```
<!-- sample:run:end -->

The last line is the summary. `bash gg-check.sh --csv` prints the same rows
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
`gg-check.sh` version 1.0.0, 140 lines.

| Part | Hash |
|---|---|
| whole file | `2c7f180aa88a` |
| S00 | `b875f928546a` |
| S01 settings | `4974e8cf99de` |
| S02 helpers | `d9deb6ab5c4d` |
| S03 output | `490cbc0df2aa` |
| S04 config | `ccb68e13b2fd` |
| S05 options | `869fb9d9b1f7` |
| S06 extract | `e645fbbe1868` |
| S07 gg | `2bc33c3b8f55` |
| S08 main | `fd7c95dc6658` |
<!-- checksums:end -->
