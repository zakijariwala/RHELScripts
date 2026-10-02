# Contributing (maintainers)

The repo changes only through Claude Code sessions run by the repo owner.
Nobody edits files in the GitHub browser, and nobody clones the repo onto
a server or a desktop. The rules every session follows are in
[FOR-CLAUDE.md](../FOR-CLAUDE.md); this page is the short version.

## Every session

1. Turn on the pre-commit hook. It runs every check on the staged files
   and blocks the commit on any failure.

   ```
   git config core.hooksPath .githooks
   ```

2. Before a commit, run the same checks by hand to see every problem at
   once:

   ```
   tools/check-all.sh
   ```

   Expected, last line: `RESULT: OK (8 checks)`.

CI on GitHub runs `tools/check-all.sh` too, plus gitleaks for secrets and
the checksum check on RHEL 8 and 9 rebuilds (gawk).

## Changing a script

1. Edit the script under `scripts/oracle-rac/NAME/`. Shared sections
   (`helpers`, `output`, `config`, `options`, `sql`) are edited in
   `tools/shared/` only, then copied into every script:

   ```
   tools/sync-shared.sh
   ```

2. Raise `VERSION=` in S01.
3. Regenerate the checksum tables and the README samples:

   ```
   tools/gen-checksums.sh && tests/make-samples.sh
   ```

4. Add a CHANGELOG entry listing every changed line as section, old line,
   new line. People update typed copies from it, line by line.
5. `tools/check-all.sh`, then commit.

## Adding a script

Copy the layout of an existing script: `#!/bin/bash`, `#== S01 settings`
with `VERSION`, `NAME`, `ABOUT`, `CHECKS`, `KEYS` and defaults, the shared
sections as marker lines only (`tools/sync-shared.sh` fills them), then its
own sections and `main`. Give it a README with the same headings as the
others, the two sample markers and the checksum markers, a CHANGELOG, and
RUNBOOK entries for every row it can print.

## Budget

200 lines, 80 characters per line, ASCII, no tabs, no backticks, no
backslash-dollar, no variable named `l`, `O` or `I`, at most one comment
line per section. If a script outgrows it, split it. Never squeeze code to
fit.

## Banned names

`tools/banned-terms.sha256` holds hashes of names that must never appear.
Add one with `tools/add-banned-term.sh` in a terminal, or compute the hash
elsewhere and paste only the hash into the file (see
[safety.md](safety.md#banned-names-hashed-not-hidden)).
