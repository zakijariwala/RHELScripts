# RHELScripts

Monitoring and operations scripts for RHEL servers and Oracle RAC
databases. Bash scripts check one cluster from the server itself. Ansible
playbooks (from Phase 3) check many servers from one control node and run
guarded actions such as rolling reboots.

Every monitoring script reads and reports. None of them changes the
database or the operating system. Two tools in `tools/` prove that on every
commit, and `docs/safety.md` shows you how to prove it yourself.

**New here?** Open [docs/00-start-here.md](docs/00-start-here.md). It tells
you which page to read for the job in front of you.

## Status

| Part | State |
|---|---|
| Repo scaffold, safety tools, CI | Done (Phase 0) |
| Oracle RAC checklist (`scripts/oracle-rac-checklist/`) | Phase 1, not yet moved in |
| Tests (`tests/`) | Phase 2 |
| Ansible checks (`ansible/playbooks/checks/`) | Phase 3 |
| Ansible guarded actions (`ansible/playbooks/actions/`) | Phase 4 |

## 5-minute quickstart

You need a Linux machine with `git` and `bash`. Your laptop or any test
server works. You do **not** need Oracle or Ansible for these steps.

1. Your user, on your machine: clone the repo.

   ```
   git clone https://github.com/zakijariwala/RHELScripts.git
   ```

   Expected output ends with:

   ```
   Resolving deltas: 100% (...), done.
   ```

   If you see `Could not resolve host: github.com`, the machine has no
   internet access. Clone on a machine that has it, then copy the folder
   across with `scp -r`.

2. Your user: enter the folder.

   ```
   cd RHELScripts
   ```

3. Your user: run the read-only SQL audit.

   ```
   tools/check-readonly-sql.sh
   ```

   Expected output (the file count grows as scripts arrive):

   ```
   RESULT: OK (0 files)
   ```

   If you see `Permission denied`, run `chmod +x tools/*.sh` and repeat.

4. Your user: run the sanitize check.

   ```
   tools/check-sanitized.sh --allow-missing-terms
   ```

   Expected output:

   ```
   WARN banned-terms list not found or empty at tools/banned-terms.txt; check 5 skipped
   RESULT: OK (27 files)
   ```

   The number of files changes as the repo grows. The `WARN` line means
   you have no private list of banned words yet. Maintainers create one as
   described in [docs/safety.md](docs/safety.md#the-banned-terms-list).

## Repo map

```
README.md                  this page
CLAUDE.md                  rules for Claude Code sessions in this repo
LICENSE                    MIT
docs/
  00-start-here.md         which doc to read for which job
  glossary.md              every term the docs use (RAC, ASM, FRA, sysdba...)
  reading-output.md        statuses, exit codes, output formats   (Phase 1)
  safety.md                read-only vs action; audit any script yourself
  offline-install.md       install tools on servers with no internet (Phase 1)
  change-requests.md       change request template for production
  contributing.md          add a new script from scripts/_template (later)
scripts/
  _template/               skeleton for new check scripts       (later)
  oracle-rac-checklist/    Oracle RAC health checklist          (Phase 1)
ansible/                   playbooks for many servers           (Phase 3)
  playbooks/checks/        read-only
  playbooks/actions/       guarded, state-changing              (Phase 4)
tests/                     bats tests with fake sqlplus, ssh... (Phase 2)
tools/
  check-readonly-sql.sh    fails if monitoring SQL holds a write keyword
  check-sanitized.sh       fails on IPs, emails, ports, banned names
  banned-terms.txt.example template for your private banned-words list
.github/workflows/ci.yml   runs shellcheck, bats, ansible-lint, both tools, gitleaks
```

## Safety in one paragraph

Scripts under `scripts/` and playbooks under `ansible/playbooks/checks/`
read state and print it. Anything that changes state (a reboot, a service
restart) lives under `ansible/playbooks/actions/` or `scripts/actions/`,
refuses to run without an explicit confirm flag, and needs an approved
change request on production. Details in [docs/safety.md](docs/safety.md).

## License

MIT. See [LICENSE](LICENSE).
