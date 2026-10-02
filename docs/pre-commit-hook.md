# Pre-commit hook

A pre-commit hook is a script git runs every time you type `git commit`.
If the script fails, git refuses the commit. This repo's hook stops three
mistakes before they reach the public repo:

| Check | Stops |
|---|---|
| `tools/check-sanitized.sh` | real IP addresses, email addresses, ports other than 22, internal host names, and words from your banned-terms list |
| `tools/check-readonly-sql.sh` | SQL that could change the database inside a monitoring script under `scripts/` |
| `gitleaks` | passwords, private keys, API tokens |

The hook checks the **staged** version of each file: the version
`git add` put into the commit. Changes you have not added yet do not count.

CI runs the same checks on every push. The hook catches the mistake on your
machine, before the commit exists. Once a commit reaches GitHub, the repo
is public, and deleting it does not make it private again.

Run every step below as **your user** on **the machine where you commit**
(your laptop or jump host), inside your clone of the repo. You install the
hook once per clone.

## Step 1: check git and bash

1. Print the git version.

   ```
   git --version
   ```

   Expected output (any version 2.9 or newer works):

   ```
   git version 2.43.0
   ```

   If you see `command not found`, install git first. On RHEL:
   `sudo dnf install git-core`.

2. Move into your clone.

   ```
   cd RHELScripts
   ```

   No output means success. If you see `No such file or directory`,
   clone the repo first (see the root [README](../README.md#5-minute-quickstart)).

## Step 2: install gitleaks

gitleaks is a single program file. You download it from GitHub, check it,
and place it in your home folder. No root needed.

1. Check whether you already have it.

   ```
   gitleaks version
   ```

   If you see a version such as `8.28.0`, skip to Step 3.
   If you see `command not found`, continue.

2. Open https://github.com/gitleaks/gitleaks/releases in a browser on any
   machine with internet. Note the newest version number without the `v`,
   for example `8.28.0`. That number replaces `CHANGE_ME_GITLEAKS_VERSION`
   below.

3. Set the version in your shell.

   ```
   GL_VER=CHANGE_ME_GITLEAKS_VERSION
   ```

   No output means success.

4. Download the program and its checksum list. Run this on a machine with
   internet. If your commit machine has none, run it elsewhere and copy
   both files across with `scp`.

   ```
   curl -LO "https://github.com/gitleaks/gitleaks/releases/download/v${GL_VER}/gitleaks_${GL_VER}_linux_x64.tar.gz"
   ```

   ```
   curl -LO "https://github.com/gitleaks/gitleaks/releases/download/v${GL_VER}/gitleaks_${GL_VER}_checksums.txt"
   ```

   Each prints a progress bar and ends at `100`. If you see
   `curl: (6) Could not resolve host`, this machine has no internet access;
   use another one.

5. Check the download has not been tampered with.

   ```
   sha256sum --ignore-missing -c "gitleaks_${GL_VER}_checksums.txt"
   ```

   Expected output:

   ```
   gitleaks_8.28.0_linux_x64.tar.gz: OK
   ```

   If you see `FAILED`, delete both files and download again. If it fails a
   second time, stop and tell the repo owner.

6. Unpack the program into `~/.local/bin`.

   ```
   mkdir -p ~/.local/bin && tar -xzf "gitleaks_${GL_VER}_linux_x64.tar.gz" -C ~/.local/bin gitleaks
   ```

   No output means success.

7. Confirm your shell finds it.

   ```
   gitleaks version
   ```

   Expected output: the version you chose, for example `8.28.0`.

   If you see `command not found`, `~/.local/bin` is not on your PATH. Add
   it and reload your profile:

   ```
   echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc
   ```

## Step 3: create your banned-terms list

The hook needs `tools/banned-terms.txt`, the private list of words that
must never appear in the repo. Follow
[safety.md, "The banned-terms list"](safety.md#the-banned-terms-list),
steps 1 to 3. Come back here when `git check-ignore` confirms git ignores
the file.

## Step 4: install the hook

1. Run the installer.

   ```
   tools/install-hooks.sh
   ```

   Expected output:

   ```
   OK   hook installed: core.hooksPath = tools/git-hooks
   OK   gitleaks found: /home/CHANGE_ME_YOUR_USER/.local/bin/gitleaks
   OK   banned-terms list found: tools/banned-terms.txt
   ```

   The installer changes one setting in this clone's `.git/config`:
   `core.hooksPath = tools/git-hooks`. Git then runs
   `tools/git-hooks/pre-commit` before every commit. A `git pull` that
   brings a newer hook needs no reinstall.

   If you see `MISSING gitleaks`, go back to Step 2.
   If you see `MISSING tools/banned-terms.txt`, go back to Step 3.
   The hook is installed either way, and it blocks every commit until the
   missing piece exists.

   If you see `Permission denied`, run `chmod +x tools/install-hooks.sh`
   and repeat.

## Step 5: prove it works

1. Create a test file with a fake leak. The shell computes the last part
   of the IP address when the command runs, so this page itself holds no
   IP address for the sanitize check to flag.

   ```
   echo "NODE2_HOST=10.20.30.$((39 + 1))" > scripts/hook-test.sh
   ```

   No output means success.

2. Stage it.

   ```
   git add scripts/hook-test.sh
   ```

3. Try to commit.

   ```
   git commit -m "hook test"
   ```

   Expected output:

   ```
   pre-commit: check-sanitized (1 staged files)
   scripts/hook-test.sh:1: FAIL IPv4 address
   RESULT: FAIL (1 hits in 1 files)
   pre-commit: check-readonly-sql (1 staged scripts)
   RESULT: OK (1 files)
   pre-commit: gitleaks
   ... INF no leaks found
   pre-commit: BLOCKED. Fix the lines above, git add, and commit again.
   ```

   The commit did not happen. If instead you see a line such as
   `[main 1a2b3c4] hook test`, the hook did not run: check Step 4 and run
   `git config core.hooksPath`, which must print `tools/git-hooks`.

4. Remove the test file.

   ```
   git rm -f --cached scripts/hook-test.sh && rm scripts/hook-test.sh
   ```

   Expected output:

   ```
   rm 'scripts/hook-test.sh'
   ```

## When the hook blocks your commit

Read the lines above `BLOCKED`. Each `FAIL` names a file and a line.

| You see | Do this |
|---|---|
| `FAIL IPv4 address`, `email address`, `port other than 22`, `internal host name` | Replace the value with a `CHANGE_ME_...` placeholder. For an example IP use 192.0.2.x; for an example mail address use example.com. Run `tools/check-sanitized.sh --show FILE` to see the line. |
| `FAIL banned term (list line N)` | The file holds the word on line N of your banned-terms list. Replace it with a placeholder. |
| `FAIL write keyword ...` or `FAIL statement starts with ...` | A monitoring script holds SQL that could change the database. Monitoring SQL is `SELECT` and `WITH` only. Write actions belong under `scripts/actions/`. See [safety.md](safety.md). |
| `Finding: ... RuleID: ...` from gitleaks | A secret sits in that file and line. Remove it, keep the real value in a gitignored file (`config.env`, a vault file). If the secret ever left your machine, rotate it. |
| `FAIL gitleaks not installed` | Do Step 2. |
| `FAIL banned-terms list not found` | Do Step 3. |

After the fix, stage the file again (`git add FILE`) and commit again.

## Overrides

Two environment variables let one commit through with a check missing.
Each prints a `WARN` line, and CI still runs the full checks after you push.

| Command | When |
|---|---|
| `ALLOW_NO_GITLEAKS=1 git commit ...` | gitleaks is not installed yet on this machine |
| `ALLOW_MISSING_TERMS=1 git commit ...` | you have no banned-terms list yet (contributors without access to it) |

`git commit --no-verify` skips the hook and every check in it. Do not use
it in this repo.

## Turn the hook off

```
tools/install-hooks.sh --uninstall
```

Expected output:

```
Hook turned off. core.hooksPath removed.
```
