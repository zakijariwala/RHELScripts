# Oracle RAC checklist

`checklist.sh` checks a two-node Oracle [RAC](../../docs/glossary.md#rac)
cluster in one run and prints one row per check, each marked OK, WARN, CRIT
or INFO. It replaces the hand-built checklist mail: it can build and send
that mail itself, as an HTML table that lines up in Outlook.

It runs on **node 1** as the **oracle** user. It reads the database, the
cluster and both servers. It changes none of them.

- What each output row means and what to do about it: [RUNBOOK.md](RUNBOOK.md)
- What changed since the first version: [CHANGELOG.md](CHANGELOG.md)
- How the code works, for someone learning bash: [HOW-IT-WORKS.md](HOW-IT-WORKS.md)
- Statuses, exit codes and output formats: [docs/reading-output.md](../../docs/reading-output.md)
- Sample output from a test run: [sample-output/](sample-output/)

## Contents

1. [What it checks](#what-it-checks)
2. [What it reads and what it writes](#what-it-reads-and-what-it-writes)
3. [Files in this folder](#files-in-this-folder)
4. [Prerequisites](#prerequisites)
5. [Set up](#set-up)
6. [Run](#run)
7. [Pre-production test plan](#pre-production-test-plan)
8. [Mail setup](#mail-setup)
9. [Troubleshooting](#troubleshooting)
10. [Before you run this on production](#before-you-run-this-on-production)

## What it checks

| Area | Rows | Source |
|---|---|---|
| Database | open mode, log mode, instances up, TEMP, tablespaces, sessions, limits, blocking, long calls, archive destinations, [Data Guard](../../docs/glossary.md#data-guard) sync, [FRA](../../docs/glossary.md#fra), [ASM](../../docs/glossary.md#asm) diskgroups, [RMAN](../../docs/glossary.md#rman) backups, alert log | one `sqlplus` session on node 1 |
| Cluster | every [Clusterware](../../docs/glossary.md#clusterware) resource that should be ONLINE | `crsctl stat res -t` on node 1 |
| Servers | CPU, memory, swap, load, filesystems | `sar`, `free`, `df` on node 1, and on node 2 over one ssh call |
| [GoldenGate](../../docs/glossary.md#goldengate) | extract status, lag, checkpoint age | `gg2.sh` on the GoldenGate host over ssh |
| sftp log | size of `/var/log/sftp.log` | file `sftp_output`, written by another job |
| Active sessions | peaks in the last 2 hours | `activesession.sh` on node 1 |
| App servers | how many respond | file `server_checklist`, written by another job |

## What it reads and what it writes

**Reads**

- The database, through `sqlplus -s -L / as sysdba`: 20 `SELECT` and 1
  `WITH` query, plus 10 `SET` lines and `EXIT`. No other statement.
  Prove it: `tools/check-readonly-sql.sh scripts/oracle-rac-checklist/checklist.sh`
  (see [docs/safety.md](../../docs/safety.md)).
- `crsctl stat res -t` (status only).
- `sar -u 1 3`, `free -m`, `df -P -l`, `/proc/loadavg`, `nproc` on node 1,
  and the same on node 2 through `ssh ... bash -s`.
- `sh gg2.sh` on the GoldenGate host through ssh.
- `sh activesession.sh` on node 1.
- The files `sftp_output`, `server_checklist`, `config.env`, `/etc/oracle/olr.loc`.

`gg2.sh` and `activesession.sh` are separate scripts that already live on
your servers. This repo does not contain them, so its tools cannot audit
them. Read them yourself (step 3 in [safety.md](../../docs/safety.md#audit-any-script-yourself)).

**Writes**

| What | When | Path |
|---|---|---|
| Lock file (empty) | every run | `/tmp/checklist_oracle.lock` |
| History log, one line per row | unless `--no-history` or `WRITE_HISTORY=0` | `LOG_DIR/checklist_YYYYMMDD.log` |
| Deletes history logs older than `LOG_RETENTION_DAYS` | same as above | `LOG_DIR/checklist_*.log` only |
| One mail | only with `--mail` or `--mail-if-issues` | through `/usr/sbin/sendmail` |

With `--no-history` and no mail flag, the lock file is the only thing it
writes.

## Files in this folder

| File | What it is |
|---|---|
| `checklist.sh` | The script. |
| `config.env.example` | Settings template. You copy it to `config.env` and fill it in. |
| `config.env` | Your real settings. You create it. Git never stores it. |
| `README.md` | This page. |
| `RUNBOOK.md` | Every row the script can print: meaning, how measured, what to do. |
| `CHANGELOG.md` | Changes from v1 to v2.1. |
| `HOW-IT-WORKS.md` | A walk through the code. |
| `sample-output/` | CSV, table and HTML from a test run against fake data. |

## Prerequisites

You check each of these in [Set up](#set-up), step 4 onwards.

| Need | Why |
|---|---|
| RHEL 8 or 9 on both nodes | bash 4.4 or newer, GNU coreutils |
| Oracle 19c (12.2 or newer works) | some queries use views that 12.2 added |
| `sysstat` package on both nodes | provides `sar`. Missing = CPU shows `?` and the row is WARN. Install: [docs/offline-install.md](../../docs/offline-install.md) |
| oracle on node 1 can ssh to node 2 with no password | node 2 checks |
| oracle on node 1 can ssh to the GoldenGate host with no password | GoldenGate check (skip with `CHECK_GG=0`) |
| `ORACLE_SID` set in the oracle user's login profile | `sqlplus / as sysdba` needs it |
| `sudo` rights to become oracle (`sudo -iu oracle`) | you run everything as oracle |

## Set up

You do this once per cluster. Steps 1 and 2 run on **your machine**. All
later steps run on **node 1**.

### Copy the files to node 1

1. **Your user, your machine**, inside your clone of this repo: copy the
   folder to node 1. Replace `CHANGE_ME_YOUR_USER` with your login name on
   node 1 and `CHANGE_ME_NODE1_HOST` with node 1's host name or IP (ask the
   DBA team, or see the server inventory).

   ```
   scp -r scripts/oracle-rac-checklist CHANGE_ME_YOUR_USER@CHANGE_ME_NODE1_HOST:/tmp/
   ```

   Expected output: one line per file, each ending in `100%`.

   ```
   checklist.sh                         100%   41KB   2.1MB/s   00:00
   config.env.example                   100%   8KB    1.0MB/s   00:00
   ...
   ```

   If you see `Permission denied (publickey,password)`, your login or
   password is wrong. If you see `Connection timed out`, your machine cannot
   reach node 1; use the jump host your team uses.

2. **Your user, your machine**: log in to node 1.

   ```
   ssh CHANGE_ME_YOUR_USER@CHANGE_ME_NODE1_HOST
   ```

   Expected: a prompt on node 1, for example `[youruser@racnode1 ~]$`.

3. **Your user, node 1**: move the folder into the oracle user's scripts
   folder and give it to oracle. The folder sits next to the old v1
   `checklist.sh`, which stays untouched.

   ```
   sudo mkdir -p /home/oracle/scripts
   ```

   ```
   sudo cp -r /tmp/oracle-rac-checklist /home/oracle/scripts/
   ```

   ```
   sudo chown -R oracle: /home/oracle/scripts/oracle-rac-checklist
   ```

   ```
   rm -r /tmp/oracle-rac-checklist
   ```

   No output from any of them means success. If you see
   `user is not in the sudoers file`, ask your team lead for sudo rights to
   become oracle.

### Check the prerequisites

4. **Your user, node 1**: become the oracle user. Every step from here
   runs as oracle.

   ```
   sudo -iu oracle
   ```

   Expected: the prompt changes to `[oracle@racnode1 ~]$`.

5. **oracle, node 1**: go to the script folder.

   ```
   cd /home/oracle/scripts/oracle-rac-checklist
   ```

6. **oracle, node 1**: check the script arrived intact.

   ```
   file checklist.sh
   ```

   Expected:

   ```
   checklist.sh: Bourne-Again shell script, ASCII text executable, with very long lines
   ```

   If the line also says `with CRLF line terminators`, the file passed
   through Windows. Fix it, then repeat this step:

   ```
   sed -i 's/\r$//' checklist.sh
   ```

7. **oracle, node 1**: check bash is version 4.4 or newer.

   ```
   bash --version | head -1
   ```

   Expected on RHEL 8: `GNU bash, version 4.4.20(1)-release ...`
   Expected on RHEL 9: `GNU bash, version 5.1.8(1)-release ...`

8. **oracle, node 1**: check the database is reachable and see its version.

   ```
   echo $ORACLE_SID
   ```

   Expected: the instance name on this node, for example `DEMODB1`. If you
   see an empty line, the oracle profile does not set
   [ORACLE_SID](../../docs/glossary.md#oracle_sid). Ask the DBA team.

   ```
   sqlplus -s / as sysdba <<< "SELECT version FROM v\$instance;"
   ```

   Expected:

   ```

   VERSION
   -----------------
   19.0.0.0.0
   ```

   Any version from 12.2 upwards works. If you see
   `ORA-01034: ORACLE not available`, the instance on this node is down or
   `ORACLE_SID` is wrong. If you see `sqlplus: command not found`, the oracle
   profile does not put `$ORACLE_HOME/bin` on the PATH. Ask the DBA team.

9. **oracle, node 1**: check `sar` exists on node 1.

   ```
   sar -u 1 1 | tail -1
   ```

   Expected: a line starting `Average:` with numbers. If you see
   `sar: command not found`, install sysstat ([offline-install.md](../../docs/offline-install.md)).

10. **oracle, node 1**: check ssh to node 2 works with no password. Replace
    `CHANGE_ME_NODE2_IP` with node 2's IP or host name; `olsnodes -n` lists
    the node names.

    ```
    ssh -o BatchMode=yes -o ConnectTimeout=10 -p 22 CHANGE_ME_NODE2_IP hostname
    ```

    Expected: node 2's host name, for example `racnode2`.

    If you see `Permission denied (publickey,...)`, oracle has no key-based
    login to node 2. RAC installs set this up for oracle in most cases. If it is
    missing, ask the DBA team: adding a key changes `~/.ssh` on node 2 and
    needs a change request.

    If you see `Host key verification failed`, run the same command without
    `-o BatchMode=yes` once, check the fingerprint with the DBA team, and
    answer `yes`.

11. **oracle, node 1**: check `sar` exists on node 2.

    ```
    ssh -o BatchMode=yes -o ConnectTimeout=10 -p 22 CHANGE_ME_NODE2_IP "sar -u 1 1 | tail -1"
    ```

    Expected: a line starting `Average:`.

12. **oracle, node 1**: find the Grid home, where `crsctl` lives.

    ```
    grep crs_home /etc/oracle/olr.loc
    ```

    Expected: `crs_home=/u01/app/19.0.0/grid` (your path may differ). The
    script reads this file itself. If the file does not exist, note the Grid
    home from the DBA team for `GRID_HOME` in step 15.

13. **oracle, node 1** (skip if the cluster has no GoldenGate): check ssh to
    the GoldenGate host and that `gg2.sh` exists there.

    ```
    ssh -o BatchMode=yes -o ConnectTimeout=10 -p 22 CHANGE_ME_GG_IP "ls -l /home/oracle/scripts/gg2.sh"
    ```

    Expected: one `ls` line for `gg2.sh`. If you see
    `No such file or directory`, ask the DBA team for its path and set
    `GG_SCRIPT` in step 15.

14. **oracle, node 1**: check the three local inputs exist.

    ```
    ls -l /home/oracle/sftp_output /home/oracle/server_checklist /home/oracle/scripts/activesession.sh
    ```

    Expected: three `ls` lines. The two files should show a time within
    the last hour, because other jobs rewrite them. A missing file is fine
    for a first test: its row shows CRIT `file missing` and the rest of the
    report still works.

### Create config.env

15. **oracle, node 1**: create your settings file from the template.

    ```
    cp config.env.example config.env
    ```

    ```
    chmod 600 config.env
    ```

    No output means success.

16. **oracle, node 1**: open it and replace every `CHANGE_ME_` value. Each
    line in the file says what the value is and how to find it.

    ```
    vi config.env
    ```

    At minimum set `NODE2_HOST`, `GG_HOST` (or `CHECK_GG=0`), `APP_USER`
    and `SUBJECT_TAG`. Leave the thresholds alone for the first run.

17. **oracle, node 1**: check no placeholder is left.

    ```
    grep -n CHANGE_ME config.env
    ```

    Expected: no output. Each line it prints still holds a placeholder.

### First run

18. **oracle, node 1**: run it once, as a table, with no history log.

    ```
    bash ./checklist.sh --table --no-history
    ```

    Expected: 40 to 60 rows, starting:

    ```
    SECTION          KEY                                VALUE                                          STATUS
    SUMMARY          racnode1 / DEMODB / 02-10-2026 ... CRIT=0 WARN=2 OK=41                            WARN
    CONFIG           config.env                         loaded from /home/oracle/scripts/oracle-rac... INFO
    DB STATUS        OPEN_MODE inst 1                   READ WRITE                                     OK
    ...
    ```

    The full sample is in [sample-output/checklist.txt](sample-output/checklist.txt).
    Read each WARN and CRIT row in [RUNBOOK.md](RUNBOOK.md).

    If you see `config.env line N: ...` and nothing else, the file has an
    error on line N. The message says what is wrong. Fix it and repeat.

    If you see `checklist.sh is already running`, another run is still
    going. Wait a few minutes and repeat.

19. **oracle, node 1**: see the exit code of that run.

    ```
    echo $?
    ```

    Expected: `0` (all OK), `1` (some WARN) or `2` (some CRIT). See
    [reading-output.md](../../docs/reading-output.md#exit-codes).

## Run

Run as **oracle** on **node 1**, from the script folder. From your own
user in one line:

```
sudo -iu oracle bash -c "cd /home/oracle/scripts/oracle-rac-checklist && bash ./checklist.sh --table"
```

| Command | Output |
|---|---|
| `bash ./checklist.sh` | CSV, same columns as v1 |
| `bash ./checklist.sh --table` | aligned table for the screen |
| `bash ./checklist.sh --html > report.html` | HTML page |
| `bash ./checklist.sh --mail` | CSV on screen, and the HTML report by mail |
| `bash ./checklist.sh --mail-if-issues` | mail only when a row is WARN or CRIT |
| `bash ./checklist.sh --no-history` | add to any of the above: skip the history log |
| `bash ./checklist.sh --help` | usage |

Always use `bash`, not `sh`. The script switches to bash itself if you
forget, so `sh ./checklist.sh` still works.

A run takes 10 to 60 seconds. The alert log query is the slow part; see
the pre-production test plan, step 7.

## Pre-production test plan

Run this on the pre-production cluster before production. It proves the
script works on your servers and that each alert fires. Nothing in it
touches the database beyond the read-only queries. Every step runs as
**oracle** on **pre-production node 1**, in
`/home/oracle/scripts/oracle-rac-checklist`.

Pre-production in most banks differs from production: no GoldenGate, often
no standby, sometimes no backups. The plan sets the toggles for that.

### Configure for pre-production

1. Complete [Set up](#set-up) steps 1 to 17 on pre-production.

2. Find out whether pre-production has a standby database.

   ```
   sqlplus -s / as sysdba <<< "SELECT dest_id FROM v\$archive_dest WHERE target='STANDBY' AND status<>'INACTIVE';"
   ```

   `no rows selected` means no standby: set `CHECK_DG=0` in `config.env`.
   A number means a standby exists: leave `CHECK_DG=1`.

3. Find out whether pre-production takes RMAN backups.

   ```
   sqlplus -s / as sysdba <<< "SELECT MAX(end_time) FROM v\$rman_backup_job_details;"
   ```

   An empty result or a date weeks old means no regular backups: set
   `CHECK_RMAN=0`.

4. Set `CHECK_GG=0` unless pre-production runs GoldenGate.

   ```
   vi config.env
   ```

### Baseline run

5. Run it and time it.

   ```
   time bash ./checklist.sh --table --no-history
   ```

   Expected: the table, then three time lines:

   ```
   real    0m24.512s
   user    0m1.102s
   sys     0m0.731s
   ```

   Expected rows on a typical pre-production cluster:

   | Row | Expected |
   |---|---|
   | `GOLDENGATE  GoldenGate  check disabled (CHECK_GG=0)` | INFO |
   | `DB SYNC STATUS  Data Guard  check disabled (CHECK_DG=0)` | INFO, if you set CHECK_DG=0 |
   | `SFTP LOG ... file missing`, `APP SERVERS ... file missing` | CRIT, if pre-production has no such jobs |
   | Every `DB STATUS`, `INSTANCE STATUS`, `CLUSTERWARE` row | OK |

6. Save the output for the change request.

   ```
   bash ./checklist.sh --table --no-history > /tmp/preprod-baseline.txt; echo "exit code $?"
   ```

   Expected: `exit code 0`, `1` or `2`. Copy `/tmp/preprod-baseline.txt` to
   your machine later with `scp`.

7. If `real` in step 5 is over 2 minutes, turn off the alert log query
   (`CHECK_ALERTLOG=0` in `config.env`) and repeat step 5. If it is still
   over 2 minutes, raise `SQL_TIMEOUT` to at least twice the time and report
   it to the repo owner.

### Prove each alert fires

These steps change `config.env` only. Keep a copy of the real one first.

8. Save your real settings.

   ```
   cp config.env config.env.real
   ```

9. Set every percentage threshold to 1 (WARN) and 2 (CRIT).

   ```
   sed -i -E 's/^([A-Z]+)_WARN=.*/\1_WARN=1/; s/^([A-Z]+)_CRIT=.*/\1_CRIT=2/' config.env
   ```

   This changes CPU, MEM, SWAP, LOAD, FS, TEMP, TS, FRA, ASM, LIMIT and GAP.

10. Run it.

    ```
    bash ./checklist.sh --table --no-history
    ```

    Expected: the OS UTILIZATION, FILESYSTEM, TEMP USAGE, TABLESPACE USAGE,
    ASM DISKGROUP and SESSION LIMIT rows turn CRIT, and the summary says
    CRIT. A row that stays OK has a value of 2 or less (an empty TEMP, for
    example). Anything else that stays OK: report it to the repo owner.

11. Put back the real thresholds, then point node 2 at an address that
    never answers. 192.0.2.1 belongs to a range reserved for documentation,
    so no server ever holds it.

    ```
    cp config.env.real config.env
    ```

    ```
    sed -i 's/^NODE2_HOST=.*/NODE2_HOST=192.0.2.1/' config.env
    ```

12. Run it.

    ```
    bash ./checklist.sh --table --no-history
    ```

    Expected, after about 10 seconds:

    ```
    OS UTILIZATION  Node 2  NO DATA (unreachable or command failed, rc=255)  CRIT
    FILESYSTEM      Node 2  NO DATA                                          CRIT
    ```

    If node 2 rows show numbers instead, the script reached a real host at
    that address. Stop and report it.

13. Put back the real settings and make every input file count as stale.

    ```
    cp config.env.real config.env
    ```

    ```
    sed -i 's/^STALE_MIN=.*/STALE_MIN=1/' config.env
    ```

14. Wait two minutes, then run it.

    ```
    sleep 120; bash ./checklist.sh --table --no-history
    ```

    Expected, for each input file that exists:

    ```
    SFTP LOG     /home/oracle/sftp_output       STALE: last updated 3m ago; producer job may have stopped  CRIT
    APP SERVERS  /home/oracle/server_checklist  STALE: last updated 3m ago; producer job may have stopped  CRIT
    ```

15. Restore the real settings and delete the copy.

    ```
    mv config.env.real config.env
    ```

    ```
    bash ./checklist.sh --table --no-history | head -3
    ```

    Expected: the same SUMMARY as step 5.

### Compare with v1

16. Run v1 the way the team runs it today.

    ```
    cd /home/oracle/scripts && sh ./checklist.sh > /tmp/v1.csv; cd -
    ```

17. Compare the numbers both versions report. They differ in places, on
    purpose:

    | Row | v1 vs v2.1 |
    |---|---|
    | OPEN_MODE, LOG_MODE | same value; v2.1 shows one row per instance |
    | Session counts | same numbers; v2.1 also shows zero-count rows |
    | CPU | close, not equal: v2.1 averages 3 seconds, v1 sampled 1 |
    | Memory | v2.1 is lower: it counts cache Linux can free as free |
    | TEMP | v2.1 is lower: v1 measured cached extents, which stay high |
    | Data Guard gap | v2.1 can differ: it counts the standby destination only |

    Any other difference: report it to the repo owner with both outputs.

18. Attach `/tmp/preprod-baseline.txt` and your notes from steps 10, 12 and 14
    to the change request for production.

## Mail setup

The script hands mail to the local [MTA](../../docs/glossary.md#mta)
(`/usr/sbin/sendmail`, provided by Postfix on RHEL). Postfix passes it to
the company relay, which delivers it to Exchange, and it lands in Outlook
as an HTML table. Three things must hold: Postfix runs, Postfix knows the
relay, and the relay accepts mail from node 1.

Changing Postfix settings or the Exchange connector is a change. Steps 1 to
4 only read. If any of them fails, raise the fix with the Linux or mail team
under a change request.

1. **Your user, node 1**: check Postfix runs.

   ```
   systemctl is-active postfix
   ```

   Expected: `active`. If you see `inactive` or `unknown`, ask the Linux
   team; the mail path is not set up on this server.

2. **Your user, node 1**: check Postfix knows the relay.

   ```
   postconf relayhost
   ```

   Expected: `relayhost = [CHANGE_ME_RELAY_HOST]` with your company's relay
   name. If you see `relayhost =` with nothing after it, Postfix tries to
   deliver directly and Exchange will reject it. Ask the Linux team to set
   the relay.

3. **Your user, node 1**: send a test mail to yourself. Replace
   `CHANGE_ME_YOUR_EMAIL` with your work address.

   ```
   printf 'To: CHANGE_ME_YOUR_EMAIL\nSubject: checklist mail test\n\nTest from node 1\n' | /usr/sbin/sendmail -t -oi
   ```

   No output means Postfix accepted it. That does not mean it arrived.

4. **Your user, node 1**: read the mail log.

   ```
   sudo tail -n 20 /var/log/maillog
   ```

   Find the line with your address and read its `status=`:

   | You see | Meaning | Do this |
   |---|---|---|
   | `status=sent (250 ...)` | the relay took it | check Outlook, including Junk |
   | `status=deferred (connect to ...: Connection timed out)` | node 1 cannot reach the relay | ask the network team to open node 1 to the relay on the SMTP port |
   | `status=bounced (... 550 5.7.x ... not permitted to relay ...)` | Exchange refuses this server | ask the mail team for a receive-connector allowance (below) |
   | `status=bounced (... sender address rejected ...)` | the From address is not allowed | agree a `MAIL_FROM` address with the mail team |

   If `/var/log/maillog` does not exist (some RHEL 9 builds), read the
   journal instead: `sudo journalctl -u postfix -n 20`.

5. **Ask the mail team** (only if step 4 showed a relay refusal). Send them:
   node 1's IP address (`hostname -I`), node 2's if you plan to run it
   there too, the `MAIL_FROM` address, and the recipient list. Ask them to
   allow these servers on the Exchange receive connector for internal relay.

6. **oracle, node 1**: fill `MAIL_TO`, `MAIL_FROM` and `SUBJECT_TAG` in
   `config.env`, then send the report.

   ```
   bash ./checklist.sh --mail --no-history > /dev/null
   ```

   Expected:

   ```
   Mail queued to: dba-team@example.com
   ```

   If you see `MAIL_TO is empty in CONFIG; mail not sent`, fill `MAIL_TO`.
   If you see `sendmail failed rc=...`, repeat steps 1 to 4.

7. Open Outlook. Expected subject:
   `[WARN] Monitoring Checklist | PROD | 02-10-2026 | 19:30`. The body
   starts with the overall status, then a "Needs attention" list, then the
   full table. [sample-output/checklist.html](sample-output/checklist.html)
   shows the same page.

## Troubleshooting

| You see | Cause | Do this |
|---|---|---|
| `config.env line N: not a KEY=value line` | shell code, a space around `=`, or an unclosed quote on line N | rewrite it as `KEY=value` |
| `config.env line N: unknown key X` | typo in the key name | compare with `config.env.example` |
| `config.env line N: X="..." is not a valid ... value` | wrong type: letters in a number, a space in a path | see the comment above that key in `config.env.example` |
| `CONFIG config.env not found ...; built-in defaults used` (WARN) | no `config.env` next to `checklist.sh` | Set up, step 15 |
| `checklist.sh is already running` (exit 3) | another run holds the lock | wait; if no run exists, check with `ps -ef \| grep checklist` |
| `DB QUERY sqlplus no rows returned (rc=127)` | `sqlplus` not on oracle's PATH | run as `sudo -iu oracle` (login shell), not `sudo -u oracle` |
| `DB QUERY sqlplus error ORA-01034` | instance down or wrong ORACLE_SID | RUNBOOK, DB QUERY |
| `CLUSTERWARE crsctl not found` (WARN) | Grid home not found | set `GRID_HOME` in `config.env` |
| `OS UTILIZATION Node 1 CPU: ?%` (WARN) | `sar` missing | install sysstat |
| `Node 2 NO DATA ... rc=255` | ssh to node 2 failed | Set up, step 10 |
| `Node 2 NO DATA ... rc=124` | ssh to node 2 hung for SSH_TIMEOUT seconds | check node 2 load; ask the Linux team |

## Before you run this on production

The script is read-only, and production still needs an approved change
request before its first run and before any cron entry. Use the template
and the filled example in [docs/change-requests.md](../../docs/change-requests.md),
and attach the results of the [pre-production test plan](#pre-production-test-plan).
