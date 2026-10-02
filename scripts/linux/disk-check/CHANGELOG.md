# CHANGELOG: disk-check.sh

## How to update a typed copy

Each version below lists every changed line as **section, old line, new
line**. On the server, open your typed `disk-check.sh`, find each old line in
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

- `df -h` without `-P` wrapped long LVM names and broke the columns. Now
  `df -P`.
- The disk loop wrote `mount.txt` into the current folder and grepped by
  device name, so `sda` also matched `sda1`. Now one `awk` pass, no file.
- Space use per mount now rates against `FS_WARN` (80) and `FS_CRIT` (90);
  the old script listed mounts at 70% or more with no status. New: inode
  use, read-only local filesystems, SCSI path states, multipath path
  counts. On database nodes `node-check.sh` also rates space use.
- The "device count" row is gone: a count with no expected value never
  showed a problem. SCSI PATH and MULTIPATH rows replace it.
