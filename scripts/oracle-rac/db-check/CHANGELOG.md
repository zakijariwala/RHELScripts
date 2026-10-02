# CHANGELOG: db-check.sh

## How to update a typed copy

Each version below lists every changed line as **section, old line, new
line**. On the server, open your typed `db-check.sh`, find each old line in
its section, retype it as the new line, and change the `VERSION=` line.
Then check the hashes of the changed sections, and the whole file, against
the table in [README.md](README.md#checksums). Sections not listed did not
change, so their hashes stay the same.

## 1.0.0

First version. Type the whole file; there is no older typed copy to edit.

Built from `checklist.sh` v2.1 (one script for the whole cluster) under
the design in [FOR-CLAUDE.md](../../../FOR-CLAUDE.md). Behaviour that
differs from v2.1:

### Changes common to every script

- Output: an aligned table by default (v2: CSV). `--csv` gives CSV with
  header `SECTION,KEY,VALUE,STATUS` (v2: `SECTION,DETAIL_KEY,VALUE,DESCRIPTION`)
  and every field in double quotes; double quotes inside a value are
  dropped.
- The SUMMARY row is the last row (v2: first) and holds host, script,
  version and time.
- Removed: mail, HTML, history log, lock file, the old-log `find ... -delete`.
  The script writes nothing.
- `config.env` holds `KEY=value` lines only: no quotes, no comments. A bad
  key or value exits 65 (v2: 64). A missing required value exits 65 and
  names the key.
- New options: `--check-config`, `--version`. Exit code 3 (already running)
  is gone with the lock file.
- A value that is not a number now rates WARN wherever a limit applies.
  v2 read it as 0 and rated it OK.
- A `|` inside a value prints as `/`.

### Changes in this script

- From v2 `check_db`: open mode, log mode, instances, app sessions,
  process and session limits, blocking, long calls. TEMP, tablespaces and
  ASM moved to `space-check.sh`; archive destinations and Data Guard to
  `dr-check.sh`; FRA and RMAN to `backup-check.sh`; the alert log to
  `node-check.sh`.
- `ORACLE_SID` is detected from the running `ora_pmon_` process.
  `EXPECTED_INSTANCES` is detected from the number of nodes `olsnodes`
  lists. A value in config.env overrides either.
- New INFO row `DATABASE name` (v2 used the name in the summary only).
- `LONG_QUERY_EXCLUDE` (`'SYS','SYSTEM'`) became `LONG_QUERY_SKIP`
  (`SYS,SYSTEM`, no quotes).
- Three sqlplus sessions, one per group, instead of one.
- Fixed: a database line the script cannot read is now a WARN row
  `DB QUERY unparsed line` (v2 dropped it without a trace).
- Fixed: sqlplus missing from PATH reports `cannot run sqlplus, rc=127`
  (v2: `database may be down`).
- Fixed: the `ERROR:` line sqlplus prints before an ORA- error no longer
  makes a second CRIT row.
- `no rows returned` became `no output, rc=N` and appears only when the
  call produced no other row.
