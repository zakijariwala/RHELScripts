# Planned scripts

Approved designs waiting for the go-ahead. Do not build until the owner
says so. When a script is built, remove its entry here and add it to the
table in README.md.

## net-check.sh

Status: design approved, not started.

Runs on the server that has the problem. Checks layer by layer, bottom
up, and ends with one line:

```
VERDICT: LOCAL SERVER | DNS | NETWORK | TARGET SERVICE | OK
```

Usage:

```
./net-check.sh                  # this server's own network health only
./net-check.sh prdb1 1521       # can this server reach prdb1 on 1521?
./net-check.sh 10.x.x.74 1521   # by IP (skips the DNS layer)
```

Default port 22. Read-only, login user, no root.

### Layers

1. **Local server** (fail = LOCAL SERVER)
   - every non-loopback interface UP with an IPv4 address (`ip -br addr`)
   - a default route exists (`ip route`)
   - bonding: every bond has its slaves up (`/proc/net/bonding/*`)
   - interface error/drop counters not zero (WARN)
     (`/sys/class/net/*/statistics`)
2. **Gateway** (fail = NETWORK)
   - ping the default gateway
   - gateway ARP entry (`ip neigh`): FAILED/INCOMPLETE = layer 2 problem
     (cable, switch port, VLAN)
3. **DNS** (always; replaces the old `dns_check.sh`; fail = DNS)
   - `/etc/resolv.conf`: at least one nameserver (skip `#` and `;`
     comments); show `search` and `options timeout/attempts/rotate`
   - per nameserver, a table like the old script's but with a real
     status: TCP 53 (bash `/dev/tcp`, under `timeout`) **and** a UDP
     query (`dig +notcp`), since DNS is mainly UDP and one can work while
     the other is blocked
   - per nameserver, `dig @server TEST_NAME`: status must be NOERROR with
     at least one answer; show query time; no reply = CRIT, SERVFAIL /
     NXDOMAIN = CRIT, over 1000 ms = WARN
   - flag nameservers that give different answers for the same name
   - `TEST_NAME` hardcoded at the top (the internal domain the old script
     queried); the target name is queried too when one is given
   - system resolver path: `getent hosts` result and time taken (over 2s
     usually means the first nameserver is dead); say so if the answer
     comes from `/etc/hosts` (stale entries)
   - reverse lookup of the resolved IP; mismatch = WARN

   Blind spots in the old `dns_check.sh` this fixes:
   - "Refused" shown for every failure: timeout, no route, nc missing
     and nc output format all looked the same
   - TCP 53 only; UDP never tested
   - `nc` without a timeout can hang
   - dig result not checked: a timeout or SERVFAIL still printed a row,
     only the query time was read (blank on failure)
   - only one name queried, answers never compared between servers
   - system resolver (`/etc/hosts`, nsswitch, search domains) never
     tested, though that is what applications use
   - writes `file1`/`file2` in the current folder and glues them with
     `pr`; `for i in 177` loop builds an IP that is never checked
   - no exit code
4. **Path to target**
   - ping the target; failure alone is only WARN (ICMP often blocked)
   - TCP connect to the port:

     | Result | Meaning | Verdict |
     |---|---|---|
     | connected | path and service fine | OK |
     | connection refused | host answered, nothing listening | TARGET SERVICE |
     | timeout | firewall drop or dead host | NETWORK |
     | no route to host | routing, or host down | NETWORK |

   - on timeout or no route: `tracepath` to show the last hop that answered
   - MTU probe `ping -M do -s 1472`: catches "connects but large transfers
     hang"

Verdict = the first layer that fails. Higher layers still run where they
can.

### Shape

- one file, about 130 lines, typeable, same style as health-check
  (`[ OK ]`/`[WARN]`/`[CRIT]`, exit 0/1/2, plus the VERDICT line)
- `dig` and `tracepath` optional: skipped with a note when missing

### Open questions (answer before building)

1. ~~Is `dig` on the servers?~~ Confirmed: dig 9.11.36 (RHEL 8
   bind-utils) on the PROD app server. Use only options 9.11 has:
   `@server`, `+time`, `+tries`, `+tcp`/`+notcp`, `+short`. Keep a
   getent-only fallback for servers without bind-utils.
2. Is ping allowed between environments and to the gateway? If not,
   ping results become INFO.
3. Default targets when run with no arguments (DNS, NTP, backup
   server)? Needs names/IPs and ports.
4. Which ports matter: 22, 1521, and which app/web ports?
5. IPv4 only OK?

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
