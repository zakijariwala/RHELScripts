# AMENDMENT 01: constraints changed during Phase 1

Saved as received, with two edits: the owner's name is replaced by "the
owner", and section 8 records the answers given after it arrived.
Sections 1 to 7 override PROMPT.md and CONTEXT.md (the original build
packet, kept outside the repo) wherever they conflict. Section 8 overrides
sections 1 to 7 where it says so.

---

## 0. Stop and checkpoint first

1. Stop Phase 1 work now. Commit everything to branch
   `wip/phase1-pre-amendment`. Do not merge it.
2. Reply with three lists: done, half-done, not started. Then wait for "go".
3. After "go": save this file as `docs/decisions/AMENDMENT-01.md`, add the
   section 3 rules to `CLAUDE.md`, and rework Phase 1 per section 5.

These rules override PROMPT.md and CONTEXT.md wherever they conflict.

---

## 1. What changed

- The repo lives on GitHub.com only. Nobody clones it onto a server or onto
  the owner's PC. The owner changes it through Claude Code only. Nobody
  edits files in the browser.
- A fresher reads each script on GitHub.com and **types it by hand** on the
  server. No copy-paste. No file transfer.
- Config values come from the team's inventory Excel sheet. The fresher
  types them into the config file on the server.
- Every run is manual and happens only after a senior checks and approves
  it. No cron. No unattended runs.
- Pre-prod has no GoldenGate.

---

## 2. Defaults (the owner edits before pasting)

| ID | Decision | Default |
|---|---|---|
| D1 | Split `checklist.sh` into small scripts, one per job | YES |
| D2 | Each script runs on the host it checks. No ssh between hosts | YES (revised, section 8) |
| D3 | Remove mail, HTML, history log, lock file. Keep table, CSV, summary, exit codes | YES |
| D4 | Banned terms stored as committed SHA-256 hashes. No GitHub secret, no plaintext file | YES |
| D5 | Ansible Phases 3 and 4 on hold. Reference docs only, no playbooks | YES |

---

## 3. New rules (add to CLAUDE.md)

### 3.1 Typing budget
- Max 150 lines per script. Max 80 characters per line. CI enforces both.
- ASCII only. No tabs. No backticks. No `\$` escapes anywhere.
- No variables named `l`, `O` or `I` (they read as `1`, `0`, `1`).
- At most one short comment line per section. Rationale, history and
  struck-out v1 lines live in `CHANGELOG.md` and `HOW-IT-WORKS.md`, never
  inside a script.
- Shared helpers (add, rate, worst, output) stay under 25 lines and are
  identical in every script. CI checks that they match.
- If a script goes over budget, split it. Never compress code to fit.

### 3.2 SQL without escapes
Use a quoted heredoc so `$` needs no escaping. Pass thresholds as SQL*Plus
substitution variables printed by the shell ahead of the heredoc:

    { printf 'DEFINE temp_warn=%s\n' "$TEMP_WARN"
      cat <<'EOF'
    SET VERIFY OFF
    SELECT ... CASE WHEN pct > &temp_warn THEN 'WARN' ... FROM gv$...;
    EOF
    } | timeout "$SQL_TIMEOUT" sqlplus -s -L / as sysdba

Keep DEFINE on (do not `SET DEFINE OFF`). No literal `&` anywhere else in
the SQL.

### 3.3 Scripts write nothing
- Output goes to stdout and stderr only.
- No files, nothing in `/tmp`, no `rm`, no `-delete`, no `>` or `>>` to any
  path except `/dev/null`.
- CI and the pre-commit hook enforce this, alongside the existing read-only
  SQL check.

### 3.4 Every script supports
- `--help`, `--version` (a `VERSION=` line near the top)
- `--check-config`: loads config, runs auto-detection, prints every value
  (marking detected vs configured, flagging mismatches) and the list of
  checks it would run. It may test connectivity (a sqlplus login, a file
  exists). It runs no checks. The senior reviews this output before
  approving the real run.
- Default run: aligned table plus summary line. `--csv` for CSV.
- Exit codes: 0 OK, 1 WARN, 2 CRIT, 64 bad usage, 65 bad or missing config.

### 3.5 Config
- `config.env` sits next to the script. `KEY=value` lines only. No comments
  needed; the mapping lives in docs.
