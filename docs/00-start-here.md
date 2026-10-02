# Start here

Find the job you have in the left column. Read the page in the right
column. Pages marked *(Phase N)* do not exist yet; the repo builds them in
that phase.

## I want to...

| Job | Read |
|---|---|
| Understand a word I do not know (RAC, ASM, sysdba, playbook...) | [glossary.md](glossary.md) |
| Check that a script changes nothing before I run it | [safety.md](safety.md) |
| Run anything new on a production server | [change-requests.md](change-requests.md) |
| Set up the Oracle RAC checklist on a database server | `scripts/oracle-rac-checklist/README.md` *(Phase 1)* |
| Understand a line in the checklist output | `scripts/oracle-rac-checklist/RUNBOOK.md` *(Phase 1)* |
| Know what OK, WARN, CRIT, INFO and the exit codes mean | [reading-output.md](reading-output.md) *(Phase 1)* |
| Install sysstat, bats or Ansible on a server with no internet | [offline-install.md](offline-install.md) *(Phase 1)* |
| Learn how the checklist code works, line by line | `scripts/oracle-rac-checklist/HOW-IT-WORKS.md` *(Phase 1)* |
| Run the tests | `docs/testing.md` *(Phase 2)* |
| Check many servers at once with Ansible | `ansible/README.md` *(Phase 3)* |
| Reboot servers one at a time, with guards | `ansible/README.md` *(Phase 4)* |
| Add a new check script to this repo | [contributing.md](contributing.md) *(later)* |

## Three rules before you run anything

1. **Read the script's README first.** Every README has a section that says
   who runs the script (root, oracle, or your own user) and on which machine.
2. **Run it on pre-production before production.** Each README has a
   pre-production test plan.
3. **Anything new on production needs a change request.** That includes a
   read-only script the first time it runs there, and every cron entry.
   Use the template in [change-requests.md](change-requests.md).

## Who runs what, where

The docs name a user and a machine for every command. These are the names
they use:

| Name in the docs | What it is |
|---|---|
| **node 1**, **node 2** | The two database servers of an Oracle RAC cluster. See [RAC](glossary.md#rac). |
| **control node** | The one server that runs Ansible and reaches every other server over ssh. See [control node](glossary.md#control-node). |
| **your machine** | Your laptop or jump host, where you clone this repo. |
| **root** | The Linux superuser. You reach it with `sudo -i`. |
| **oracle** | The Linux user that owns the Oracle software. You reach it with `sudo -iu oracle`. |
| **your user** | Your own login on that machine. |
