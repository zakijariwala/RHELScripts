# Planned scripts

Approved designs waiting for the go-ahead. Do not build until the owner
says so. When a script is built, remove its entry here and add it to the
table in README.md.

## dr-drill-check.sh

Status: design approved, not started. Updated from the "DR Drill Activity
OS procedure" SOP.

Runs on any PR or DR server around a drill. Site is detected from the
default-route IP (10.191.x = PR, 10.176.x = DR). Run health-check first;
this script does not repeat its checks.

```
./dr-drill-check.sh normal      # PR is live (before switchover / after switchback)
./dr-drill-check.sh switched    # DR is live (after switchover)
```

### From the SOP (all servers)

1. **DNS order** in `/etc/resolv.conf`: on PR servers a PR nameserver
   first, then DR, alternating ("PR dns first and DR dns and so on");
   on DR servers DR first (to confirm). PR DNS = 10.189.x, DR DNS =
   10.176.x (from app05's resolv.conf; to confirm). Wrong first server =
   CRIT.
2. **/etc/hosts entries**, exact IP and name:

   | Server group | Must contain |
   |---|---|
   | front end | 10.191.146.173 vps.ra1, .174 vps.ra2, .175 vps.ra3, .176 vps.ra4 |
   | back end | 10.191.145.21 vps.app1, .22 vps.app2, .23 vps.app3, .24 vps.app4 |

   Missing line, wrong IP, or the same name twice = CRIT.
3. **vpsuser crontab on app10** (PR app10 and DR app10 only), 35 entries:

   | Mode | PR app10 | DR app10 |
   |---|---|---|
   | normal | 35 active, 0 commented | 0 active, 35 commented |
   | switched | 0 active, 35 commented | 35 active, 0 commented |

   Read with `crontab -l -u vpsuser` (root). Counts shown, wrong state =
   CRIT, a total other than 35 = WARN (an entry was added or lost).

### Kept from the first design

- every `/etc/fstab` entry mounted, NFS mounts respond
- next tier reachable (front end to vps.ra*, back end to vps.app*, app
  to DB 1521) with the net-check TCP test
- DB nodes: `database_role` / `open_mode` / redo apply as in the table
  below (PR primary when normal, DR primary when switched)

| | standby side | primary side |
|---|---|---|
| `database_role` | PHYSICAL STANDBY | PRIMARY |
| `open_mode` | MOUNTED or READ ONLY WITH APPLY | READ WRITE |
| redo apply (MRP) | running | not running |

### Proposed companion (action, separate script, not approved)

`cron-switch.sh comment|uncomment`: comments or uncomments the 35
vpsuser entries on app10. Saves the current crontab first, shows the
before/after diff, asks for `yes`, then installs it. Replaces 35 hand
edits per drill.

### Open questions

1. Which servers are "front end" and which "back end" (by inventory
   name: web, app, which app numbers)?
2. On DR servers, are the /etc/hosts entries the same PR IPs, or DR IPs?
3. DNS: are 10.189.x PR and 10.176.x DR? DR servers DR-first?
4. How to recognise the 35 vpsuser entries (all lines of vpsuser's
   crontab, or a marker/comment)?
5. DR DB name/SID same as PR (`vpsdb`)? SQL as `/ as sysdba`?
6. Photos of `drill_activity_cp_pr.sh` and `check_drill_activity_cp_pr.sh`.

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

Status: design approved, not started. Updated from the DS agent and DAM
agent troubleshooting notes.

health-check asks "is the process running"; this asks "is the agent
working". Run as root. Site (PR/DR) from the default-route IP, as in
dr-drill-check.

### DS agent (Deep Security, every server)

| Check | How | Fail |
|---|---|---|
| installed | `rpm -q ds_agent` | CRIT |
| service | `systemctl is-active ds_agent` | CRIT |
| self-telnet 4118 | `nc -zv -w 3 127.0.0.1 4118` | CRIT |
| to manager 4120, 4122 | `nc -zv` to each manager | CRIT (firewall rule FAR #122949) |
| manager connected in | established connections from the managers to 4118 (`ss -tn`) | INFO |

Managers: PR 10.191.146.220, 10.191.146.221; DR 10.176.53.122,
10.176.53.123. Inbound 4118 from the managers cannot be tested from the
server itself; the `ss` line shows whether they have connected.

### DAM agent (Imperva ragent, DB servers only)

| Check | How | Fail |
|---|---|---|
| installed | `/opt/imperva/ragent/bin/cacli` exists | CRIT |
| status | `cacli` status output | CRIT if not running |
| gateways | every `<gw-ip>` in `/opt/imperva/ragent/etc/cliInfo.xml` | CRIT if none |
| gateway ports | `nc -zv` each gw-ip on 443 and 5555 | CRIT per gateway/port |
| source interface | `ip route get GW` must leave from the main ens192 IP, not an alias (ens192:1) | WARN |

The last row replaces the `tcpdump` step of the SOP: traffic to the
gateways leaving from an alias IP was the root cause found in testing,
and `ip route get` shows it without capturing packets.

### Later (same table pattern)

Splunk forwarder, Commvault, OEM agent, rscd, tmxbc: process, status
command, server port, listening port, log freshness. Need their status
commands and ports.

### Open questions

1. `cacli` status output when healthy and when not (exact text).
2. Is the DAM agent on every DB server, PR and DR?
3. Which interface is "main" when a server has several (ens192 on DB
   servers; app05 has ens160 and ens192)?
4. Status commands and ports for Splunk, Commvault, OEM, rscd, tmxbc.