- Auto-detect before asking the fresher to type anything:
  GRID_HOME from `/etc/oracle/olr.loc`, ORACLE_SID from the running pmon on
  this host, node names from `olsnodes`, standby destination from
  `v$archive_dest`. A config value overrides detection.
- A missing required value exits 65 and names the key and the doc section
  that explains where to find it.

### 3.6 Verifying a typed file
- Mark sections inside every script: `#== S01 name`, `#== S02 name`, ...
- `tools/gen-checksums.sh` computes, per script, one whole-file hash and one
  hash per section. Both are SHA-256 taken after deleting spaces, tabs and
  carriage returns, so indentation differences don't matter but typos do.
  It writes the table into the script's README between marker comments.
  CI fails if any table is stale.
- The fresher's verify command: at most two lines, coreutils and awk only,
  writes no files, prints the whole-file hash and each section hash. It goes
  in `docs/typing-guide.md`.

### 3.7 Repo workflow
- All edits come through Claude Code. First command of every session:
  `git config core.hooksPath .githooks`.
- One pre-commit hook and CI run the same checks: shellcheck, line length,
  ASCII, tabs, backticks, `\$`, no-write rule, read-only SQL, generic
  sanitize (IPv4, email, ports other than 22), hashed banned terms,
  helper-block match, checksum table freshness.
- Every check fails loudly. Remove every skip-with-warning path. A missing
  hash file is a failure.
- Delete the `BANNED_TERMS` secret step and the
  `tools/banned-terms.txt.example` flow.

### 3.8 Banned terms as hashes
- `tools/banned-terms.sha256`: one lowercase SHA-256 per line, committed.
- `tools/add-banned-term.sh`: prompts with `read -s`, hashes each term,
  appends the hash. Plaintext never touches disk or shell history.
- Scanner: lowercase each file, split on characters outside `[a-z0-9._-]`,
  hash each token and each part of it split on `.`, `_` and `-`, compare.
  Report `file:line` only.
- `docs/safety.md` states the limit plainly: someone who guesses a
  candidate name can hash it and test it. Hashes reduce exposure; they do
  not make the list secret.

---

## 4. Docs changes

Remove every instruction that assumes the fresher clones the repo, runs
repo tools, or copies files. Add:

- **`docs/typing-guide.md`**: which user creates the file and in which
  directory; vi basics (open, insert, save, quit, `:set number`, `:set list`
  to spot stray characters); type one section at a time; verify that
  section's hash before moving on; run `bash -n`; how to find and fix a typo
  using section hashes.
- **`docs/config-from-inventory.md`**: one table. Columns: config key,
  inventory sheet, column, example format, command to confirm the value on
  the server, what to do on mismatch (use the server's value, tell the
  senior the inventory row is wrong). Use `CHANGE_ME` placeholders for sheet
  and column names; the owner fills the real names.
- **`docs/approval-checklist.md`**: a printable form. Script, version,
  whole-file and section hashes matched (Y/N), `bash -n` passed, host,
  config values, `--check-config` output attached, reads and writes
  (copied from the README), expected runtime, approver, date, decision.
  Filled on paper or the team's internal system. Never committed.
- **Each script's README**: purpose; which host and which user; what to
  type; config keys with a link to the inventory mapping; sample
  `--check-config` output; sample run output; checksum table; safety
  statement.
- **Each script's CHANGELOG**: for every version, the exact line-level
  edits (section, old line, new line) so someone with a typed copy updates
  only those lines, then re-verifies hashes.

---

## 5. Rework Phase 1

Directory: `scripts/oracle-rac/`. Suggested split (adjust if a group breaks
the 150-line budget):

| Script | Runs on | Covers |
|---|---|---|
| `db-check.sh` | any one DB node, as oracle | open mode, log mode, instance count and uptime, TEMP and top consumer, tablespaces, app-schema sessions, process/session limits, blocking, long calls, ASM diskgroups |
| `dr-check.sh` | primary DB node, as oracle | archive destinations, Data Guard gap and lag, FRA, RMAN (toggle) |
| `node-check.sh` | every node, as oracle | CPU, memory, swap, load, filesystems, local instance alert log ORA- errors |
| `crs-check.sh` | any one node, as grid or oracle | Clusterware resources TARGET vs STATE |
| `gg-check.sh` | the GoldenGate host | runs the existing `gg2.sh` locally, status, lag, checkpoint age |
| `inputs-check.sh` | the node holding the files | `sftp_output`, `server_checklist`, `activesession.sh`, freshness |

