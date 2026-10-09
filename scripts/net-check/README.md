# net-check

Is the problem this server, DNS or the network? Run it on the server that
has the problem. Read-only: writes no files, changes nothing.

```
./net-check.sh                  # this server, gateway, fixed targets
./net-check.sh prdb1 1521       # can this server reach prdb1 on 1521?
./net-check.sh 10.x.x.74 2200   # by IP
echo $?                         # 0 OK, 1 WARN, 2 CRIT
```

Default port 22. Ports that matter at the site: 22, 1521, 2200.
Last line is the answer:

```
VERDICT: LOCAL SERVER | DNS | NETWORK | TARGET SERVICE | OK
```

The first layer that fails decides the verdict.

## Fixed targets

At the top of the script. One line per target, `NAME PORT`; lines
starting with `#` are skipped. Every run tests them.

```
TARGETS="
prdb1 1521
10.x.x.213 22
"
```

## What it checks

| Layer | Check | Fail means |
|---|---|---|
| Local server | every interface with an IPv4 address is up; rx/tx errors since boot (WARN) | LOCAL SERVER |
| | bonds: every slave up (WARN when one is down) | |
| | a default route exists | LOCAL SERVER |
| Gateway | ping the gateway | NETWORK |
| | 1500-byte packet with don't-fragment (MTU) reaches it (WARN) | |
| | gateway ARP entry FAILED / INCOMPLETE: cable, switch port, VLAN | NETWORK |
| Targets | name resolves (`getent`, as applications do) | DNS: run `dns-check.sh NAME` |
| | `nc -zv -w 3 HOST PORT`: | |
| | `Connected to` | OK |
| | `Connection refused`: host is up, nothing listens on the port | TARGET SERVICE |
| | `TIMEOUT` / `No route to host`: firewall drop or host down; `tracepath` shows the last hop | NETWORK |

No ping to other servers: ICMP between environments is blocked at the
site, so a failed ping there proves nothing. Without `nc` it falls back
to bash `/dev/tcp`.

IPv4 only. Needs `ip`, `ping`, `getent`, `nc`; `tracepath` optional.
