# Change requests

A change request (CR) is the approved ticket that lets you change a
production system. Your team's change tool (ServiceNow, Remedy, Jira or
similar) holds the real form. This page gives you the text to paste into
it, so the approvers see the same facts for every change from this repo.

## When you need a CR

| What you plan to do on production | CR needed? |
|---|---|
| Run a monitoring script from this repo for the first time | Yes |
| Run the same version again by hand, after its first CR closed | Follow your team's rule; most teams say no |
| Run a new version of a monitoring script | Yes |
| Add, change or remove a cron entry | Yes |
| Change `config.env` thresholds or hosts | Yes, unless your team lists it as a standard change |
| Copy a script to a server without running it | Follow your team's rule |
| Run any action (reboot, restart) from `actions/` | Yes, every time |
| Install a package (sysstat, Ansible) | Yes |

If you are not sure, raise one. A CR nobody needed costs ten minutes. A
change nobody approved can cost your job.

## Template

Copy everything inside the box into your change tool. Replace every
`CHANGE_ME_...` value. The comment after each field says where to find the
value.

```
TITLE
  CHANGE_ME_TITLE
  (One line. Example: "Deploy read-only Oracle RAC checklist v2.1 on CHANGE_ME_ENV")

CHANGE TYPE
  CHANGE_ME_TYPE
  (Standard, Normal or Emergency. Ask your team lead which your tool uses.)

SYSTEMS AFFECTED
  CHANGE_ME_HOSTS
  (Every host name the change touches. Real names go here, in the ticket,
   never in this repo.)

WHAT CHANGES
  CHANGE_ME_DESCRIPTION
  (Which script or playbook, which version or git commit, what it does.
   Get the commit with: git log -1 --format=%h)

WHY
  CHANGE_ME_REASON

READ-ONLY OR STATE-CHANGING
  CHANGE_ME_READONLY_OR_ACTION
  (Monitoring scripts: "Read-only. SQL audit passed: <paste the RESULT line
   of tools/check-readonly-sql.sh>". Actions: list every state it changes.)

WHAT IT READS AND WRITES
  CHANGE_ME_READS_WRITES
  (Copy the "What it reads" and "What it writes" lists from the script's
   README.)

TESTED ON
  CHANGE_ME_PREPROD_RESULT
  (Date and outcome of the pre-production run. Attach its output.)

RISK AND IMPACT
  CHANGE_ME_RISK
  (Read-only scripts: load from one sqlplus session and a few ssh calls for
   under five minutes. Actions: what users lose and for how long.)

PRE-CHECKS
  CHANGE_ME_PRECHECKS
  (What you confirm before you start. Example: "CRS resources all ONLINE,
   Data Guard lag under 15 minutes".)

IMPLEMENTATION STEPS
  CHANGE_ME_STEPS
  (Numbered commands, copied from the script's README.)

VERIFICATION
  CHANGE_ME_VERIFICATION
  (What output proves success. Example: "exit code 0 or 1, no DB QUERY
   rows".)

BACKOUT PLAN
  CHANGE_ME_BACKOUT
  (How you undo it. Read-only script: delete the script folder and any cron
   line. Actions: the exact reverse steps.)

WINDOW
  CHANGE_ME_WINDOW
  (Start and end time. Actions on production run in an agreed window.)

PEOPLE
  Implementer: CHANGE_ME_IMPLEMENTER
  Reviewer:    CHANGE_ME_REVIEWER
  Approver:    CHANGE_ME_APPROVER
```

## Filled example: first run of a read-only script

```
TITLE
  Run read-only Oracle RAC checklist v2.1 on CHANGE_ME_ENV production cluster

CHANGE TYPE
  Normal

SYSTEMS AFFECTED
  CHANGE_ME_NODE1_HOSTNAME, CHANGE_ME_NODE2_HOSTNAME, CHANGE_ME_GG_HOSTNAME

WHAT CHANGES
  Copy scripts/oracle-rac-checklist/checklist.sh (commit 1a2b3c4) and its
  config.env to /home/oracle/scripts on node 1. Run it once by hand as the
  oracle user. No cron entry in this change.

WHY
  Replace the manual checklist mail with a generated report that flags
  failures the old script hid.

READ-ONLY OR STATE-CHANGING
  Read-only. SQL audit passed:
  "scripts/oracle-rac-checklist/checklist.sh: 20 SELECT, 1 WITH, 10 SET, 1 EXIT"

WHAT IT READS AND WRITES
  Reads: Oracle dictionary views, crsctl status, sar/free/df on both nodes,
  gg2.sh output over ssh, two status files in /home/oracle.
  Writes: /tmp/checklist_oracle.lock. With --no-history, nothing else.

TESTED ON
  Pre-production, CHANGE_ME_DATE. Output attached. Exit code 1 (expected
  WARN rows listed in the attachment).

RISK AND IMPACT
  One sqlplus session for under one minute, one ssh call each to node 2 and
  the GoldenGate host. No service impact.

PRE-CHECKS
  oracle user can ssh to node 2 without a password. sysstat installed on
  both nodes.

IMPLEMENTATION STEPS
  1-9 from scripts/oracle-rac-checklist/README.md, section "Set up".

VERIFICATION
  Script exits 0, 1 or 2 and prints a SUMMARY row. No "DB QUERY" CRIT rows.

BACKOUT PLAN
  rm -r /home/oracle/scripts/oracle-rac-checklist

WINDOW
  CHANGE_ME_WINDOW

PEOPLE
  Implementer: CHANGE_ME_IMPLEMENTER
  Reviewer:    CHANGE_ME_REVIEWER
  Approver:    CHANGE_ME_APPROVER
```
