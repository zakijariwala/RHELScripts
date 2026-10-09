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
3. **DNS** (only when a name is given; fail = DNS)
   - `/etc/resolv.conf` has at least one nameserver
   - each nameserver answers on port 53
   - `getent hosts` result and time taken; over 2s usually means the first
     nameserver is dead
   - with `dig`: ask each nameserver separately, flag disagreement
   - say so if the name comes from `/etc/hosts` (stale entries)
   - reverse lookup of the resolved IP; mismatch = WARN
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

1. Is `dig` (bind-utils) on the servers?
2. Is ping allowed between environments and to the gateway? If not,
   ping results become INFO.
3. Default targets when run with no arguments (DNS, NTP, backup
   server)? Needs names/IPs and ports.
4. Which ports matter: 22, 1521, and which app/web ports?
5. IPv4 only OK?
