# Oracle RAC scripts

Nine small read-only scripts that together check a two-node Oracle
[RAC](../../docs/glossary.md#rac) cluster. They replace `checklist.sh`
v2.1. Each one does one job, fits on a few screens, and is typed by hand on
the server from this page (see [docs/typing-guide.md](../../docs/typing-guide.md)).

None of them writes anything. Each prints an aligned table and a summary
line, and exits 0 (OK), 1 (WARN) or 2 (CRIT).

## Which script, where

All of them run as **oracle**. Each lives in its own folder under
`/home/oracle/scripts/oracle-rac/` with its own `config.env`.

| Script | Type and run it on | Checks | Production | Pre-production |
|---|---|---|---|---|
| [db-check.sh](db-check/) | node 1 | open mode, log mode, instances, app sessions, limits, blocking, long calls | yes | yes |
| [space-check.sh](space-check/) | node 1 | TEMP, tablespaces, ASM diskgroups | yes | yes |
| [dr-check.sh](dr-check/) | node 1 of the **primary** | archive destinations, Data Guard gap and lag | yes | with `STANDBY_DEST=none` if no standby |
| [backup-check.sh](backup-check/) | node 1 | Fast Recovery Area, RMAN backup age | yes | with `CHECK_RMAN=0` if no backups |
| [node-check.sh](node-check/) | node 1 (reaches the other nodes over ssh) | CPU, memory, swap, load, filesystems, alert log, on every node | yes | yes |
| [crs-check.sh](crs-check/) | node 1 | Clusterware resources | yes | yes |
| [proc-check.sh](proc-check/) | node 1 (reaches the other nodes over ssh) | instance, ASM, listener and Clusterware processes, on every node | yes | yes |
| [gg-check.sh](gg-check/) | node 1 (reaches the GoldenGate host over ssh) | GoldenGate extracts | yes | **no**, pre-production has no GoldenGate |
| [inputs-check.sh](inputs-check/) | node 1 | sftp log size, active session peaks, app servers | yes | if the input files exist |

Everything is typed and run on node 1 only. `node-check.sh`,
`proc-check.sh` and `gg-check.sh` need passwordless ssh as oracle from node 1 to the other
nodes and to the GoldenGate host.

## The order to work in

For each script, one at a time:

1. **Type** it from its page on GitHub, section by section, checking each
   section's hash ([typing guide](../../docs/typing-guide.md)).
2. **Configure** `config.env` from the inventory sheet
   ([config-from-inventory.md](../../docs/config-from-inventory.md)).
3. **Check the configuration** with `--check-config`.
4. **Get approval**: fill in the [approval checklist](../../docs/approval-checklist.md)
   and hand it to the senior.
5. **Run** it, only after approval.
6. **Read** the output with the [RUNBOOK](RUNBOOK.md).

Start with `db-check.sh`: it is the one most likely to find a real
problem, and it proves sqlplus works.

The general server checks (reboot pending, time sync, disks, bonding,
HugePages) are in [scripts/linux/](../linux/README.md); type them on every
node too.

## Pages in this folder

| Page | For |
|---|---|
| Each script's `README.md` | what it needs, what to type, config keys, sample output, checksums |
| Each script's `CHANGELOG.md` | what changed in each version, line by line |
| [RUNBOOK.md](RUNBOOK.md) | every row any script can print: meaning, how measured, what to do |
| [HOW-IT-WORKS.md](HOW-IT-WORKS.md) | a walk through the code, for someone learning bash |

## Typing effort

Each script is 130 to 200 lines; together about 1,400. Each README's
checksum table gives the exact count for the current version.

Sections S02 to S05 (and S06 in the four database scripts) are the same
in every script and carry the same hash everywhere. Once you have typed
them correctly once, you know them.
