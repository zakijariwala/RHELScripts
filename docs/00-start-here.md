# Start here

You read this repo on GitHub. You never clone it, download it or copy
files from it. You type each script by hand on the server, prove it is
exact with hashes, configure it, get a senior's approval, then run it.

## I want to...

| Job | Read |
|---|---|
| See which database scripts exist and where each one runs | [scripts/oracle-rac/README.md](../scripts/oracle-rac/README.md) |
| See the scripts for any RHEL server (database, app, web) | [scripts/linux/README.md](../scripts/linux/README.md) |
| Type a script on a server and prove it is exact | [typing-guide.md](typing-guide.md) |
| Fill in config.env from the inventory sheet | [config-from-inventory.md](config-from-inventory.md) |
| Get a senior's approval before a run | [approval-checklist.md](approval-checklist.md) |
| Understand a row in the output | [oracle-rac RUNBOOK](../scripts/oracle-rac/RUNBOOK.md), [linux RUNBOOK](../scripts/linux/RUNBOOK.md) |
| Know what OK, WARN, CRIT, INFO and the exit codes mean | [reading-output.md](reading-output.md) |
| Check that a script changes nothing | [safety.md](safety.md) |
| Understand a word I do not know (RAC, ASM, sysdba...) | [glossary.md](glossary.md) |
| Learn how the code works, line by line | [scripts/oracle-rac/HOW-IT-WORKS.md](../scripts/oracle-rac/HOW-IT-WORKS.md) |
| Ask the Linux team to install sysstat | [offline-install.md](offline-install.md) |
| Raise a change request for production | [change-requests.md](change-requests.md) |
| Change the repo itself (maintainers) | [contributing.md](contributing.md) |

## Rules before you run anything

1. **Read the script's README first.** Its first table says on which server
   and as which user the script runs.
2. **Type and verify before you configure.** Every section hash and the
   whole-file hash must match the README.
3. **Run `--check-config` first.** It shows every value the script will use
   and tests its connections, and checks nothing else.
4. **No run without approval.** A senior reviews the
   [approval checklist](approval-checklist.md) and the `--check-config`
   output before every run. Runs are manual; there is no cron.
5. **Pre-production before production.** Pre-production has no
   GoldenGate: never type `gg-check.sh` there.

## Who runs what, where

| Name in the docs | What it is |
|---|---|
| **node 1**, **node 2** | The two database servers of an Oracle RAC cluster. See [RAC](glossary.md#rac). Every database script is typed and run on node 1. |
| **app1 to app10**, **web1 to web4** | The app and web servers, mirrored on the DR site. The Linux host scripts run on each of them. |
| **GoldenGate host** | The server that runs GoldenGate and `gg2.sh`. `gg-check.sh` reaches it over ssh from node 1. |
| **root** | The Linux superuser. You do not need it for any script here. |
| **oracle** | The Linux user that owns the Oracle software. You become it with `sudo -iu oracle`. |
| **your user** | Your own login on the server. |
| **senior** | The person who approves a run. |
