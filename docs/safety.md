# Safety

## What the scripts may do

Every script in `scripts/` is a **monitoring** script. It:

- sends the database only `SELECT` and `WITH` queries, plus the SQL*Plus
  commands `SET` (output layout), `DEFINE` (fills in a threshold) and
  `EXIT`,
- writes **nothing**: no file, no log, nothing in `/tmp`, on this host or
  any other. It prints to the screen only,
- over ssh (only `node-check.sh` and `gg-check.sh`) runs read-only commands
  on the other host: its own measuring function, `sh gg2.sh`, `true`,
  `test -r`,
- never starts, stops, kills or restarts anything.

No script in this repo changes state. Actions (reboots, restarts) are on
hold together with Ansible ([AMENDMENT 01](decisions/AMENDMENT-01.md), D5).
If one is ever added it lives under `scripts/actions/` and follows the
guards in [CLAUDE.md](../CLAUDE.md).

## How the repo proves it

On every change, CI and the pre-commit hook run:

| Tool | Proves |
|---|---|
| `tools/check-readonly-sql.sh` | every SQL statement starts with SELECT, WITH, SET or EXIT; no write keyword anywhere; sqlplus gets SQL only from a quoted heredoc and DEFINE lines |
| `tools/check-no-write.sh` | no redirect to a file, no `rm`, `mv`, `cp`, `mkdir`, `tee`, `sed -i`, `-delete`, no `/tmp`, no awk that writes |
| `tools/check-budget.sh` | the file stays small enough to type and read |

The copy you typed on the server is the copy CI checked when its hashes
match the README's checksum table ([typing guide](typing-guide.md)).

## Check it yourself on the server

You do not need to trust this page. Run these as **oracle** in the
script's folder, on your typed copy. None of them changes anything.
Replace `db-check.sh` with your script.

1. Look for commands that write files.

   ```
   grep -nwE 'rm|mv|cp|mkdir|touch|tee|chmod|chown|truncate|dd|ln|mktemp|exec' db-check.sh; grep -nE -- '-delete|sed -i|/tmp|>>' db-check.sh
   ```

   Expected: no output. Any line it prints, stop and report it to the
   senior before you run the script.

2. Look for SQL that writes.

   ```
   grep -inwE 'insert|update|delete|merge|drop|alter|create|grant|revoke|truncate|begin|commit|rollback|execute|exec|shutdown|startup|spool|kill|purge' db-check.sh
   ```

   Expected: only lines containing `awk ... 'BEGIN {`. `BEGIN` there is an
   awk keyword that runs a block before reading input; it is not SQL. Any
   other line: stop and report it.

3. List the words that start SQL lines.

   ```
   grep -oE '^[A-Z]+( |;|$)' db-check.sh | sort | uniq -c
   ```

   Expected: only `EXIT`, `SELECT`, `SET`, `SQL` (the line that ends each
   SQL block) and, in `dr-check.sh`, `WITH`. The counts differ per script.

4. Prove at run time that nothing changed. After the senior approved the
   run, run it this way instead of the plain command:

   ```
   t=$(date '+%F %T'); bash db-check.sh; find "$HOME" /tmp -xdev -newermt "$t" -type f 2>/dev/null
   ```

   Expected: the script's output, then nothing more. Any file `find`
   prints was written during the run. Some other process may have written
   it; report it to the senior so they can tell.

The scripts this repo does not contain, `gg2.sh` and `activesession.sh`,
run with your rights when `gg-check.sh` and `inputs-check.sh` call them.
No tool here checks them. Run steps 1 and 2 on them too, and ask the senior
who owns them.

## Banned names: hashed, not hidden

`tools/check-sanitized.sh` blocks real IP addresses, email addresses,
ports other than 22 and internal host names with fixed patterns.
`tools/check-banned.sh` blocks names the patterns cannot know: the
employer, people, real hosts, databases, schemas.

The banned names live in `tools/banned-terms.sha256` as SHA-256 hashes
only, one per line. The scanner lowercases every file, cuts it into words
at every character outside `a-z 0-9 . _ -`, hashes each word and each part
of it split at `.`, `_` and `-`, and compares. It reports file and line,
never the word.

**The limit.** Hashes keep the list out of plain sight; they do not make
it secret. Anyone who guesses a candidate name can hash it and test it
against the file. Treat the hash file as a guard against accidental leaks,
not as a vault.

To add a name, the repo owner either runs `tools/add-banned-term.sh` in a
terminal (hidden input, only the hash is stored), or computes the hash on
any Linux machine and gives only the hash to the Claude Code session:

```
read -rs t; printf '%s' "${t,,}" | sha256sum | cut -c1-64; unset t
```

Type the name at the empty prompt and press Enter. The command prints a
64-character hash; the name never appears on screen or in the shell
history.

## If a real identifier reaches GitHub

The repo is public. Treat anything pushed as seen by others, even if it is
deleted a minute later.

1. Replace the value with a `CHANGE_ME_...` placeholder and push the fix.
2. Add its hash to `tools/banned-terms.sha256` so it cannot return.
3. If it was a password or key, rotate it now. Deleting the commit does not
   make it secret again.
4. The owner decides whether to rewrite git history. A history rewrite
   removes the value from the repo but not from forks or clones.
