# FOR-CLAUDE.md

The single source of truth for any Claude Code session in this repo:
purpose, design, decisions, progress and the rules you work by. It stands
on its own. Other files explain things to people; this file decides.

**Keep it true.** When a decision, the design or the progress changes,
rewrite the affected section in place. Never append an "amendment",
"update" or "note" at the end. Remove what is no longer true. Date the
progress section. If another file disagrees with this one, this one wins:
fix the other file.

---

## 1. Purpose

Read-only monitoring scripts for an Oracle 19c RAC estate on RHEL 8 and 9,
written for a banking infrastructure team, and an Ansible scaffold for the
app and web tiers.

The audience is a **fresher**: knows basic Linux (cd, ls, cat, vi, ssh,
sudo), has never used Oracle, RAC, Data Guard, GoldenGate or Ansible. With
the docs alone they must be able to type a script onto a server, prove it
is exact, configure it, get it approved, run it, read every output row,
know what to do at WARN and CRIT, and confirm the script changed nothing.

## 2. Environment (fixed facts)

- The repo is **public** on GitHub (`zakijariwala/RHELScripts`, MIT). It
  lives only there. The owner changes it only through Claude Code. Nobody
  clones it onto a server or desktop, nobody edits in the browser.
- Scripts reach a server one way: a fresher reads them on GitHub and
  **types them by hand**. No copy-paste, no file transfer.
- Config values come from the team's inventory Excel sheet; the fresher
  types them into `config.env` next to the script.
- Every run is manual and approved by a senior first. No cron, no
  unattended runs.
- Servers have no internet access. Packages are installed offline by the
  Linux team.
- Database estate: 2-node RAC, ASM, Grid Infrastructure, physical Data
  Guard standby on a DR site, GoldenGate extract on a separate host, SFTP
  log and app-server reachability files written by other jobs.
- Pre-production has the same shape with **no GoldenGate**, and may have
  no standby and no backups.
- ssh between hosts is allowed.
- App tier: app1 to app10, control node app5. Web tier: web1 to web4,
  control node web1. Both mirrored on the DR site (dr-app1..10 with
  dr-app5, dr-web1..4 with dr-web1; DR names are placeholders).
- You have no access to any real server. Everything runs against stubs.

## 3. Design

### 3.1 Layout

```
FOR-CLAUDE.md            this file
CLAUDE.md                loader: points here, nothing else
README.md                public front page
docs/                    fresher docs (start-here, typing guide, config
                         mapping, approval form, output, safety, glossary,
                         offline install, change requests, contributing)
scripts/oracle-rac/      database-cluster scripts, typed on node 1
  README.md RUNBOOK.md HOW-IT-WORKS.md
  NAME/NAME.sh NAME/README.md NAME/CHANGELOG.md
scripts/linux/           per-host scripts for any RHEL server, RUNBOOK.md
  NAME/NAME.sh NAME/README.md NAME/CHANGELOG.md
ansible/                 scaffold only (section 3.10)
tools/                   repo checks, shared-section masters, hash list
tests/                   stubs, fixtures, run-stub.sh, make-samples.sh
.githooks/pre-commit     runs tools/check-all.sh on the staged tree
.github/workflows/ci.yml check-all, Rocky 8/9 gawk check, gitleaks
```

### 3.2 Scripts

Database cluster, `scripts/oracle-rac/`, all typed and run on node 1 as
oracle:

| Script | Checks |
|---|---|
| db-check | open mode, log mode, instances and uptime, app-schema sessions, process/session limits, blocking, long calls |
| space-check | TEMP and top consumer, 5 fullest tablespaces, ASM diskgroups |
| dr-check | archive destinations, standby destination, Data Guard gap and lag (run on the primary) |
| backup-check | FRA, RMAN backup age, failed jobs |
| node-check | CPU, memory, swap, load, filesystems, alert log ORA-, every node over ssh |
| crs-check | Clusterware resources TARGET vs STATE |
| proc-check | per node over ssh: ora_pmon instances, asm_pmon, each LISTENERS name, each CRS daemon named |
| gg-check | GoldenGate extracts via gg2.sh on the GG host over ssh |
| inputs-check | sftp_output, server_checklist, activesession.sh, freshness |

Any RHEL server, `scripts/linux/`, typed and run on each server it checks
(DB nodes as oracle, app/web as the login user, no root, no ssh):

| Script | Checks |
|---|---|
| host-check | running vs newest kernel-core, needs-restarting, chrony leap and offset, PROCS by exact name (pgrep -xc), failed systemd units, kdump, kernel log err+ |
| disk-check | space and inode use per mount, read-only local fs (/proc/mounts), SCSI path state (/sys), multipath running paths vs MPATH_MIN |
| hw-check | bonding slaves (/proc/net/bonding), HugePages, transparent hugepages (CHECK_HUGEPAGES=0 on app/web) |

