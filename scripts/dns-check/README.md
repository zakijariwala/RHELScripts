# dns-check

Checks every line of `/etc/resolv.conf` and every nameserver in it.
Replaces the old `dns_check.sh`. Read-only: writes no files.

```
./dns-check.sh              # query TEST_NAME
./dns-check.sh prdb1        # query this name (short names use search)
echo $?                     # 0 OK, 1 WARN, 2 CRIT
```

Setting at the top: `TEST_NAME`, a name every nameserver must answer.
Left as `CHANGE_ME`, the script uses this server's own name
(`hostname -f`).

## What it checks

**resolv.conf**
- no `nameserver` line: CRIT
- the same nameserver twice, more than 3 nameservers (only the first 3
  are used), more than 6 search domains: WARN
- `options timeout` over 5 or `attempts` over 3: WARN (slow failover)
- unknown lines, e.g. `namserver`: WARN (the resolver ignores them)

**Each nameserver**, one row each in a table:

```
NAMESERVER       USED UDP      TCP53     TIME  ANSWER           STATUS NOTE
192.0.2.53       yes  NOERROR  open      3 ms  192.0.2.74       OK
192.0.2.54       yes  none     closed          -                CRIT no answer at all
192.0.2.60       no   NOERROR  open     31 ms  192.0.2.74       OK
```

- USED: the resolver only asks the first 3 `nameserver` lines (a
  duplicate line takes a slot). Rows with `no` are tested but never used
  by applications; a dead one there is WARN, not CRIT
- TCP 53 with `nc -zv`, UDP with `dig +notcp`
- the query must return NOERROR with at least one record; no answer,
  SERVFAIL, NXDOMAIN or REFUSED: CRIT; over 1000 ms: WARN
- UDP fails but TCP 53 is open: CRIT, a firewall blocks UDP
- UDP works but TCP 53 is closed: WARN (large answers fail)
- a different answer from an earlier nameserver: WARN
- every search domain must exist on it (SOA query): WARN if not

**System resolver** (the path applications use)
- `getent` answer and how long it took; over 2 s: WARN, usually the
  first nameserver is dead and each lookup waits for the timeout
- answer comes from `/etc/hosts`: WARN (stale entries)
- reverse lookup gives a different name: WARN

Without `dig` only TCP 53 is tested. Needs `nc` (nmap-ncat) for TCP 53.

## Blind spots fixed from the old dns_check.sh

| Old | Problem | Now |
|---|---|---|
| `nc` output grepped for "connected" | timeout, no route, nc missing all shown as "Refused" | separate TCP and UDP results |
| TCP 53 only | DNS runs on UDP; one can work while the other is blocked | both tested |
| `nc` without timeout | hangs on a nameserver that drops packets | `-w 3` inside `timeout` |
| only "Query time" read | a timeout or SERVFAIL still printed a row | status and answer count checked |
| one fixed name | answers never compared | answers compared across nameservers |
| resolv.conf: nameservers only | search, options, typos ignored | every line checked |
| no system resolver test | `/etc/hosts` and search domains never seen | `getent` timing, `/etc/hosts`, reverse |
| `> file1`, `> file2`, `pr` | writes files in the current folder | writes nothing |
| `for i in 177` | builds an IP never checked | removed |
| no exit code | | 0 / 1 / 2 |
