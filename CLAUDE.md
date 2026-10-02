# CLAUDE.md

Rules for every Claude Code session in this repo. Read all of it before
changing anything. [docs/decisions/AMENDMENT-01.md](docs/decisions/AMENDMENT-01.md)
records why the repo works this way.

## First command of every session

```
git config core.hooksPath .githooks
```

The pre-commit hook runs `tools/check-all.sh` on the staged tree and
blocks the commit on any failure. Never bypass it with `--no-verify`.

## The repo

Read-only monitoring scripts for Oracle 19c RAC clusters on RHEL 8 and 9
(RAC, ASM, Grid Infrastructure, Data Guard, GoldenGate). The repo is
**public**.

- The repo lives on GitHub only. The owner changes it through Claude Code
  only. Nobody clones it onto a server or a desktop, and nobody edits in
  the browser.
- A fresher reads each script on GitHub and **types it by hand** on the
  server. No copy-paste, no file transfer.
- Config values come from the team's inventory sheet; the fresher types
  them into `config.env` next to the script.
- Every run is manual and approved by a senior first. No cron, no
  unattended runs.
- Servers have no internet. Pre-production has no GoldenGate.
- ssh between hosts is allowed: `node-check.sh` and `gg-check.sh` run on
  node 1 and reach the other hosts over ssh.
- Ansible (Phases 3 and 4) is on hold. No playbooks.
- You have no access to any real server. You run everything against the
  stubs in `tests/` (`tests/run-stub.sh NAME`).

## How the owner wants you to work

- Output first. Terse. No preamble, no recap of the request.
- Direct, unvarnished assessments. Flag problems plainly.
- Do only what the current task asks. List extra ideas under
  "Proposed, not done". Do not build them. Ask first.
- A bug or doubtful choice in existing check logic: report it with
  evidence and a proposed fix. Change check logic only after the owner
  agrees.
- Summaries: what exists, how you verified it, what is open.

## Safety (never break these)

1. **Monitoring is read-only.** SQL is `SELECT`/`WITH` only, plus SQL*Plus
   `SET`, `DEFINE` and `EXIT`.
2. **Scripts write nothing.** Output goes to stdout and stderr only. No
   files, nothing in `/tmp`, no `rm`, no `-delete`, no `>` or `>>` to any
   path except `/dev/null`. Over ssh, only read-only commands.
3. **Actions are separate and guarded** (none exist today). Anything that
   changes state lives under `scripts/actions/`, refuses to run without
   `--i-understand`, prints what it will do and where, supports a dry run,
   works one host at a time, runs a pre-check and a post-check, and has a
   README section "Before you run this on production" pointing to
   `docs/change-requests.md`.
4. **No real identifiers in the repo.** No IPs, hostnames, ports other
   than 22, DB or schema names, people, email addresses, or employer
   names. Example IPs: 192.0.2.x, 198.51.100.x, 203.0.113.x. Example mail:
   example.com. Placeholders look like `CHANGE_ME_SOMETHING`.
5. **No secrets.** No passwords, keys, tokens.
6. Never weaken a check, a test or a repo tool to get green. Flag it.

## Typing budget (every script under scripts/)

- At most **200 lines** per script (the owner raised it from 150 because
  the shared sections take about 100 lines). At most **80 characters** per
  line.
- ASCII only. No tabs. No backticks. No backslash-dollar anywhere.
- No variable named `l`, `O` or `I`.
- Line 1 `#!/bin/bash`, line 2 `#== S01 settings`. Sections marked
  `#== Snn name`, numbered in order.
- At most one short comment line per section. Rationale and history live
  in the CHANGELOG and HOW-IT-WORKS, never in a script.
- Shared sections, identical in every script and each 25 lines or fewer:
  `helpers`, `output`, `config`, `options`; `sql` in every database
  script. Masters live in `tools/shared/`; `tools/sync-shared.sh` copies
  them in. Edit the masters, never the copies.
- Over budget: split the script. Never squeeze code to fit.

## SQL without escapes

Quoted heredoc, thresholds as SQL*Plus substitution variables:

```
sql "temp_warn=$TEMP_WARN" <<'SQL'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 VERIFY OFF TAB OFF LINESIZE 1000
SELECT ... CASE WHEN pct > &temp_warn THEN 'WARN' ... FROM gv$...;
EXIT
SQL
```

