# CHANGELOG: Oracle RAC checklist

The script marks each change in its code: `[ADDED]`, `[CHANGED]`, `[FIXED]`,
`[REMOVED]` for v2, the same with `v2.1` for v2.1. Old lines stay in the
file, struck out with `#~` (shell) or `--~` (SQL), so you can compare.

## v2.1

### Changed

- **Settings moved to `config.env`.** The script reads `config.env` from
  its own folder. Built-in defaults stay in the script for any key the file
  leaves out. The template `config.env.example` documents every key.
- **`config.env` is read as data, never executed.** Each line must be
  `KEY=value` for a known key, and each value must match its type (number,
  0/1, path, host, database name). A bad line stops the run with exit code
  64 and names the line. Reason: several values go into the SQL sent as
  SYSDBA. A sourced file, or an unchecked value, could run a command or
  add a write statement that the read-only audit never sees.
- **Timeouts for `crsctl` and `activesession.sh` moved to config**
  (`CRS_TIMEOUT`, `ACTIVESESSION_TIMEOUT`). They were fixed at 60 and 120
  seconds inside the code; the defaults stay the same.
- **`--no-history` beats `WRITE_HISTORY=1` in `config.env`.** Without this,
  the config file would override the flag.
- **`GG_SCRIPT`, `ACTIVESESSION_SCRIPT` and `GRID_HOME`** default to blank
  and are worked out after `config.env` is read, so setting `SCRIPTS_DIR`
  alone moves both script paths.
- **Install folder.** The script now lives in
  `/home/oracle/scripts/oracle-rac-checklist/`, next to v1, so both can run
  during rollout.
- Two unused variables replaced with `_` (shellcheck). No behaviour change.

### Added

- **`CHECK_GG`** (default 1). `0` skips GoldenGate and prints one INFO row
  `GOLDENGATE GoldenGate check disabled (CHECK_GG=0)`. For clusters with no
  GoldenGate, such as pre-production.
- **`CHECK_DG`** (default 1). `0` leaves the Data Guard query out of the
  SQL and prints one INFO row `DB SYNC STATUS Data Guard check disabled
  (CHECK_DG=0)`. For databases with no standby, which otherwise show CRIT
  on every thread.
- **CONFIG row**, first after SUMMARY: INFO when `config.env` loaded, WARN
  when the script fell back to built-in defaults.
- **Exit code 64** for an invalid `config.env` (it already meant "bad
  option").

## v2 (from v1)

### Fixed

1. **Node 2 unreachable printed "Normal".** v1 set missing CPU and memory
   to 0, so a dead node looked idle. Now CRIT `NO DATA`.
2. **A down instance vanished.** A stopped instance has no row in
   `GV$INSTANCE`, so v1 never printed "Not Running". Now the open count is
   compared with `EXPECTED_INSTANCES`.
3. **sqlplus errors were dropped.** v1 kept only lines containing `|`;
   `ORA-01034` and friends have none. Now each error line is a CRIT row.
4. **"No Active Session" could never fire.** v1 grouped existing
   sessions, so zero ACTIVE sessions produced no row. Now every instance
   gets an ACTIVE and an INACTIVE row, zero included.
5. **TEMP measured the wrong thing.** v1 used `bytes_cached` from
   `v$temp_extent_pool`: extents Oracle keeps after sorts finish, on the
   local instance only. It showed 92.88% two hours apart. Now used blocks
   from `gv$sort_segment` against the maximum size, autoextend included.
6. **Data Guard sync.** v1 mixed local and standby destinations, dropped
   a thread with no applied log, and counted sequences with no time. Now:
   standby destination only, missing thread = CRIT, and a minutes-behind
   figure.
7. **Input files trusted blindly.** v1 printed `sftp_output` and
   `server_checklist` as they were. A dead producer job showed "all good"
   forever. Now a file older than `STALE_MIN` is CRIT.
8. **ssh could hang forever.** Now `BatchMode`, `ConnectTimeout` and
   `timeout` on every call.

### Changed

- OPEN_MODE checked on every instance (v1: `ROWNUM = 1`, one instance).
- Memory % uses the "available" column; CPU averages 3 seconds (v1: 1).
- Node 2 metrics in one ssh call (v1: three).
- IPs, ports and thresholds moved into a CONFIG block.
- One status vocabulary: OK, WARN, CRIT, INFO (v1: Normal, High, Warning,
  CRITICAL, Running, High Session).
- CSV fields quoted, so a comma inside a value no longer shifts columns.

### Added

- Checks: permanent tablespaces, FRA, archive destination errors, ASM
  diskgroups, RMAN backup age, alert log ORA- errors, Clusterware
  resources, filesystems on both nodes, swap, load, process and session
  limits, blocking sessions, long-running calls, top TEMP consumer,
  GoldenGate lag and checkpoint limits, sftp.log size limit.
- Summary row, exit codes, `--table`, `--html`, `--mail`,
  `--mail-if-issues`, history log, run lock.

### Removed

- Commented-out `sar -r` lines (dead code).
- `echo -e` on section headers (nothing to escape).

## v1

The original: one sqlplus `UNION ALL`, `sar` and `free` over three ssh
calls, and `cat` of four inputs, printed as unquoted CSV and pasted into
Excel, then into Outlook by hand.
