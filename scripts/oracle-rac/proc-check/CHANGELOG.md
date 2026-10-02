# CHANGELOG: proc-check.sh

## How to update a typed copy

Each version below lists every changed line as **section, old line, new
line**. On the server, open your typed `proc-check.sh`, find each old line in
its section, retype it as the new line, and change the `VERSION=` line.
Then check the hashes of the changed sections, and the whole file, against
the table in [README.md](README.md#checksums). Sections not listed did not
change, so their hashes stay the same.

## 1.0.0

First version. Type the whole file; there is no older typed copy to edit.

Built from the team's earlier per-node health script (colour output, one
file for every check) under the design in [FOR-CLAUDE.md](../../../FOR-CLAUDE.md).
Common to all four scripts built from it (host-check, disk-check, hw-check,
proc-check): statuses OK, WARN, CRIT, INFO instead of colour codes and
emoji; an aligned table or `--csv`; a SUMMARY row and exit codes 0, 1, 2,
64, 65; `--check-config`; settings in config.env; writes nothing.

### Changes from the old script

- The database check looked for one hardcoded instance name, so it failed
  on node 2. Now every `ora_pmon_` process on each node is listed, and none
  is CRIT.
- The listener check passed on any `tnslsnr`, SCAN listeners included.
  Now each name in `LISTENERS` (default `LISTENER`) must run on each node;
  other listeners show as INFO.
- The cluster check ANDed nine daemons and printed "cluster is not
  running" without saying which. Now the row names every missing daemon.
- New: ASM instance (`asm_pmon_`) per node. Every node checked from node 1
  over ssh (the old script ran on one node only).
- Process presence is not health: pair this script with `crs-check.sh`
  and `db-check.sh`.
