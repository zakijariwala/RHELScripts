# Change requests

A change request (CR) is the approved ticket that lets you change a
production system. Your team's change tool (ServiceNow, Remedy, Jira or
similar) holds the real form. This page gives you the text to paste into
it, so the approvers see the same facts for every change from this repo.

## When you need a CR

| What you plan to do on production | CR needed? |
|---|---|
| Type a monitoring script on a production server for the first time | Yes |
| Run a monitoring script on production for the first time | Yes |
| Run the same version again, after its first CR closed | Follow your team's rule; the [approval checklist](approval-checklist.md) is needed for every run regardless |
| Type and run a new version of a script | Yes |
| Change `config.env` thresholds or hosts | Yes, unless your team lists it as a standard change |
| Install a package (sysstat) | Yes |

Cron entries and actions (reboots, restarts) do not exist in this repo:
every run is manual and approved by a senior.

If you are not sure, raise one. A CR nobody needed costs ten minutes. A
change nobody approved can cost your job.

## Template

Copy everything inside the box into your change tool. Replace every
`CHANGE_ME_...` value. The comment after each field says where to find the
value.

```
TITLE
  CHANGE_ME_TITLE
  (One line. Example: "Type and run read-only db-check.sh 1.0.0 on CHANGE_ME_ENV")

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
  (Monitoring scripts: "Read-only, writes nothing. Typed copy verified
   against the README checksum table, whole-file hash <hash>".)

WHAT IT READS AND WRITES
  CHANGE_ME_READS_WRITES
  (Copy the "What it reads" and "What it writes" lists from the script's
   README.)

TESTED ON
  CHANGE_ME_PREPROD_RESULT
  (Date and outcome of the pre-production run. Attach its output and the
   filled approval checklist.)

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
  (How you undo it. Read-only script: delete the script's folder.)

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
  Type and run read-only db-check.sh 1.0.0 on CHANGE_ME_ENV production cluster

CHANGE TYPE
  Normal

SYSTEMS AFFECTED
  CHANGE_ME_NODE1_HOSTNAME

WHAT CHANGES
  Type scripts/oracle-rac/db-check/db-check.sh version 1.0.0 by hand into
  /home/oracle/scripts/oracle-rac/db-check/ on node 1, with a one-line
  config.env (APP_USER). Run it once by hand as oracle. No cron.

WHY
  Replace the manual checklist with a script that flags failures the old
  one hid.

READ-ONLY OR STATE-CHANGING
  Read-only, writes nothing. Typed copy verified: every section hash and
  the whole-file hash match the README (CHANGE_ME_WHOLE_FILE_HASH).

WHAT IT READS AND WRITES
  Reads: the database through sqlplus / as sysdba (SELECT only), ps,
  /etc/oracle/olr.loc, olsnodes.
  Writes: nothing.

TESTED ON
  Pre-production, CHANGE_ME_DATE. Output and approval checklist attached.

RISK AND IMPACT
  Three short sqlplus sessions, under one minute in total. No service
  impact.

PRE-CHECKS
  bash db-check.sh --check-config: every TEST row OK, no MISMATCH.

IMPLEMENTATION STEPS
  docs/typing-guide.md, then the README of db-check.sh, sections
  "Type it", "Configure", "Check the configuration", "Run".

VERIFICATION
  Exit code 0, 1 or 2 and a SUMMARY row. No DB QUERY rows.

BACKOUT PLAN
  rm -r /home/oracle/scripts/oracle-rac/db-check

WINDOW
  CHANGE_ME_WINDOW

PEOPLE
  Implementer: CHANGE_ME_IMPLEMENTER
  Reviewer:    CHANGE_ME_REVIEWER
  Approver:    CHANGE_ME_APPROVER
```
