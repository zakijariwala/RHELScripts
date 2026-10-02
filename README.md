# RHELScripts

Read-only monitoring scripts for Oracle RAC clusters on RHEL 8 and 9.
Each script checks one area, prints an aligned table with a status per row
(OK, WARN, CRIT, INFO) and a summary, and exits 0, 1 or 2. None of them
writes anything.

The scripts reach a server one way: a team member reads them here on
GitHub and **types them by hand** on the server, then proves the copy is
exact with per-section hashes. Every run is manual and approved by a
senior first.

**New here?** Open [docs/00-start-here.md](docs/00-start-here.md).

## The scripts

| Script | Checks |
|---|---|
| [db-check.sh](scripts/oracle-rac/db-check/) | open mode, log mode, instances, app sessions, limits, blocking, long calls |
| [space-check.sh](scripts/oracle-rac/space-check/) | TEMP, tablespaces, ASM diskgroups |
| [dr-check.sh](scripts/oracle-rac/dr-check/) | archive destinations, Data Guard gap and lag |
| [backup-check.sh](scripts/oracle-rac/backup-check/) | Fast Recovery Area, RMAN backups |
| [node-check.sh](scripts/oracle-rac/node-check/) | CPU, memory, swap, load, filesystems, alert log, on every node |
| [crs-check.sh](scripts/oracle-rac/crs-check/) | Clusterware resources |
| [gg-check.sh](scripts/oracle-rac/gg-check/) | GoldenGate extracts |
| [inputs-check.sh](scripts/oracle-rac/inputs-check/) | sftp log, active sessions, app servers |

Where each one runs and in which order to set them up:
[scripts/oracle-rac/README.md](scripts/oracle-rac/README.md).

## Status

| Part | State |
|---|---|
| Repo checks, pre-commit hook, CI | done |
| Oracle RAC scripts (Phase 1) | done; tested against stubs only, not yet on a real database |
| bats tests (Phase 2) | planned: [tests/README.md](tests/README.md) |
| Ansible (app and web tiers, prod and DR) | scaffold only: [ansible/README.md](ansible/README.md) |

## Repo map

```
README.md                      this page
FOR-CLAUDE.md                  design, decisions, progress, agent rules
CLAUDE.md                      points Claude Code sessions to FOR-CLAUDE.md
LICENSE                        MIT
docs/
  00-start-here.md             which page to read for which job
  typing-guide.md              type a script on a server and prove it is exact
  config-from-inventory.md     where each config.env value comes from
  approval-checklist.md        the form a senior signs before a run
  reading-output.md            statuses, exit codes, table and CSV
  safety.md                    what the scripts may do; check it yourself
  glossary.md                  every term the docs use
  offline-install.md           sysstat without internet (Linux team)
  change-requests.md           change request template for production
  contributing.md              how maintainers change the repo
scripts/oracle-rac/
  README.md                    which script runs where
  RUNBOOK.md                   every output row: meaning and action
  HOW-IT-WORKS.md              a walk through the code
  NAME/NAME.sh                 the script to type
  NAME/README.md               setup, config keys, samples, checksums
  NAME/CHANGELOG.md            line-by-line changes per version
ansible/                       scaffold: app and web tiers, prod and DR
tools/                         repo checks (maintainers and CI only)
tests/                         stubs, fixtures, sample generator
.githooks/pre-commit           runs tools/check-all.sh on staged files
.github/workflows/ci.yml       runs the same checks on every push
```

## License

MIT. See [LICENSE](LICENSE).
