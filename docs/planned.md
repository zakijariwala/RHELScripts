# Planned scripts

Approved designs waiting for the go-ahead. Do not build until the owner
says so. When a script is built, remove its entry here and add it to the
table in README.md.

## net-check.sh

Status: design approved, questions answered, waiting for "build".

Runs on the server that has the problem. Checks layer by layer, bottom
up, and ends with one line:

```
VERDICT: LOCAL SERVER | DNS | NETWORK | TARGET SERVICE | OK
```

Usage:

```
./net-check.sh                  # this server + resolv.conf + fixed targets
./net-check.sh prdb1 1521       # can this server reach prdb1 on 1521?
./net-check.sh 10.x.x.74 2200   # by IP (skips the name lookup)
```

Default port 22. Ports that matter at the site: 22, 1521, 2200.
IPv4 only. Read-only, login user, no root.

### Settings block (top of the script)

```
TEST_NAME=CHANGE_ME       # name every nameserver must answer
# Fixed targets, tested on every run. One per line: NAME PORT
# To add a target, add a line. Empty = none.
TARGETS="
"
```

Fixed targets are the obvious place to grow the script: no code change,
one line per target.

### Layers

1. **Local server** (fail = LOCAL SERVER)
   - every non-loopback interface UP with an IPv4 address (`ip -br addr`)
   - a default route exists (`ip route`)
   - bonding: every bond has its slaves up (`/proc/net/bonding/*`)
   - interface error/drop counters not zero (WARN)
     (`/sys/class/net/*/statistics`)
2. **Gateway** (fail = NETWORK). Ping to the gateway works at the site.
   - ping the default gateway; no reply = CRIT
   - gateway ARP entry (`ip neigh`): FAILED/INCOMPLETE = layer 2 problem
     (cable, switch port, VLAN)
   - MTU probe to the gateway, `ping -M do -s 1472`: catches "connects
     but large transfers hang"
3. **DNS** (always; replaces the old `dns_check.sh`; fail = DNS).
   Everything in `/etc/resolv.conf` is checked:
   - file missing or no `nameserver` line = CRIT (skip `#`/`;` comments)
   - every `nameserver`:
     - TCP 53 with `nc -zv -w 3`, UDP with `dig +notcp`; one working and
       the other not = WARN (firewall blocks one)
     - `dig @server TEST_NAME`: NOERROR with at least one answer, query
       time shown; no reply / SERVFAIL / NXDOMAIN / REFUSED = CRIT,
       over 1000 ms = WARN
     - answers compared across nameservers; different = WARN
   - more than 3 nameservers = WARN (glibc only uses the first 3)
   - duplicate nameserver lines = WARN
   - every `search` domain answers on each nameserver (`dig SOA`);
     a dead search domain slows every short-name lookup = WARN;
     more than 6 domains = WARN (glibc limit)
   - `options`: shown (timeout, attempts, rotate, ndots); `timeout` over
     5 or `attempts` over 3 = WARN (slow failover); `ndots` over 1 = INFO
   - unknown lines = WARN (typos are silently ignored by the resolver)
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
   - search domains and options never checked
   - system resolver (`/etc/hosts`, nsswitch, search domains) never
     tested, though that is what applications use
   - writes `file1`/`file2` in the current folder and glues them with
     `pr`; `for i in 177` loop builds an IP that is never checked
   - no exit code
4. **Path to target** (the argument, then every fixed target).
   No ping: ICMP between environments is blocked at the site.
   - `nc -zv -w 3 HOST PORT` (inside `timeout`), result read from its
     message:

     | nc says | Meaning | Verdict |
     |---|---|---|
     | `Connected to` | path and service fine | OK |
     | `Connection refused` | host answered, nothing listening | TARGET SERVICE |
     | `TIMEOUT` / no answer | firewall drop or dead host | NETWORK |
     | `No route to host` | routing, or host down | NETWORK |
     | nc missing | fall back to bash `/dev/tcp` | - |

   - on timeout or no route: `tracepath` (if present) shows the last hop
     that answered, INFO only (it may be blocked too)

Verdict = the first layer that fails. Higher layers still run where they
can.

### Shape

- one file, about 130 lines, typeable, same style as health-check
  (`[ OK ]`/`[WARN]`/`[CRIT]`, exit 0/1/2, plus the VERDICT line)
- `dig` 9.11 options only: `@server`, `+time`, `+tries`, `+tcp`/`+notcp`,
  `+short` (dig 9.11.36 confirmed on the PROD app server); getent-only
  fallback without bind-utils
- `nc` is nmap-ncat on RHEL 8/9 (`-z` supported)
- `tracepath` optional: skipped with a note when missing

### Answered

1. dig: 9.11.36 present.
2. Ping: works to the gateway, blocked between environments. Use
   `nc -zv` between servers.
3. Fixed targets: none yet; `TARGETS` block makes adding them a
   one-line change.
4. Ports: 22, 1521, 2200.
5. IPv4 only.

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
