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

1. ~~Is `dig` on the servers?~~ Yes on the PROD app server that runs
   the old dns_check.sh (dig and nc both used). Keep a getent-only
   fallback for servers without bind-utils.
2. Is ping allowed between environments and to the gateway? If not,
   ping results become INFO.
3. Default targets when run with no arguments (DNS, NTP, backup
   server)? Needs names/IPs and ports.
4. Which ports matter: 22, 1521, and which app/web ports?
5. IPv4 only OK?