`PROC_DIR` and `SYS_DIR` exist so tests can point at fixture trees;
production leaves the defaults. Site agent names never appear as
defaults: `PROCS` defaults to `crond,chronyd,sshd` and the site adds its
agents in config.env.

### 3.3 Script contract

- Bash, `#!/bin/bash`, `set -o pipefail`, never `set -e`.
- Rows `SECTION|KEY|VALUE|STATUS`. Statuses OK, WARN, CRIT, INFO only.
  Unreachable host or failed command = CRIT. Missing measurement = WARN.
  Never OK for data not obtained.
- Default output: aligned table (`column -t`) ending in a SUMMARY row
  (host, script, version, time, counts, overall). `--csv`: every field in
  double quotes, header `SECTION,KEY,VALUE,STATUS`.
- Options: `--help`, `--version`, `--check-config`, `--csv`. Exit codes:
  0 OK, 1 WARN, 2 CRIT, 64 bad usage, 65 bad or missing config.
- `--check-config`: loads config, runs detection, adds one CONFIG row per
  key with `[default]`, `[config]`, `[detected]` or `MISMATCH, detected X`
  (WARN), the list of checks, and TEST rows for connectivity (sqlplus
  login, ssh, files, binaries). Runs no checks. A senior reviews it before
  approving the run.
- Writes nothing: stdout and stderr only. No files, nothing in `/tmp`, no
  `rm`, `-delete`, no `>`/`>>` except to `/dev/null`. Over ssh only
  read-only commands (`bash -s` with a collect function, `sh gg2.sh`,
  `true`, `test -r`).
- Every external call in `timeout`; ssh with `-q -o BatchMode=yes -o
  ConnectTimeout=10`.

### 3.4 Typing budget

- At most **200 lines** per script, at most **80 characters** per line.
- ASCII only. No tabs, no backticks, no backslash-dollar anywhere.
- No variable named `l`, `O` or `I`.
- Line 1 `#!/bin/bash`, line 2 `#== S01 settings`. Sections `#== Snn name`
  numbered in order. At most one comment line per section; rationale goes
  in CHANGELOG and HOW-IT-WORKS.
- S01 holds `VERSION=`, `NAME="..."`, `ABOUT`, `CHECKS`, `KEYS`, defaults
  (`A=1 B=2` on one line, empty as `''`).
- Shared sections, identical everywhere, 25 lines or fewer each, masters
  in `tools/shared/`: `helpers` (S02), `output` (S03), `config` (S04),
  `options` (S05) in every script; `sql` (S06) in every database script.
  Edit masters, then `tools/sync-shared.sh`.
- Over budget: split the script. Never squeeze code.

### 3.5 Config

- `config.env` next to the script, `KEY=value` lines, no quotes, no
  comments. Values limited to `[A-Za-z0-9_./:,@+-]`. Keys ending WARN,
  CRIT, MAX, SECS, MIN, HRS, DAYS, TIMEOUT, MB, PORT or starting CHECK_
  must be numbers. Unknown key or bad value: exit 65. Values reach SQL run
  as SYSDBA; never loosen these rules.
- Detect before asking: GRID_HOME from `/etc/oracle/olr.loc`, ORACLE_SID
  from a single `ora_pmon_` process, nodes from `olsnodes`, standby
  destination from `v$archive_dest`. Config overrides detection.
- `need KEY` exits 65 naming the key and `docs/config-from-inventory.md`.

### 3.6 SQL

```
sql "temp_warn=$TEMP_WARN" <<'SQL'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 VERIFY OFF TAB OFF LINESIZE 1000
SELECT 'TEMP USAGE|...|' || CASE WHEN pct > &temp_warn THEN 'WARN' ... ;
EXIT
SQL
```

`sql()` prints `DEFINE name=value` per argument, then the quoted heredoc,
into `timeout sqlplus -s -L / as sysdba`. Only SELECT, WITH, SET, DEFINE,
EXIT. DEFINE stays on; `&` only as a substitution variable. Output lines
that match the row format become rows; `ORA-`/`SP2-` lines become CRIT
`DB QUERY error`; `ERROR`/`Process`/`Session` noise is skipped; anything
else is WARN `DB QUERY unparsed line`; rc 124 timed out, rc >= 126 cannot
run sqlplus, no rows at all `no output`.

### 3.7 Verifying typed copies

