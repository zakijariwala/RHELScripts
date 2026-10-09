# health-check

Health of the server it runs on. Copy or type it onto the server, run it
when you need it. Read-only: it writes no files and changes nothing.

```
chmod +x health-check.sh
./health-check.sh
echo $?        # 0 OK, 1 WARN, 2 CRIT
```

Run as the normal login user (oracle on DB nodes). The Database and
Cluster sections run only when Oracle is found on the box (a pmon process
or `/etc/oracle/olr.loc`), so the same script works on web, app and DB
servers.

Settings at the top: `DB` (database name, instances are `vpsdb1`,
`vpsdb2`), `AGENTS` (every server), `DB_AGENTS` (only where Oracle is
found: the Imperva DAM agent `ragent`, `ragentinst`), `CRS` daemons,
`FS_WARN` / `FS_CRIT`.

## Blind spots fixed from the original

| Original | Problem | Now |
|---|---|---|
| "Latest kernel" = `uname -r` | that is the running kernel, not the latest | compares running vs newest installed `kernel-core`; WARN = reboot pending |
| `df -h` | long LVM names wrap onto two lines and break the awk | `df -P` (one line per filesystem) |
| `df ... > mount.txt` | writes a file in the current folder; fails on read-only dirs, leaves junk, reuses stale data | nothing written to disk |
| `df -h \| grep $i` | `/dev/sda1` also matches `/dev/sda10`; same mount reported twice | reads each df line once |
| 70% only | no critical level | WARN 70%, CRIT 90% |
| no inode check | disk "full" at 40% space when inodes run out | inode % checked |
| `df` with NFS | a dead NFS server hangs the whole script | local df under `timeout`; each NFS/CIFS mount tested with a 5s timeout |
| nothing on read-only | disk errors remount xfs/ext4 read-only while df looks fine | CRIT on any read-only xfs/ext4 mount |
| "device count" | number of `/dev/` lines in df means nothing | removed |
| `ntpstat` | works with chrony on RHEL 8, but not installed everywhere (then `[ $n1 -eq 1 ]` errors); shows no server or offset in the old output | `chronyc tracking`: leap status, NTP server, stratum, offset (WARN at 100 ms) |
| `pgrep $i` | substring match: `rscd` matches any name containing rscd | `pgrep -x` exact name |
| `packagekitd` required | PackageKit starts on demand and exits when idle: false CRIT | dropped |
| `sleep 1` per service | 9 seconds wasted | removed |
| no load/memory/swap | blind to the most common outages | load per CPU, MemAvailable %, swap % |
| process check only | an agent running now but disabled in systemd does not come back after a reboot | WARN when the agent's unit is disabled |
| no systemd view | crashed services not in the list go unseen | lists failed systemd units |
| `pgrep ora_pmon_vpsdb1` | only right on node 1; red on every web/app server | finds every `vpsdb` instance; DB checks only on DB servers |
| no ASM check | database down when ASM is down, cause hidden | ASM pmon checked |
| `pgrep tnslsnr` | any listener (e.g. a SCAN listener) counts as "the" listener | the node `LISTENER` must run; others listed |
| 9 CRS daemons ANDed | says "cluster not running" without saying which daemon | one line per daemon, plus `crsctl check crs` |
| `ps -ef \| grep pmon` | prints the grep itself; noise | removed |
| colours always on | escape codes garble output saved to a file or mail | colours only on a terminal |
| no exit code | cannot tell result from a wrapper or senior's runbook | 0 / 1 / 2 + summary line |

## Not covered yet (ideas)

- Bonding / multipath path state
- HugePages and transparent hugepages on DB nodes
- Alert log `ORA-` errors since the last run
- Kernel log (`journalctl -k -p err`) errors
