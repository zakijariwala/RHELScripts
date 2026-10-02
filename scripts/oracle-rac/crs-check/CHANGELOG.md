# CHANGELOG: crs-check.sh

## How to update a typed copy

Each version below lists every changed line as **section, old line, new
line**. On the server, open your typed `crs-check.sh`, find each old line in
its section, retype it as the new line, and change the `VERSION=` line.
Then check the hashes of the changed sections, and the whole file, against
the table in [README.md](README.md#checksums). Sections not listed did not
change, so their hashes stay the same.

## 1.0.0

First version. Type the whole file; there is no older typed copy to edit.

Built from `checklist.sh` v2.1 (one script for the whole cluster) under
[AMENDMENT 01](../../../docs/decisions/AMENDMENT-01.md). Behaviour that
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

- From v2 `check_crs`. Same parsing and statuses.
- `GRID_HOME` detected from `/etc/oracle/olr.loc` as before; a missing
  value now exits 65 instead of falling back to `/u01/app/19.0.0/grid`.
