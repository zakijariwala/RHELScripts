# CHANGELOG: host-check.sh

## How to update a typed copy

Each version below lists every changed line as **section, old line, new
line**. On the server, open your typed `host-check.sh`, find each old line in
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

- "Latest kernel" printed the running kernel. Now the running kernel is
  compared with the newest installed `kernel-core`; a difference is WARN
  "reboot pending". `needs-restarting -r` adds the userspace view.
- NTP: `ntpstat` broke with a syntax error when missing and showed no
  offset. Now `chronyc tracking`: leap status not Normal is CRIT, the
  offset is rated against `TIME_WARN_MS` / `TIME_CRIT_MS`, the source is
  shown. chronyc missing or failing is CRIT.
- Processes: `pgrep NAME` matched substrings, so one agent could mask
  another. Now `pgrep -xc`, exact names, each from `PROCS`. Site agent
  names moved out of the script into config.env. `packagekitd` dropped:
  it starts on demand, so "not running" was a false alarm.
- New: failed systemd units, kdump active, kernel log errors (priority
  err and worse, last `KLOG_HRS` hours).
