# Tests

Everything here runs on a maintainer's machine or in CI, never on a server.
Fake versions of the server commands stand in for the real ones.

| Path | What it is |
|---|---|
| `stubs/bin/` | fake `sqlplus`, `ssh`, `sar`, `free`, `df`, `ps`, `pgrep`, `nproc`, `hostname`, `uname`, `rpm`, `needs-restarting`, `chronyc`, `systemctl`, `journalctl`, `id` |
| `stubs/grid/bin/` | fake `crsctl` and `olsnodes`, used as `GRID_HOME` |
| `fixtures/sample/proc/`, `fixtures/sample/sys/` | fake `/proc` and `/sys` trees for disk-check and hw-check (`PROC_DIR`, `SYS_DIR`) |
| `stubs/activesession.sh` | fake `activesession.sh` |
| `fixtures/sample/` | canned output for each fake command: a healthy cluster with a few WARN rows |
| `fixtures/sample/config/` | the `config.env` each script gets in a stub run |
| `run-stub.sh` | runs one script against the stubs: `tests/run-stub.sh db-check [FIXTURE] [-- OPTIONS]` |
| `make-samples.sh` | refreshes the sample output blocks in every script README |

The `sqlplus` stub picks its fixture file from the SQL it receives (for
example `TEMP USAGE` in the SQL selects `temp.out`). Set
`STUB_SQL_CAPTURE=FILE` to save the SQL a script sent.

## Phase 2 plan (bats tests, not built yet)

Every case
runs each affected script through `run-stub.sh` with its own fixture.

**Output and exit codes**
- All healthy: exit 0, every row OK or INFO.
- Exit codes 0, 1, 2, 64 (bad option), 65 (bad config).
- `--csv`: header, quoting, a value with commas, a value with double quotes.
- `--version`, `--help`.

**--check-config**
- Prints one CONFIG row per key with `[default]`, `[config]`, `[detected]`.
- MISMATCH between config.env and detection shows WARN.
- TEST rows: sqlplus login, APP_USER missing in the database, ssh to a node
  that fails, ssh to the GoldenGate host that fails, `gg2.sh` not readable,
  input file missing, `crsctl` missing.
- Runs no check rows.

**Config and detection**
- Unknown key, bad character in a value, non-number threshold: exit 65.
- Required key missing (`APP_USER`, `GG_HOST`): exit 65 naming the key.
- Windows line endings and a last line without a newline load correctly.
- Auto-detect failures: no `ora_pmon_` process, two `ora_pmon_` processes,
  no `/etc/oracle/olr.loc`, `olsnodes` missing.
- `STANDBY_DEST`: blank (auto), a number, `none`, a bad value (exit 65).

**Database scripts**
- Instance missing (`1 of 2`), sqlplus ORA- error, sqlplus timeout,
  sqlplus not found (rc 127), database down (no rows), unparsed line,
  `ERROR:` line produces no extra row.

**node-check**
- Node 2 unreachable (ssh fails), `sar` missing (CPU `?`), filesystem over
  WARN and CRIT, no instance on a node, alert log query failure.

**crs-check**
- Resource OFFLINE (CRIT) and INTERMEDIATE (WARN), crsctl failure.

**gg-check**
- Extract not RUNNING, lag over CRIT, lag not `HH:MM:SS`, checkpoint stale,
  unparsed line, no extract rows.

**inputs-check**
- Stale file, missing file, unparsed line, producer status not Normal,
  inaccessible app servers, `activesession.sh` failure.

**Linux host scripts and proc-check**
- host-check: kernel newer than running, needs-restarting reboot, chrony
  not synchronised, offset over WARN and CRIT, chronyc missing, process
  missing, failed unit, kdump inactive, kernel log errors, journal not
  readable.
- disk-check: space and inodes over limits, read-only mount, SCSI path
  offline, multipath with one path and with none.
- hw-check: bond slave down, bond down, no HugePages, transparent
  hugepages not never, CHECK_HUGEPAGES=0.
- proc-check: no pmon, no ASM, local listener missing, CRS daemon missing,
  node unreachable.

**Rules and tools**
- No-write rule: a run writes no file anywhere (compare file lists before
  and after, outside the stub temp folder).
- Every repo tool fails on a planted violation: `check-budget`,
  `check-no-write`, `check-readonly-sql`, `check-sanitized`,
  `check-banned`, `sync-shared --check`, `gen-checksums --check`.
- `add-banned-term.sh` stores only the hash.
- The verify one-liners in docs/typing-guide.md produce the README table
  under both gawk and mawk; an indent change keeps the hash, a missing
  space changes it.

Removed from the original plan: mail, history log, lock file, and node 2
over ssh as a separate case (node-check covers it).