- Hash = SHA-256, first 12 hex characters, after deleting carriage
  returns and blank lines, squeezing runs of spaces/tabs to one space,
  trimming each line. Indentation does not matter; a missing space does.
- Fresher commands (docs/typing-guide.md), identical to
  `tools/gen-checksums.sh`:

  ```
  awk '{gsub(/\r/,"")}NF{$1=$1;print}' F | sha256sum | cut -c1-12
  awk 'BEGIN{printf "S00 "}{gsub(/\r/,"")}NF{$1=$1}/^#== S/{close(c);printf "%s %s ",$2,$3}NF{print|(c="sha256sum|cut -c1-12")}END{close(c)}' F
  ```

- Each script README carries the table between `<!-- checksums:start -->`
  and `<!-- checksums:end -->`; sample output between
  `<!-- sample:check-config:start/end -->` and `<!-- sample:run:start/end -->`.
- CHANGELOG entries list every changed line (section, old line, new line)
  so a typed copy is patched, not retyped.

### 3.8 Banned names

`tools/banned-terms.sha256`: lowercase SHA-256 of each banned term, one
per line. `tools/check-banned.sh` lowercases files, splits on characters
outside `[a-z0-9._-]`, hashes each token and each part split on `.`, `_`,
`-`, reports `file:line` only. Missing or empty list fails. Add terms with
`tools/add-banned-term.sh` (hidden input) or by hash alone. Hashes reduce
exposure; anyone can hash a guess and test it. Never write a banned term in
plain text anywhere: files, commit messages, PR text, chat summaries.

### 3.9 Checks, hook, CI

`tools/check-all.sh` (hook and CI run exactly this): shellcheck,
check-budget, check-no-write, check-readonly-sql, check-sanitized (IPv4,
email, ports other than 22, internal host names), check-banned,
sync-shared --check, gen-checksums --check. Every check fails loudly; no
skip paths. CI adds gitleaks and `bash -n` plus `gen-checksums --check` on
Rocky 8 and 9 (gawk). `.shellcheckrc` disables SC2317 only.

Tests: `tests/run-stub.sh NAME [FIXTURE] [-- OPTIONS]` runs a script
against `tests/stubs/bin` and `tests/fixtures/<fixture>`;
`tests/make-samples.sh` refreshes README samples.

### 3.10 Ansible

Scaffold only. Four inventories (`ansible/inventory/{app,web}-{prod,dr}.example.ini`),
one per control node, groups `<tier>_control`, `<tier>_managed`, `<tier>`,
`site_prod`/`site_dr`. `group_vars/{all,app,web}.yml.example`, a base
`ansible.cfg`, empty `playbooks/checks/`, `playbooks/actions/`, `roles/`.
No playbook, no role, no precise configuration until the owner supplies
it. Real inventories, group_vars and vault files are gitignored. The
database cluster stays outside Ansible.

When playbooks come: checks are read-only with `changed_when: false` and
the same status words; actions need `-e confirm=yes`, print the plan,
support `--check`, run `serial: 1`, pre- and post-check, stop on first
failure, and a README section "Before you run this on production". FQCN
module names, ansible-lint clean, no `shell`/`command` where a module
exists. ansible-lint joins check-all with the first playbook.

## 4. Decisions

| Decision | Why |
|---|---|
| Split the v2 checklist into one script per job | typing and verifying 750 lines in one file is not realistic |
| Line cap 200 (raised from 150) | shared sections take about 100 lines in a database script; at 150 the split needed about 14 scripts |
| Scripts write nothing; no mail, HTML, history, lock | manual approved runs need none of them; nothing to clean up |
| config.env parsed as data, never sourced | values reach SYSDBA SQL; sourcing allows command and SQL injection |
| Quoted heredoc + DEFINE | no `\$` escapes to type; thresholds stay out of the SQL text |
| Hash after squeezing spaces (not deleting them) | deleting all spaces hides typos such as `[-z` for `[ -z` |
| Banned names as hashes | the list must be committed and checked in CI without publishing it |
| node-check, proc-check and gg-check use ssh from node 1 | the fresher types the database scripts on node 1 only |
| Linux host scripts run locally on each server, no ssh | they serve app and web servers too, and Ansible will run them per host later |
| dr-check: STANDBY_DEST (number, none, blank=auto) | replaces the CHECK_DG toggle; detects and flags mismatches |
| gitleaks in CI only, not in the hook | a fresh session needs no gitleaks binary |
| Ansible back as scaffold; DB cluster stays manual | app/web tiers have control nodes; DB scripts stay typed |
| Site agent names live in config, not defaults | the security tooling list identifies the site |

