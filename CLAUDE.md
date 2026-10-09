# CLAUDE.md

Personal scripts for RHEL 8/9 servers, written at home, tried at work.

Rules for every script unless the owner says otherwise:

- One server only. It runs on the box it checks. No ssh fan-out, no
  inventory lookups inside scripts.
- Typeable by hand: short (aim for ~120 lines or fewer), plain bash, no
  clever tricks. Split instead of growing.
- Read-only unless the script's purpose is an action: no files written,
  nothing changed.
- Hardcode IPs, host names, SIDs where a script needs them.
  docs/inventory.md is the server list.
- `set -o pipefail`, every command that can hang in `timeout`.
- Must also run as `sh script.sh` (bash in POSIX mode): no `< <(...)`
  process substitution. Test with `bash --posix`.
- Lines `[ OK ]`, `[WARN]`, `[CRIT]`; exit 0/1/2.
- shellcheck clean (style notes may stay if the fix hurts readability).
- Each script folder has a README: how to run, settings, what it checks.
- New scripts: propose the design first. Approved designs go in
  docs/planned.md. Build only when the owner says so.
