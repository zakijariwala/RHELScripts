# CHANGELOG: node-check.sh

## How to update a typed copy

Each version below lists every changed line as **section, old line, new
line**. On the server, open your typed `node-check.sh`, find each old line in
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

- From v2 `check_os` and the alert log query.
- Checks every node `olsnodes` lists, or `NODES` in config.env (v2: node 1
  and `NODE2_HOST`). Runs on one node; reaches the others over one ssh call
  each, as v2 did for node 2.
- Row keys are host names (v2: `Node 1`, `Node 2`).
- The alert log is checked on every node (v2: node 1 only). Each node
  reads its own instance's alert log; the script finds the instance from
  `ora_pmon_` and its `ORACLE_HOME` from that process. New WARN rows when
  a node runs no instance, or the query fails.
- An unreachable node prints one CRIT row `OS UTILIZATION` (v2 also
  printed `FILESYSTEM NO DATA`).
- Filesystem rows over a limit print before the node's `OS UTILIZATION`
  row (v2: after).
