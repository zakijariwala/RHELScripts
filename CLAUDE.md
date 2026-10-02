# CLAUDE.md

Rules for every Claude Code session in this repo. Read all of it before
changing anything.

## The repo

Linux and Oracle monitoring and operations scripts for a banking
infrastructure team. Bash check scripts under `scripts/`, Ansible under
`ansible/`. The repo is **public**.

- Targets: RHEL 8 and RHEL 9, Oracle 19c (RAC, ASM, Grid Infrastructure,
  Data Guard, GoldenGate).
- Servers have no internet access. Installs are offline (RPMs copied in,
  no pip or ansible-galaxy from the internet). See `docs/offline-install.md`.
- You have no access to any real server. Everything you run, you run
  locally against stubs in `tests/stubs/` and fixtures in `tests/fixtures/`.
- Change management applies on production. Anything scheduled or
  state-changing needs an approved change request (`docs/change-requests.md`).

## How the owner wants you to work

- Output first. Terse. No preamble, no recap of the request.
- Direct, unvarnished assessments. Flag problems plainly.
- Do only what the current task asks. List extra ideas under
  "Proposed, not done". Do not build them. Ask first.
- If you find a bug or a doubtful choice in an existing script, report it
  with evidence and a proposed fix. Change check logic only after the owner
  agrees.
- Summaries: what exists, how you verified it, what is open.

## The fresher test (every doc must pass)

A fresher knows basic Linux (cd, ls, cat, vi, ssh, sudo) and has never used
Oracle, RAC, Data Guard, GoldenGate or Ansible.

- Every command is copy-paste ready, in its own code block, with the
  expected output shown underneath.
- One action per numbered step.
- Show what success looks like and what failure looks like at each step.
- "If you see X, do Y" for every failure you can predict.
- Define each term on first use and link it to `docs/glossary.md`.
- Never write "simply", "just", "obviously", "easy".
- Say who runs each command (root, oracle, your user) and on which machine
  (node 1, node 2, control node).
- Every placeholder looks like `CHANGE_ME_SOMETHING` and the doc says where
  to find the real value.

## Hard rules

### Safety (never break these)

1. **Monitoring is read-only.** Scripts under `scripts/` and playbooks under
   `ansible/playbooks/checks/` must not change DB or OS state. SQL is
   `SELECT`/`WITH` only, plus SQL*Plus `SET` and `EXIT`.
   `tools/check-readonly-sql.sh` enforces this. Write every SQL heredoc so
   the tool can see it: open it on the `sqlplus` line, or give it a
   delimiter containing `SQL` (`<<EOSQL`).
2. **Actions are separate and guarded.** Anything that changes state lives
   under `ansible/playbooks/actions/` or `scripts/actions/`. Each one:
   - refuses to run without an explicit flag (`-e confirm=yes` in Ansible,
     `--i-understand` in bash),
   - prints exactly what it will do and to which hosts before doing it,
   - supports a dry run (`--check` in Ansible),
   - runs one host at a time (`serial: 1`) unless told otherwise,
   - runs a pre-check and a post-check,
   - has a README section titled "Before you run this on production" that
     points to `docs/change-requests.md`.
3. **No real identifiers in the repo.** No IPs, hostnames, ports other than
   22, DB or schema names, people, email addresses, or employer names.
   Real values go in gitignored `config.env` / inventory files; the repo
   ships `*.example` versions. `tools/check-sanitized.sh` enforces this.
   For example IPs use 192.0.2.x, 198.51.100.x or 203.0.113.x. For example
   mail addresses use example.com.
4. **No secrets.** No passwords, keys, tokens. Ansible secrets go in vault
   files that are gitignored, with a documented example.
5. Never weaken a check to make a test pass. Flag it instead. The same goes
   for the two tools in `tools/`: never loosen a pattern to get green.

### Code conventions

- Bash, `#!/bin/bash`, `set -o pipefail`, no `set -e` (one failed check must
  not stop the rest). Shellcheck clean.
- Must run on the bash, coreutils and gawk shipped with RHEL 8 and RHEL 9.
  Tools in `tools/` must also run on Ubuntu (mawk) for CI.
- Each script runs as a **single self-contained file** plus an optional
  `config.env` next to it. No shared libraries a fresher has to copy too.
- Output contract for every check script and playbook:
  - rows `SECTION|KEY|VALUE|STATUS`
  - status vocabulary `OK`, `WARN`, `CRIT`, `INFO` and nothing else
  - unreachable host or failed command = `CRIT`; missing measurement =
    `WARN`; never `OK` for data you did not get
  - exit codes: 0 OK, 1 WARN, 2 CRIT, 3 already running, 64 bad usage
  - flags: `--help`, `--table`, `--html`, `--no-history`, `--mail`,
    `--mail-if-issues` where they make sense
- Every external call (ssh, sqlplus, remote scripts) wrapped in `timeout`;
  ssh uses `-o BatchMode=yes -o ConnectTimeout=10`.
- Every threshold and host lives in config, never inline.
- Ansible: FQCN module names, `ansible-lint` clean, no `shell`/`command`
  where a module exists, `changed_when: false` on every read-only task.

### Naming

- Scripts: `scripts/<area>-<thing>/<thing>.sh`, kebab-case
  (`scripts/oracle-rac-checklist/checklist.sh`).
- Branches: `feat/<short>`, `fix/<short>`, `docs/<short>`.
- Annotations in scripts: `[ADDED]`, `[CHANGED]`, `[FIXED]`, `[REMOVED]`,
  with a version suffix for later changes (`[CHANGED v2.1]`). Struck-out old
  lines start `#~` in shell and `--~` in SQL and never execute.

### Writing style for docs ("Stop Slop")

- No em dashes.
- Active voice with a human or a named component as the subject.
- No adverbs.
- No "not X, it's Y" constructions.
- No throat-clearing openers ("In this guide we will...").
- Specific nouns over vague statements.
- Vary sentence length.

## Before every commit

Run all three and fix what they report:

```
find scripts tools tests -name '*.sh' -print0 | xargs -0 -r shellcheck
tools/check-readonly-sql.sh
tools/check-sanitized.sh
```

`tools/check-sanitized.sh` needs `tools/banned-terms.txt` (gitignored). If it
is missing, ask the owner. Never create it with guessed words and never
commit it.

## Definition of done (every script or playbook)

- [ ] Runs from one file plus optional config
- [ ] Output follows the contract above
- [ ] README: purpose, prerequisites, setup, run, sample output
- [ ] RUNBOOK: every possible row, WARN/CRIT actions
- [ ] Safety statement: exactly what it reads and writes
- [ ] Tests for healthy, each failure path, and unreachable
- [ ] shellcheck / ansible-lint clean
- [ ] check-readonly-sql and check-sanitized pass
- [ ] A fresher could use it with nothing but the docs
