# crs-check.sh: Clusterware resources

Clusterware resources whose target is online but state is not.

| | |
|---|---|
| Runs on | any one node |
| Runs as | oracle (grid also works) |
| Folder on the server | `/home/oracle/scripts/oracle-rac/crs-check` |
| Needs | nothing |
| Run time | 2 to 10 seconds |
| Rows it prints | [CLUSTERWARE](../RUNBOOK.md#clusterware) |

Contents: [Safety](#safety) · [Type it](#type-it) · [Configure](#configure) ·
[Check the configuration](#check-the-configuration) · [Run](#run) ·
[Checksums](#checksums) · [Changes](CHANGELOG.md)

## Safety

**Reads:** `crsctl stat res -t` (status only); `/etc/oracle/olr.loc`.

**Writes:** nothing. The script prints to the screen only. It creates,
changes and deletes no file, on this host or any other, and sends no SQL
other than `SELECT`, `WITH`, SQL*Plus `SET`, `DEFINE` and `EXIT`. CI proves
this on every change with `tools/check-no-write.sh` and
`tools/check-readonly-sql.sh`; your typed copy matches the checked copy
when its hashes match the [checksum table](#checksums). How to check it
yourself: [docs/safety.md](../../../docs/safety.md).

## Type it

Follow [docs/typing-guide.md](../../../docs/typing-guide.md). In short, as
**oracle** on **any one node**:

1. Create the folder and open a new file.

   ```
   mkdir -p /home/oracle/scripts/oracle-rac/crs-check && cd /home/oracle/scripts/oracle-rac/crs-check && vi crs-check.sh
   ```

2. Type the script from [crs-check.sh](crs-check.sh), one section at a time
   (`#== S01 ...`, `#== S02 ...`). After each section, save with `:w` and
   check that section's hash against the [checksum table](#checksums).

3. Check the syntax.

   ```
   bash -n crs-check.sh && echo SYNTAX OK
   ```

   Expected: `SYNTAX OK`. Anything else names the line to fix.

4. Check the whole-file hash.

   ```
   awk '{gsub(/\r/,"")}NF{$1=$1;print}' crs-check.sh | sha256sum | cut -c1-12
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
| `GRID_HOME` | Grid Infrastructure home | (blank) | detected from /etc/oracle/olr.loc |
| `CRS_TIMEOUT` | seconds for crsctl | `60` | default |

Any key you leave out keeps its default or its detected value. Thresholds
are explained row by row in the [RUNBOOK](../RUNBOOK.md); change them only
when a senior asks.

```
vi /home/oracle/scripts/oracle-rac/crs-check/config.env
```

A wrong key or value stops the script with exit code 65 and a message that
names the key.

## Check the configuration

Before the first real run, print what the script will use and test its
connections. This runs no checks.

```
cd /home/oracle/scripts/oracle-rac/crs-check && bash crs-check.sh --check-config
```

Sample output (from a test run against fake data):

<!-- sample:check-config:start -->
```
SECTION  KEY                                           VALUE                                                       STATUS
CONFIG   GRID_HOME                                     /u01/app/19.0.0/grid [config]                               INFO
CONFIG   CRS_TIMEOUT                                   60 [default]                                                INFO
CONFIG   checks                                        every resource in crsctl stat res -t: TARGET against STATE  INFO
TEST     crsctl                                        found in /u01/app/19.0.0/grid/bin                           OK
SUMMARY  racnode1 crs-check 1.0.0 2026-10-02 23:39:16  CRIT=0 WARN=0 OK=1                                          OK
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
cd /home/oracle/scripts/oracle-rac/crs-check && bash crs-check.sh
```

Sample output (from a test run against fake data):

<!-- sample:run:start -->
```
SECTION      KEY                                           VALUE               STATUS
CLUSTERWARE  Resources with TARGET=ONLINE                  all ONLINE          OK
SUMMARY      racnode1 crs-check 1.0.0 2026-10-02 23:39:16  CRIT=0 WARN=0 OK=1  OK
```
<!-- sample:run:end -->

The last line is the summary. `bash crs-check.sh --csv` prints the same rows
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
`crs-check.sh` version 1.0.0, 133 lines.

| Part | Hash |
|---|---|
| whole file | `4b2a01d0186d` |
| S00 | `b875f928546a` |
| S01 settings | `4b7e61379ce8` |
| S02 helpers | `d9deb6ab5c4d` |
| S03 output | `490cbc0df2aa` |
| S04 config | `ccb68e13b2fd` |
| S05 options | `869fb9d9b1f7` |
| S06 parse | `2e4f5cb34b28` |
| S07 crs | `ed07f8a2df10` |
| S08 main | `c619d231cc65` |
<!-- checksums:end -->