`sql()` prints each argument as `DEFINE name=value` ahead of the heredoc.
Keep DEFINE on (never `SET DEFINE OFF`). No literal `&` anywhere else in
the SQL. Each SELECT emits one line `SECTION|KEY|VALUE|STATUS`.

## Every script supports

- `--help`, `--version` (`VERSION=` in S01)
- `--check-config`: loads config, runs detection, prints every value with
  `[default]`, `[config]`, `[detected]` or `MISMATCH`, the list of checks,
  and TEST rows for connectivity (sqlplus login, ssh, files). Runs no
  checks.
- Default run: aligned table with a SUMMARY row. `--csv` for CSV.
- Exit codes: 0 OK, 1 WARN, 2 CRIT, 64 bad usage, 65 bad or missing
  config.
- Statuses OK, WARN, CRIT, INFO and nothing else. Unreachable host or
  failed command = CRIT. Missing measurement = WARN. Never OK for data the
  script did not get.
- Every external call in `timeout`; ssh with `-o BatchMode=yes -o
  ConnectTimeout=10`.

## Config

- `config.env` next to the script. `KEY=value` lines only, no quotes, no
  comments. Values limited to `[A-Za-z0-9_./:,@+-]`; keys ending WARN,
  CRIT, MAX, SECS, MIN, HRS, DAYS, TIMEOUT, MB, PORT or starting CHECK_
  must be numbers. Values reach SQL run as SYSDBA, so never loosen this.
- Detect before asking: GRID_HOME from `/etc/oracle/olr.loc`, ORACLE_SID
  from `ora_pmon_`, nodes from `olsnodes`, standby destination from
  `v$archive_dest`. Config overrides detection.
- A missing required value exits 65 naming the key and
  `docs/config-from-inventory.md`.

## Verifying a typed file

- `tools/gen-checksums.sh` writes, into each script's README, a whole-file
  hash and one hash per section: SHA-256, first 12 characters, after
  deleting carriage returns and blank lines, squeezing runs of spaces and
  tabs to one space and trimming each line. The fresher's two verify
  commands in `docs/typing-guide.md` compute exactly the same.
- After any script change: `tools/gen-checksums.sh`, `tests/make-samples.sh`,
  and a CHANGELOG entry listing every changed line (section, old line, new
  line).

## Banned terms

`tools/banned-terms.sha256`: one lowercase SHA-256 per line, committed.
`tools/check-banned.sh` hashes every token and token part and reports
file:line only. A missing or empty hash file fails. Never write a banned
term in plain text anywhere, including commit messages.

## The checks (hook and CI run the same)

`tools/check-all.sh` runs: shellcheck, check-budget, check-no-write,
check-readonly-sql, check-sanitized, check-banned, sync-shared --check,
gen-checksums --check. Every check fails loudly; there is no skip path.
CI also runs gitleaks and the checksum check on RHEL 8 and 9 rebuilds.

## Naming

- Scripts: `scripts/<area>/<name>/<name>.sh`, kebab-case.
- Branches: `feat/<short>`, `fix/<short>`, `docs/<short>`.

## Writing style for docs ("Stop Slop")

- No em dashes. No adverbs. No "not X, it's Y". No throat-clearing.
- Active voice with a human or a named component as the subject.
- Specific nouns. Vary sentence length.
- Never "simply", "just", "obviously", "easy".

## The fresher test (every doc)

A fresher knows basic Linux and has never used Oracle. Every command sits
in its own code block with expected output; one action per step; success
and failure shown; "if you see X, do Y"; terms linked to the glossary; who
runs it and on which machine; placeholders `CHANGE_ME_...` with where to
find the value.

## Definition of done (every script)

- [ ] Within the typing budget; shared sections in sync
- [ ] Output, options and exit codes as above
- [ ] README: purpose, host, user, what to type, config keys, sample
      `--check-config`, sample run, checksum table, safety statement
- [ ] CHANGELOG with line-level edits
- [ ] RUNBOOK entry for every row it can print
- [ ] Runs against the stubs; failure paths tried
- [ ] `tools/check-all.sh` passes
