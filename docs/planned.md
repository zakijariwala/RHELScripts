# Planned scripts

Approved designs waiting for the go-ahead. Do not build until the owner
says so. When a script is built, remove its entry here and add it to the
table in README.md.

## dr-drill-check.sh

Status: design approved, not started.

Runs on a DR server during a drill. Two modes, since "healthy" differs
before and after the switchover:

```
./dr-drill-check.sh pre     # before switchover: ready to take over?
./dr-drill-check.sh post    # after switchover: now serving?
```

Role detected like health-check (Oracle present = db). Run health-check
first; this script does not repeat its checks.

### All roles

- every `/etc/fstab` entry mounted (`findmnt -s` vs `findmnt`), NFS
  mounts respond
- services for the role enabled and active (list per role from owner)
- names the apps use resolve to DR IPs, not DC IPs (stale `/etc/hosts`
  lines are a classic drill failure)
- app config files: grep for DC host names (PRDB1, PRA1, ...); any hit
  is CRIT in `post`
- next tier reachable from this box (web to app ports, app to DR DB
  1521), same TCP test as net-check

### DB node (read-only SQL as oracle)

| | pre | post |
|---|---|---|
| `database_role` | PHYSICAL STANDBY | PRIMARY |
| `open_mode` | MOUNTED or READ ONLY WITH APPLY | READ WRITE |
| redo apply (MRP) | running | not running |
| archive gap / apply lag | none / under threshold | - |
| listener and services | up | DB services registered |

### Open questions

1. Services expected per role (web, app, db, backup) on DR.
2. App config file paths that hold DB/app host names.
3. Switchover or failover? Changes what `post` expects of the old primary.
4. DR DB name/SID same as DC (`vpsdb`)?
5. SQL as `/ as sysdba`, or a monitoring login?
6. Photos of the existing `drill_activity_cp_pr.sh` and
   `check_drill_activity_cp_pr.sh` on the PROD app server.

## logrotate-check.sh

Status: design approved, not started.

Catches logs that will fill a disk before they do.

- logrotate scheduled: `/etc/cron.daily/logrotate` (RHEL 8) or
  `logrotate.timer` (RHEL 9) enabled, with its last run
- logrotate actually ran: newest entry in
  `/var/lib/logrotate/logrotate.status` older than 2 days = WARN
- config valid: `logrotate -d /etc/logrotate.conf` (dry run, changes
  nothing); any `error:` line = CRIT
- big logs in `/var/log` and app log folders that the dry run never
  mentions (no config covers them)
- logs whose last rotation is far older than their daily/weekly setting
- deleted-but-open logs (`/proc/*/fd` entries marked `(deleted)`): disk
  held after rotation without `copytruncate`; why df and du disagree
- space on the filesystem holding `/var/log` and each app log folder

### Open questions

1. Run with sudo/root? As a normal user some configs and other users'
   open files are hidden (shown as WARN "cannot see"). The PROD app
   server's existing scripts run as root.
2. App log folder paths, and the size that counts as "big" (proposal
   1 GB).

## agent-check.sh

Status: design approved, not started.

health-check asks "is the process running"; this asks "is the agent
working". Five checks per agent, driven by a one-line-per-agent table at
the top of the script:

| Check | How |
|---|---|
| process running | `pgrep -x` |
| agent's own status command | e.g. `emctl status agent`, `dsa_query`, `commvault status` |
| connected to its server | `ss -tn state established` to the server port |
| listening (if it should) | `ss -ltn` on its port |
| log still written | log modified in the last N minutes, recent ERROR lines |

First guess at the table (to be corrected):

| Agent | Status command | Server port | Listens on |
|---|---|---|---|
| Splunk forwarder | `splunk status` | 9997 indexer, 8089 deployment | - |
| DS agent | `/opt/ds_agent/dsa_query -c GetAgentStatus` | 4120 / 4122 | 4118 |
| Commvault | `commvault status` | 8400 / 8403 | 8400 |
| OEM agent | `emctl status agent` (Running and Ready, recent upload) | OMS upload port | 3872 |
| rscd | - | - | 4750 |
| EDR | ? | ? | ? |
| DAM | ? | ? | ? |
| tmxbc, ragent | ? | ? | ? |

### Open questions

1. Products behind EDR, DAM, tmxbc, ragent and their status commands
   (the "verify" sections of the SOP docs, and the `ds_agent_script` and
   `splunkScript` folders on the PROD app server).
2. Real server ports at the site, if not the defaults.
3. Which user runs it: some status commands need the agent owner or root.
