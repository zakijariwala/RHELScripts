# inputs-check.sh: Inputs from other jobs: sftp log, active sessions, app servers

Sftp log size, active session peaks, app servers, from other jobs.

| | |
|---|---|
| Runs on | the node that holds `sftp_output` and `server_checklist` (node 1) |
| Runs as | oracle |
| Folder on the server | `/home/oracle/scripts/oracle-rac/inputs-check` |
| Needs | the two input files and `activesession.sh` (a missing one shows CRIT `file missing`) |
| Run time | 2 to 120 seconds |
| Rows it prints | [SFTP LOG](../RUNBOOK.md#sftp-log), [ACTIVE SESSIONS](../RUNBOOK.md#active-sessions), [APP SERVERS](../RUNBOOK.md#app-servers) |

Contents: [Safety](#safety) · [Type it](#type-it) · [Configure](#configure) ·
[Check the configuration](#check-the-configuration) · [Run](#run) ·
[Checksums](#checksums) · [Changes](CHANGELOG.md)

## Safety

**Reads:** the files `SFTP_FILE` and `SERVER_FILE`; the output of `sh activesession.sh`.

**Writes:** nothing. The script prints to the screen only. It creates,
changes and deletes no file, on this host or any other, and sends no SQL
other than `SELECT`, `WITH`, SQL*Plus `SET`, `DEFINE` and `EXIT`. CI proves
this on every change with `tools/check-no-write.sh` and
`tools/check-readonly-sql.sh`; your typed copy matches the checked copy
when its hashes match the [checksum table](#checksums). How to check it
yourself: [docs/safety.md](../../../docs/safety.md).

## Type it

Follow [docs/typing-guide.md](../../../docs/typing-guide.md). In short, as
**oracle** on **the node that holds `sftp_output` and `server_checklist`**:

1. Create the folder and open a new file.

   ```
   mkdir -p /home/oracle/scripts/oracle-rac/inputs-check && cd /home/oracle/scripts/oracle-rac/inputs-check && vi inputs-check.sh
   ```

2. Type the script from [inputs-check.sh](inputs-check.sh), one section at a time
   (`#== S01 ...`, `#== S02 ...`). After each section, save with `:w` and
   check that section's hash against the [checksum table](#checksums).

3. Check the syntax.

   ```
   bash -n inputs-check.sh && echo SYNTAX OK
   ```

   Expected: `SYNTAX OK`. Anything else names the line to fix.

4. Check the whole-file hash.

   ```
   awk '{gsub(/\r/,"")}NF{$1=$1;print}' inputs-check.sh | sha256sum | cut -c1-12
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
| `SFTP_FILE` | file written by the sftp size job | `/home/oracle/sftp_output` | default |
| `SERVER_FILE` | file written by the app server job | `/home/oracle/server_checklist` | default |
| `ACTIVESESSION_SCRIPT` | path of activesession.sh | `/home/oracle/scripts/activesession.sh` | default |
| `ACTIVESESSION_TIMEOUT` | seconds for activesession.sh | `120` | default |
| `STALE_MIN` | input file older than this many minutes = CRIT | `60` | default |
| `SFTP_LOG_WARN_MB` | sftp.log size in MB above which = WARN | `1024` | default |

Any key you leave out keeps its default or its detected value. Thresholds
are explained row by row in the [RUNBOOK](../RUNBOOK.md); change them only
when a senior asks.

```
vi /home/oracle/scripts/oracle-rac/inputs-check/config.env
```

A wrong key or value stops the script with exit code 65 and a message that
names the key.

## Check the configuration

Before the first real run, print what the script will use and test its
connections. This runs no checks.

```
cd /home/oracle/scripts/oracle-rac/inputs-check && bash inputs-check.sh --check-config
```

Sample output (from a test run against fake data):

<!-- sample:check-config:start -->
```
SECTION  KEY                                              VALUE                                                            STATUS
CONFIG   SFTP_FILE                                        /home/oracle/sftp_output [config]                                INFO
CONFIG   SERVER_FILE                                      /home/oracle/server_checklist [config]                           INFO
CONFIG   ACTIVESESSION_SCRIPT                             /home/oracle/scripts/activesession.sh [config]                   INFO
CONFIG   ACTIVESESSION_TIMEOUT                            120 [default]                                                    INFO
CONFIG   STALE_MIN                                        60 [default]                                                     INFO
CONFIG   SFTP_LOG_WARN_MB                                 1024 [default]                                                   INFO
CONFIG   checks                                           sftp_output, activesession.sh, server_checklist, file freshness  INFO
TEST     /home/oracle/sftp_output                         readable                                                         OK
TEST     /home/oracle/server_checklist                    readable                                                         OK
TEST     /home/oracle/scripts/activesession.sh            readable                                                         OK
SUMMARY  racnode1 inputs-check 1.0.0 2026-10-02 23:39:17  CRIT=0 WARN=0 OK=3                                               OK
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
cd /home/oracle/scripts/oracle-rac/inputs-check && bash inputs-check.sh
```

Sample output (from a test run against fake data):

<!-- sample:run:start -->
```
SECTION          KEY                                              VALUE                                                               STATUS
SFTP LOG         /var/log/sftp.log                                size 1003M, modified Oct 2 23:50, producer says: Normal             OK
ACTIVE SESSIONS  Last 2h (2151 - 2351)                            highest 2331 --> 20 rows [NORMAL], lowest 2200 --> 6 rows [NORMAL]  OK
APP SERVERS      Accessible                                       9 of 9, inaccessible 0                                              OK
SUMMARY          racnode1 inputs-check 1.0.0 2026-10-02 23:39:17  CRIT=0 WARN=0 OK=3                                                  OK
```
<!-- sample:run:end -->

The last line is the summary. `bash inputs-check.sh --csv` prints the same rows
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
`inputs-check.sh` version 1.0.0, 179 lines.

| Part | Hash |
|---|---|
| whole file | `76dc2b7fab27` |
| S00 | `b875f928546a` |
| S01 settings | `6fac923408b9` |
| S02 helpers | `d9deb6ab5c4d` |
| S03 output | `490cbc0df2aa` |
| S04 config | `ccb68e13b2fd` |
| S05 options | `869fb9d9b1f7` |
| S06 tools | `caebeddfa2ff` |
| S07 sftp | `b20095a2bec3` |
| S08 sessions | `1315102d103e` |
| S09 servers | `4212ca0a2837` |
| S10 main | `8407888b87db` |
<!-- checksums:end -->
