# Linux host scripts

Three small read-only scripts for **any** RHEL 8 or 9 server: the database
nodes, the app servers (app1 to app10) and the web servers (web1 to web4),
on production and DR. They replace the team's earlier per-node health
script. Each one is typed by hand on the server it checks
([typing guide](../../docs/typing-guide.md)) and runs there; none uses ssh.

| Script | Checks | Run on |
|---|---|---|
| [host-check.sh](host-check/) | pending reboot, time sync, required processes, failed systemd units, kdump, kernel log errors | every server |
| [disk-check.sh](disk-check/) | space and inode use, read-only filesystems, SCSI path states, multipath paths | every server |
| [hw-check.sh](hw-check/) | network bonding, HugePages, transparent hugepages | every server (`CHECK_HUGEPAGES=0` on app and web) |

None needs root. Each prints an aligned table and a summary row, writes
nothing, and exits 0 (OK), 1 (WARN) or 2 (CRIT). On the database nodes,
type them as oracle in `/home/oracle/scripts/linux/`; elsewhere as your
own login in `$HOME/scripts/linux/`.

The Oracle process part of the old script (instances, listener,
Clusterware daemons) lives in
[oracle-rac/proc-check.sh](../oracle-rac/proc-check/), typed on node 1.

Every row and what to do about it: [RUNBOOK.md](RUNBOOK.md). The steps per
script (type, configure, check, approve, run) are the same as for the
Oracle scripts: [scripts/oracle-rac/README.md](../oracle-rac/README.md#the-order-to-work-in).

Ansible will later run these from the control nodes (app5, web1 and their
DR mirrors): see [ansible/README.md](../../ansible/README.md).