Notes:
- Running `node-check.sh` on every node closes the "node 2 alert log" gap
  from CONTEXT.md section 6.
- Pre-prod skips `gg-check.sh` entirely. No toggle needed.
- Keep every v2 fix and check. Change only what this amendment requires.
  Log each behaviour change in CHANGELOG.
- Dropped: all ssh calls, mail, HTML, history log, lock file, the
  `find ... -delete` line.

Phase 1 is done when:
- every script passes the full check set and stays within budget,
- checksum tables exist and CI confirms they're fresh,
- typing guide, inventory mapping and approval checklist exist,
- a fresher could type, verify, configure, get approval, run and read the
  output using only the docs.

Update the Phase 2 test list: add `--check-config` cases, auto-detect
failures, exit 65, the no-write rule, the hash tool and the checksum tool.
Remove the mail, history, lock and node-2-over-ssh cases.

---

## 6. Backlog additions (record, do not build)

**host-health script** (a second existing script, reviewed in chat). Build
only when the owner says go, under these same rules, as a per-node script.
Findings to fix when built:
- `df` without `-P` wraps long LVM names and breaks column parsing.
- Disk loop greps by device name, so substrings match the wrong rows; it
  also writes a temp file to the current directory.
- `pgrep` without `-x` matches substrings, so one agent masks another.
- Database SID hardcoded to node 1, so the script fails on node 2.
- Listener check passes on any listener, including SCAN.
- NTP check breaks with a syntax error when the tool is missing, and shows
  no offset.
- PackageKit checked as required, though it starts on demand.
- "Latest kernel" prints the running kernel; nothing detects a pending
  reboot.
- Process presence treated as health for DB and Clusterware; the cluster
  check doesn't name the missing daemon; ASM not checked.
- Missing: multipath paths, NIC bonding, failed systemd units, CPU, memory,
  swap, load, HugePages, inode use, read-only filesystems, recent kernel
  log errors, kdump.
- Colour codes and emoji break any non-terminal output; no summary or exit
  code; unused colour variables.

**Also backlog:** an optional separate mail script; Ansible reference docs
if a transfer path to a control node ever gets approved.

---

## 7. Report back after the rework

Tree, line count and longest line per script, results of every check, and
open questions. Terse.

---

## 8. Answers given after the amendment (these win over sections 1 to 7)

| Topic | Answer |
|---|---|
| ssh between hosts (D2) | Allowed. `node-check.sh` runs on node 1, checks node 1 locally and every other node over ssh. `gg-check.sh` runs on node 1 and runs `gg2.sh` on the GoldenGate host over ssh. The fresher types both scripts on node 1 only. |
| Section hash normalization (3.6) | Squeeze each run of spaces and tabs to one space and trim both ends of each line, instead of deleting all spaces. Delete carriage returns and blank lines. Indentation still does not matter; a missing space between two words now changes the hash. |
| Config value checks (3.5) | Kept. Every value is checked against an allowed character set, and numeric keys must be numbers, because values reach SQL run as SYSDBA through DEFINE. |
| Line budget (3.1) | Raised from 150 to **200** lines per script. The shared sections need about 100 lines in a database script; at 150 every database check group needed its own script (about 14 scripts, 1,900 typed lines). |
| Script split (5) | Eight scripts: `db-check` (status, instances, sessions, limits, blocking, long calls), `space-check` (TEMP, tablespaces, ASM), `dr-check` (archive destinations, Data Guard), `backup-check` (FRA, RMAN), `node-check` (OS, filesystems and alert log on every node), `crs-check`, `gg-check`, `inputs-check`. FRA and RMAN left `dr-check` because the four groups together exceed 200 lines. |
| Shared blocks (3.1) | Four shared sections, each 25 lines or fewer and identical in every script: `helpers`, `output`, `config`, `options`. A fifth, `sql`, is identical in every script that queries the database. Masters in `tools/shared/`. |
| Hook checks (3.7) | The hook runs the listed checks only. gitleaks runs in CI, not in the hook, so a fresh session needs no gitleaks binary. |
| Seed bugs | Fix all four: GG lag that is not a time rated OK; an unrecognised database line dropped without a row; "sqlplus not found" reported as "database may be down"; "ERROR:" and the following ORA- line producing two CRIT rows. |