Seed bugs fixed in the split (all logged in CHANGELOGs): non-numeric value
rated OK (now WARN), unparsed database line dropped (now WARN row),
sqlplus not found reported as database down, `ERROR:` line made a second
CRIT row.

## 5. Progress (2026-10-02)

| Phase | State |
|---|---|
| 0 Scaffold, tools, CI | done |
| 1 Oracle RAC scripts (9) | done; stub-tested only, never on a real database |
| 1b Linux host scripts (3) | done; rebuilt from the owner's old host-health script; stub-tested only |
| 2 bats tests | planned; list in tests/README.md |
| 3 Ansible | scaffold done; playbooks wait for owner's configuration |
| 4 Ansible actions | not started |

The old host-health script (colours and emoji, uname as "latest kernel",
`df -h` without `-P`, a temp file in the current folder, substring
`pgrep`, a hardcoded SID, any `tnslsnr`, nine CRS daemons ANDed, ntpstat,
PackageKit as required) became host-check, disk-check, hw-check and
proc-check. Its SID is in the banned-term hashes.

**Open with the owner:**
1. Banned-term hashes: only the owner's names and one SID are listed;
   employer, hosts, databases, schemas, agent product names still missing.
2. Inventory sheet and column names in docs/config-from-inventory.md are
   `CHANGE_ME_` placeholders.
3. Typing load ~1,400 lines for the DB scripts; copying a verified shared
   section between typed files on the same server is undecided.
4. crs-check exits 65 without GRID_HOME (v2 fell back to a default path):
   keep or revert.
5. crs-check reports "all ONLINE" when crsctl lists zero resources:
   proposed WARN, not built.
6. Untested on a real database: DEFINE inside string literals, ORACLE_HOME
   from pmon environ for remote alert log, gv$ counts on 19c.
7. Ansible: versions, privilege model, become, transfer path to control
   nodes, vault location, DR control nodes reaching production.
8. Linux scripts on app/web servers: which login user runs them, and
   whether that user may join `systemd-journal` (else KERNEL LOG is WARN).
9. A single SCSI path offline rates WARN (MULTIPATH carries the CRIT when
   no path is left); confirm.

**Backlog (do not build unprompted):** optional mail script, least-
privilege monitoring DB user guide, Splunk ingestion guide, GG manager/
pump/replicat coverage.

## 6. Agent rules

### Session start
1. Read this file in full.
2. `git config core.hooksPath .githooks`
3. Work on the branch the session names; never push elsewhere without the
   owner saying so. Never open a PR unless asked.

### Working style
- Output first. Terse. No preamble, no recap.
- Direct, unvarnished assessments; flag problems plainly.
- Do only the current task. Extra ideas go under "Proposed, not done".
- Existing check logic: report bugs with evidence and a proposed fix;
  change only after the owner agrees.
- Summaries: what exists, how verified, what is open.
- Before finishing: `tools/check-all.sh` passes, this file's progress
  section is current, commit, push.

### Safety (never break)
1. Monitoring is read-only; scripts write nothing (3.3).
2. Actions live under `scripts/actions/` or `ansible/playbooks/actions/`
   with every guard in 3.10; none exist today.
3. No real identifiers: IPs (examples 192.0.2.x, 198.51.100.x,
   203.0.113.x), host names, ports other than 22, DB/schema names, people,
   emails (example.com), employer. Placeholders `CHANGE_ME_SOMETHING`.
4. No secrets.
5. Never weaken a check, test or tool to get green. Flag it.
6. Never `--no-verify`.

### After changing a script
`tools/sync-shared.sh` (if shared), raise `VERSION=`,
`tools/gen-checksums.sh`, `tests/make-samples.sh`, CHANGELOG line-level
entry, RUNBOOK rows, `tools/check-all.sh`.

### Docs
- Fresher test: each command in its own code block with expected output;
  one action per step; success and failure shown; "if you see X, do Y";
  terms linked to docs/glossary.md; who runs it and on which machine;
  placeholders with where to find the value.
- Style: no em dashes, no adverbs, no "not X, it's Y", no throat-clearing,
  active voice with a named subject, specific nouns, varied sentence
  length, never "simply", "just", "obviously", "easy".

### Definition of done (every script)
Within budget, shared sections in sync; contract in 3.3; README (purpose,
host, user, typing, config keys, sample --check-config, sample run,
checksums, safety); CHANGELOG; RUNBOOK rows; stub runs including failure
paths; `tools/check-all.sh` passes.

### Naming
Scripts `scripts/<area>/<name>/<name>.sh`, kebab-case. Branches
`feat/<short>`, `fix/<short>`, `docs/<short>`.
