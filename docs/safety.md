# Safety

This repo holds two kinds of code. Know which kind you are about to run.

| Kind | Where it lives | What it may change |
|---|---|---|
| **Monitoring** | `scripts/` (not `scripts/actions/`), `ansible/playbooks/checks/` | Nothing in the database. On the OS: its own lock file, its own history log, and a mail when you ask for one. |
| **Action** | `scripts/actions/`, `ansible/playbooks/actions/` | What its README says, and only after you pass the confirm flag. |

## What "read-only" means here

A monitoring script:

- sends the database `SELECT` and `WITH` queries, plus the [sqlplus](glossary.md#sqlplus)
  commands `SET` (output layout) and `EXIT`. Nothing else.
- never starts, stops, kills or restarts a process or service.
- writes on disk only the files its README lists under "What it writes".
  For the Oracle RAC checklist that list is: a lock file in `/tmp`, a
  history log directory, and nothing more when you pass `--no-history`.
- sends mail only when you pass `--mail` or `--mail-if-issues`.

## What an action does before it changes anything

Every action script or playbook:

1. refuses to run without an explicit flag: `-e confirm=yes` for Ansible,
   `--i-understand` for bash.
2. prints what it will do and to which hosts, then waits.
3. supports a dry run (`--check` in Ansible) that changes nothing.
4. works on one host at a time ([serial](glossary.md#serial) `1`).
5. checks the host before the change and again after it, and stops at the
   first failure.
6. has a README section "Before you run this on production" that sends
   you to [change-requests.md](change-requests.md).

## Audit any script yourself

You do not need to trust this page. These steps let you check a script
with your own eyes before it runs on a server. The example audits the
Oracle RAC checklist; swap in any path.

Run every step as **your user** on **your machine**, inside the repo folder.

1. Run the read-only SQL audit on the script.

   ```
   tools/check-readonly-sql.sh scripts/oracle-rac-checklist/checklist.sh
   ```

   Success looks like:

   ```
   scripts/oracle-rac-checklist/checklist.sh: 20 SELECT, 1 WITH, 10 SET, 1 EXIT
   RESULT: OK (1 files)
   ```

   Failure looks like:

   ```
   scripts/oracle-rac-checklist/checklist.sh:240: FAIL write keyword UPDATE: UPDATE ...
   RESULT: FAIL (1 of 1 files have problems)
   ```

   If you see `FAIL`, stop. Do not run the script. Report the line to the
   repo owner.

   The tool reads every SQL block a script sends to sqlplus. It fails on
   any statement that does not start with `SELECT`, `WITH`, `SET` or `EXIT`,
   and on any line holding a write word such as `INSERT`, `UPDATE`,
   `DELETE`, `DROP`, `ALTER`, `GRANT`, `BEGIN`, `COMMIT`, `SHUTDOWN` or
   `DBMS_`. `tools/check-readonly-sql.sh --help` lists every rule.

2. Search the script for shell commands that change files or processes.

   ```
   grep -nE '((^|[[:space:];])>>? *"|exec [0-9]+>|\b(rm|mv|cp|mkdir|chmod|chown|kill|pkill|systemctl|reboot|shutdown|srvctl|tee|truncate|dd) |-delete|crsctl +(stop|start|delete|modify))' scripts/oracle-rac-checklist/checklist.sh | grep -vE '^[0-9]+: *#'
   ```

   You get a list of line numbers and lines. Read each one. For the
   checklist you should see five lines, all of them listed in the script's
   README under "What it writes":

   ```
   ...:    mkdir -p "$LOG_DIR" 2>/dev/null || return
   ...:            "$RUN_TS" "$HOST" ... "${R_STATUS[$i]}" >> "$f"
   ...:        "$RUN_TS" "$HOST" "$DB_NAME" "$SUMMARY" "$OVERALL" >> "$f"
   ...:    find "$LOG_DIR" -name 'checklist_*.log' -mtime +"$LOG_RETENTION_DAYS" -delete 2>/dev/null
   ...:exec 9>"/tmp/checklist_$(id -un).lock"
   ```

   The first four write the history log and delete history files older
   than the retention period. The last one creates the lock file.

   If you see a line that writes somewhere the README does not mention,
   stop and ask the repo owner.

3. List every other program the script calls on a remote host or from disk.

   ```
   grep -nE '\b(ssh|scp|sh|bash) ' scripts/oracle-rac-checklist/checklist.sh | grep -v '^[0-9]*: *#'
   ```

   Read each called script too. The tools in step 1 do **not** read
   scripts that live on the servers, such as `gg2.sh` and
   `activesession.sh`. Run step 1 and step 2 on those files as well:

   ```
   tools/check-readonly-sql.sh /path/to/gg2.sh
   ```

4. On the server, prove what the run touched. Run these as the user who
   runs the script (for the checklist, **oracle** on **node 1**).

   Create a marker file:

   ```
   touch /tmp/before-run
   ```

   No output means success.

   Run the script with history off:

   ```
   bash ./checklist.sh --no-history --table
   ```

   List every file in the oracle home and `/tmp` changed since the marker:

   ```
   find "$HOME" /tmp -xdev -newer /tmp/before-run -type f 2>/dev/null
   ```

   Expected output for the checklist:

   ```
   /tmp/checklist_oracle.lock
   ```

   If you see any other file, the script wrote it. Compare it with the
   README's "What it writes" list and report anything missing from that
   list.

## The banned-terms list

`tools/check-sanitized.sh` blocks real IP addresses, email addresses, ports
other than 22 and internal host names with fixed patterns. It cannot guess
your employer's name, your database names or your colleagues' names. You
give it those in a private list that never enters git.

Maintainers run these steps once, as **your user** on **your machine**.

1. Copy the example list.

   ```
   cp tools/banned-terms.txt.example tools/banned-terms.txt
   ```

   No output means success.

2. Open it and replace the `CHANGE_ME_...` lines with the real words: the
   employer name and its short forms, host names, database, service and
   schema names, GoldenGate process names, people's names, internal
   domains. One per line.

   ```
   vi tools/banned-terms.txt
   ```

3. Confirm git ignores it.

   ```
   git check-ignore -v tools/banned-terms.txt
   ```

   Expected output:

   ```
   .gitignore:21:tools/banned-terms.txt	tools/banned-terms.txt
   ```

   If you see no output, git would commit the file. Stop and fix
   `.gitignore` before you go further.

4. Run the full check.

   ```
   tools/check-sanitized.sh
   ```

   Expected output (the file count grows with the repo):

   ```
   RESULT: OK (27 files)
   ```

   If you see `FAIL banned term (list line N)`, a file contains the word
   on line N of your list. The tool prints the file and line, and never the
   word itself, because CI logs on a public repo are public. Run
   `tools/check-sanitized.sh --show` on your own machine to see the line.

5. Install the pre-commit hook so every commit runs this check on your
   machine first: [pre-commit-hook.md](pre-commit-hook.md).

6. Give CI the same list. In GitHub, open the repo, then **Settings >
   Secrets and variables > Actions > New repository secret**. Name:
   `BANNED_TERMS`. Value: the contents of your list, one term per line.
   Until this secret exists, CI skips the banned-terms check and shows a
   yellow warning.

## If a real identifier reaches GitHub

The repo is public. Treat anything pushed as seen by others, even if you
delete it a minute later.

1. Replace the value with a `CHANGE_ME_...` placeholder and push the fix.
2. Tell the repo owner which value leaked and in which commit.
3. If it was a password or key, rotate it now. Deleting the commit does not
   make it secret again.
4. The owner decides whether to rewrite git history. A history rewrite
   removes the value from the repo but not from forks or clones.
