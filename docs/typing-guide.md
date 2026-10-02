# Typing guide

Scripts from this repo reach a server one way: you read them on GitHub and
type them by hand. No copy-paste, no file transfer. This page shows how to
type a script so it comes out exact, and how to prove it.

You need: a browser with the script's page open on GitHub, and an ssh
session to the server.

## Who types, and where

| Script | Server | User | Folder |
|---|---|---|---|
| every script in `scripts/oracle-rac/` | node 1 | oracle | `/home/oracle/scripts/oracle-rac/<script name>` |

Each script's README repeats this in its first table.

1. **Your user, on node 1**: become oracle.

   ```
   sudo -iu oracle
   ```

   Expected: the prompt changes to `[oracle@racnode1 ~]$`. If you see
   `user is not in the sudoers file`, ask your team lead for the right to
   become oracle.

2. **oracle, node 1**: create the script's folder and go into it. The
   example uses `db-check`; use your script's name.

   ```
   mkdir -p /home/oracle/scripts/oracle-rac/db-check && cd /home/oracle/scripts/oracle-rac/db-check
   ```

   No output means success.

## vi in five minutes

vi has two modes. In **normal** mode keys are commands. In **insert** mode
keys type text. `Esc` always returns to normal mode.

| You want to | Press (normal mode) |
|---|---|
| open or create a file | `vi db-check.sh` (at the shell prompt) |
| start typing before the cursor | `i` |
| start typing on a new line below | `o` |
| stop typing | `Esc` |
| save | `:w` then Enter |
| save and quit | `:wq` then Enter |
| quit without saving | `:q!` then Enter |
| show line numbers | `:set number` then Enter |
| show hidden characters (tabs show as `^I`, line ends as `$`) | `:set list` then Enter |
| hide them again | `:set nolist` then Enter |
| stop vi indenting new lines for you | `:set noautoindent` then Enter |
| go to line 120 | `:120` then Enter |
| delete the character under the cursor | `x` |
| delete the whole line | `dd` |
| undo | `u` |
| find text | `/text` then Enter, `n` for the next one |

Run `:set noautoindent` before you start typing. Indentation does not
change a hash, but vi's automatic indent can pile up and make the file
hard to read.

## Type one section at a time

Every script is cut into sections, each starting with a marker line such
as `#== S02 helpers`. Type one section, save, check its hash, then move on.
A typo then costs you one section, never the whole file.

1. **oracle, node 1**: open the file.

   ```
   vi db-check.sh
   ```

2. Press `i`. Type the first line, `#!/bin/bash`, and section S01 down to
   the line before `#== S02`.

3. Press `Esc`, type `:w`, press Enter. vi shows `"db-check.sh" ... written`.

4. Check the section ([below](#verify-a-section)). Match: continue with the
   next section. No match: [find the typo](#find-and-fix-a-typo).

5. Repeat until the last section. Then `:wq`.

Things that matter when you type:

| Matters | Does not matter |
|---|---|
| every letter, digit and symbol | indentation (spaces at the start of a line) |
| a space between two words (`[ -z` is not `[-z`) | how many spaces in a row (one or four) |
| `'` versus `"` versus a backtick | spaces at the end of a line |
| upper or lower case | blank lines |
| `(` versus `{` versus `[` | |

Characters people mix up: `l` (lower L) and `1`, `O` and `0`, `|` (pipe)
and `l`, `'` (quote) and the backtick. The scripts never use a backtick,
and never name a variable `l`, `O` or `I`.

## Verify a section

**oracle, node 1**, in the script's folder. Type this command once; after
that, press the up arrow to run it again. Replace `db-check.sh` with your
file.

```
awk 'BEGIN{printf "S00 "}{gsub(/\r/,"")}NF{$1=$1}/^#== S/{close(c);printf "%s %s ",$2,$3}NF{print|(c="sha256sum|cut -c1-12")}END{close(c)}' db-check.sh
```

Expected: one line per section you have typed so far, for example:

```
S00 b875f928546a
S01 settings 7d1c0f3a92e4
S02 helpers d9deb6ab5c4d
```

Compare each line with the **Checksums** table at the bottom of the
script's README. All 12 characters must match.

- **S00** is the first line, `#!/bin/bash`, alone.
- The last section you typed may show a different hash while you are still
  in the middle of it. Only a finished section must match.
- The command writes nothing; it only prints.

What the command does: it removes carriage returns and blank lines,
squeezes every run of spaces to one, trims both ends of each line, then
hashes each section with `sha256sum` and prints the first 12 characters.
That is why indentation does not matter and a missing space does.

## Verify the whole file

When every section matches, check the whole file and the syntax.

1. **oracle, node 1**: the whole-file hash.

   ```
   awk '{gsub(/\r/,"")}NF{$1=$1;print}' db-check.sh | sha256sum | cut -c1-12
   ```

   Expected: the "whole file" hash in the README's Checksums table.

2. **oracle, node 1**: the syntax check. `bash -n` reads the script and
   runs nothing.

   ```
   bash -n db-check.sh && echo SYNTAX OK
   ```

   Expected: `SYNTAX OK`. If you see `line 87: syntax error near
   unexpected token`, look at line 87 and the line before it
   (`:set number`, `:87`).

3. **oracle, node 1**: the help text, as a last check that the file starts
   correctly.

   ```
   bash db-check.sh --version
   ```

   Expected: `db-check 1.0.0` (the VERSION in the README's table).

Write down the whole-file hash and the result of `bash -n` on the
[approval checklist](approval-checklist.md).

## Find and fix a typo

The section hashes tell you which section holds the typo. Then:

1. Open the file and go to that section: `/#== S07` then Enter.
2. Turn on line numbers and hidden characters: `:set number`, `:set list`.
3. Compare the section with GitHub line by line. Read each line
   backwards, from its end to its start: your eye then sees characters
   instead of the words you expect.
4. Look first at: quotes, `$`, `|`, brackets, `-` versus `_`, and a
   missing space between two words.
5. A `^I` in `:set list` mode is a tab. Tabs do not change the hash, but
   the repo's scripts contain none; replace it with spaces to keep the
   file identical.
6. Fix, `:w`, run the section check again.

If one section will not match after three careful comparisons, ask a
colleague to read it to you while you watch the screen. Two people find a
typo faster than one.

## Updating to a new version

Do not retype the whole file. The script's [CHANGELOG](../scripts/oracle-rac/db-check/CHANGELOG.md)
lists each changed line as section, old line, new line. Edit only those
lines, change `VERSION=`, then check the changed sections and the whole
file against the new Checksums table.
