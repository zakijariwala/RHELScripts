# How checklist.sh works

A walk through the code for someone who knows basic Linux and is learning
bash. Read it with the script open next to it:

```
vi checklist.sh
```

In vi, `:set nu` shows line numbers, and `/check_db` jumps to the text
`check_db`. This page names functions, not line numbers, because line
numbers change with every edit.

## 1. The shape of the file

The file runs top to bottom, but most of it only **defines** things. Real
work starts at the `MAIN` block at the bottom.

| Block | What it holds |
|---|---|
| Header comment | usage, exit codes, changelog |
| First 3 lines of code | make sure bash runs it |
| `CONFIG` | built-in defaults: hosts, paths, thresholds |
| `CONFIG FILE` | `valid_value` and `load_config`, which read `config.env` |
| `HELPERS` | small functions every check uses: `add`, `rank`, `worst`, `rate`, `trim`, `file_age_min`, `to_mb` |
| `1. DATABASE` to `5. STATIC INPUT FILES` | one function per check: `check_db`, `check_crs`, `check_os`, `check_gg`, `check_sftp`, `check_activesessions`, `check_appservers` |
| `OUTPUT` | turn results into CSV, a table or HTML; send mail; write history |
| `MAIN` | read options, read config, take the lock, call every check, print, exit |

Every check follows one pattern: **measure, rate, store**. Nothing prints
until all checks finish. Storing first lets the script count statuses for
the SUMMARY row and print the same results in three formats.

## 2. Making sure bash runs it

```
if [ -z "$BASH_VERSION" ]; then exec /bin/bash "$0" "$@"; fi
set +o posix 2>/dev/null
set -o pipefail
```

- The team ran v1 as `sh checklist.sh`. On RHEL `sh` is bash in POSIX
  mode, which turns off features this script needs. If `$BASH_VERSION` is
  empty, the shell is not bash, so `exec` replaces it with real bash,
  passing the same file (`$0`) and arguments (`"$@"`).
- `set +o posix` switches POSIX mode off if bash started in it.
- `set -o pipefail` makes a pipeline such as `a | b` fail when `a` fails,
  not only when `b` fails.
- There is no `set -e`. With `set -e`, the first failing command stops
  the script. Here a failed check must become a CRIT row while the other
  checks carry on.

## 3. Defaults and config.env

The `CONFIG` block sets plain variables:

```
CPU_WARN=60;     CPU_CRIT=85
```

The `;` lets two assignments share a line. `SSH_OPTS` is an **array**:

```
SSH_OPTS=(-q -o BatchMode=yes -o ConnectTimeout=10)
```

Later, `"${SSH_OPTS[@]}"` expands to those five words, each a separate
argument to ssh. A plain string would need unquoted expansion, which
breaks on spaces.

### Reading config.env without running it

The common way to load settings is `source config.env`, which **runs**
the file as bash. Anyone who can edit it can then run any command as
oracle. Worse, values such as `APP_USER` go into SQL sent as SYSDBA, so a
value like `X'; DELETE FROM t; --` would add a write statement. So the
script reads the file as text instead:

```
declare -A CONFIG_TYPE=(
    [NODE2_HOST]=host [NODE2_PORT]=int ...
    [APP_USER]=dbname ...
)
```

`declare -A` makes an **associative array**: keys are names, not numbers.
`${CONFIG_TYPE[APP_USER]}` gives `dbname`. A key missing from this list is
an unknown key.

`load_config` reads the file one line at a time:

```
while IFS= read -r line || [ -n "$line" ]; do
```

- `IFS=` keeps leading spaces; `-r` keeps backslashes as they are.
- `|| [ -n "$line" ]` handles a last line with no newline at the end.

Each line must match one of three patterns, tested with `[[ ... =~ ... ]]`:
`KEY="value"`, `KEY='value'` or `KEY=value`, each with an optional
`# comment`. The parts in parentheses in the pattern land in
`BASH_REMATCH[1]` (the key) and `BASH_REMATCH[2]` (the value). Anything
else, `$(...)` included, matches none of them and stops the script.

`valid_value` checks the value against its type with one more pattern per
type. A `dbname` may hold only letters, digits, `_`, `$` and `#`: no quote,
no space, no `;`, so nothing can break out of the SQL string.

Then:

```
printf -v "$key" '%s' "$val"
```

`printf -v NAME` stores the text in the variable whose name is in `$key`.
This sets `APP_USER` when `$key` holds `APP_USER`, with no `eval`.

## 4. Storing and rating results

```
R_SECTION=(); R_KEY=(); R_VALUE=(); R_STATUS=()
add() { R_SECTION+=("$1"); R_KEY+=("$2"); R_VALUE+=("$3"); R_STATUS+=("$4"); }
```

Four arrays grow side by side. Row 5 of the output is `R_SECTION[5]`,
`R_KEY[5]`, `R_VALUE[5]`, `R_STATUS[5]`. `add` appends one row.

`rate` turns a number into a status:

```
rate() {
    awk -v v="$1" -v w="$2" -v c="$3" 'BEGIN {
        if (v == "") { print "WARN"; exit }
        if (v+0 > c+0) print "CRIT"; else if (v+0 > w+0) print "WARN"; else print "OK" }'
}
```

Bash compares whole numbers only; `awk` handles `76.24`. The `BEGIN`
block runs without reading any input. An empty value means the script
could not measure it, and that gives WARN: never OK for data it did not
get.

`rank` maps CRIT/WARN/OK to 2/1/0, and `worst` returns the highest of
several statuses. The script's exit code is the `rank` of the worst row.

## 5. The database check: check_db

### Building the SQL

```
if [ "$CHECK_RMAN" = 1 ]; then
    sql_rman=$(cat <<EOSQL
SELECT 'RMAN BACKUP|...' ... > $DB_BACKUP_MAX_HRS ... FROM v\$rman_backup_job_details ...
EOSQL
)
fi
```

`<<EOSQL ... EOSQL` is a [heredoc](../../docs/glossary.md#heredoc): the
lines between become the input of `cat`, and `$( )` captures that into
`sql_rman`. The delimiter is unquoted, so bash replaces `$DB_BACKUP_MAX_HRS`
with its value. Oracle view names also contain `$` (`v$database`), so the
script writes `v\$` to keep bash's hands off them.

Optional parts (`sql_rman`, `sql_alert`, `sql_dg`) stay empty when their
toggle is 0, so their queries never reach the database.

### Running sqlplus

```
out=$(timeout "$SQL_TIMEOUT" sqlplus -s -L / as sysdba <<EOF 2>&1
SET PAGESIZE 0
...
SELECT 'DB STATUS|OPEN_MODE inst '||inst_id||'|'||open_mode||'|'||CASE ... END FROM gv\$database ...;
...
$sql_rman
$sql_alert
EXIT;
EOF
)
rc=$?
```

- `timeout N` kills sqlplus after N seconds and returns exit code 124.
- `-s` hides the banner, `-L` tries the login once instead of prompting.
- `2>&1` sends errors into `out` too, so the script sees them.
- Each `SELECT` glues its answer into one line, `SECTION|KEY|VALUE|STATUS`,
  with Oracle's `||` text join. The SQL decides the status with `CASE`.
- `SET PAGESIZE 0`, `HEADING OFF`, `FEEDBACK OFF` strip everything except
  those lines.

### Reading the answer

```
local re='^([^|]+)\|([^|]*)\|([^|]*)\|(OK|WARN|CRIT|INFO)$'
while IFS= read -r line; do
    if [[ "$line" =~ $re ]]; then
        add "${BASH_REMATCH[1]}" ... "${BASH_REMATCH[4]}"
    elif [[ "$line" =~ (ORA-|SP2-|ERROR) ]]; then
        add "DB QUERY" "sqlplus error" "$(trim "$line")" "CRIT"
    fi
done <<< "$out"
```

`<<< "$out"` feeds the variable to the loop as input (a here-string).
A line with four `|`-separated fields becomes a row. An Oracle error line
becomes a CRIT row. v1 threw error lines away, which hid a down database.
The `META` row carries the database name for the SUMMARY row and is not
stored.

## 6. Clusterware: check_crs

`crsctl stat res -t` prints a resource name on one line, then one indented
line per node with TARGET and STATE:

```
ora.LISTENER.lsnr
               ONLINE  ONLINE       racnode1                 STABLE
               ONLINE  OFFLINE      racnode2                 STABLE
```

The `awk` program remembers the last unindented line as the resource name
(`/^[^ \t]/ { res=$1; next }`). On an indented line it takes the first
state word as TARGET and the second as STATE, and prints the resource when
TARGET is ONLINE and STATE is not. The bash loop after it turns each
printed line into a row: OFFLINE = CRIT, anything else = WARN.

## 7. Both servers: os_collect, process_os, check_os

`os_collect` gathers CPU, memory, swap, load and filesystems and prints
them as `OS|cpu|mem|swap|load|cores` and `FS|mount|pct` lines.

For node 1 the script calls it directly. For node 2:

```
out=$(timeout "$SSH_TIMEOUT" ssh "${SSH_OPTS[@]}" -p "$NODE2_PORT" "$NODE2_HOST" "bash -s" \
      <<< "$(declare -f os_collect); os_collect" 2>/dev/null)
```

`declare -f os_collect` prints the function's own source code. That text,
plus a call to it, goes over ssh into `bash -s` on node 2, which runs what
arrives on its input. Node 2 needs no copy of the script.

`process_os` reads the lines back with `IFS='|' read -r _ cpu mem swap load cores`:
setting `IFS` to `|` for that one command splits the line at `|`. `_` takes
the `OS` label and is ignored. No `OS|` line, or a failed ssh, gives CRIT
`NO DATA`. v1 filled in zeros, so a dead node looked idle.

## 8. GoldenGate: check_gg

`gg2.sh` prints lines such as:

```
"X_EXTRACT1","RUNNING","2026-09-20 15:37","00:00:04","2026-10-02 23:51:09","18.25 (...)"
```

- `${line//\"/}` deletes every `"` (pattern `\"`, replacement empty).
- `IFS=',' read -r name status started lag ckpt scn` splits at commas.
- `awk -F: '{ print $1*3600 + $2*60 + $3 }'` turns `00:00:04` into seconds.
- `date -d "$ckpt" +%s` turns the checkpoint time into seconds since 1970;
  subtracting it from `date +%s` (now) gives its age.
- `worst` combines the three ratings: status, lag, checkpoint age.

## 9. Files from other jobs: fresh_or_flag

```
fresh_or_flag() {
    local section="$1" file="$2" age
    if ! age=$(file_age_min "$file"); then
        add "$section" "$file" "file missing" "CRIT"; return 1
    fi
    ...
}
```

`file_age_min` uses `stat -c %Y` (last modification, in seconds since 1970) and
returns failure when the file does not exist. A missing or old file adds a
CRIT row and returns 1. The caller writes `fresh_or_flag ... || return`:
"if the file is not fresh, stop this check here".

## 10. Output

- `summarise` counts statuses and sets `OVERALL`.
- `csv` wraps a field in double quotes when it contains a comma or a quote,
  and doubles quotes inside it. That is the CSV rule Excel follows.
- `print_table` writes tab-separated lines and pipes them through
  `column -t -s $'\t'`, which pads columns to line up.
- `build_html` writes an HTML table with inline styles, because Outlook
  ignores style sheets. `html_escape` turns `<`, `>` and `&` into entities
  so a value cannot break the page.
- `send_mail` writes the mail headers and the HTML into `sendmail -t`,
  which reads the recipients from the `To:` and `Cc:` headers.
- `write_history` appends one `key="value"` line per row to a daily file,
  then `find "$LOG_DIR" -name 'checklist_*.log' -mtime +N -delete` removes
  files older than N days. The `-name` pattern limits it to the script's
  own files.

## 11. MAIN

1. **Options.** A `for arg in "$@"` loop with `case` sets `MODE`,
   `SEND_MAIL` and `NO_HISTORY`. An unknown option exits 64.
2. **Config.** `load_config`, then the values derived from it
   (`GG_SCRIPT`, `ACTIVESESSION_SCRIPT`, `GRID_HOME`). `--no-history` is
   applied after, so it beats `config.env`.
3. **Lock.**

   ```
   exec 9>"/tmp/checklist_$(id -un).lock"
   if command -v flock >/dev/null && ! flock -n 9; then
       echo "checklist.sh is already running" >&2; exit 3
   fi
   ```

   `exec 9>file` opens the file as file descriptor 9 for the rest of the
   script. `flock -n 9` takes an exclusive lock on it or fails at once if
   another run holds it. The lock goes away when the script exits, even if
   it crashes, because the operating system closes descriptor 9.
4. **Checks.** The CONFIG row, then each `check_` function. `CHECK_GG`
   decides between `check_gg` and an INFO row.
5. **Print.** `summarise`, then CSV, table or HTML by `MODE`.
6. **History and mail**, if switched on.
7. **Exit.** `exit "$(rank "$OVERALL")"`: 0, 1 or 2.

## Bash features used, in one table

| Feature | Example | Meaning |
|---|---|---|
| Array | `R_STATUS+=("OK")` | append to a list |
| Associative array | `declare -A T=([a]=1)` | list indexed by name |
| Parameter default | `${GG_SCRIPT:-$SCRIPTS_DIR/gg2.sh}` | the variable, or the text after `:-` if empty |
| Replace all | `${line//\"/}` | delete every `"` |
| Upper / lower case | `${s1^^}`, `${status,,}` | convert case |
| Regex test | `[[ $x =~ ^[0-9]+$ ]]` | true if `$x` matches |
| Here-string | `cmd <<< "$var"` | feed a variable to a command's input |
| Heredoc | `cmd <<EOF ... EOF` | feed lines of text to a command |
| Command substitution | `out=$(cmd)` | capture a command's output |
| Exit status | `rc=$?` | exit code of the last command |
| Named output variable | `printf -v name '%s' "$val"` | set a variable by its name |
| File descriptor | `exec 9>file` | keep a file open as number 9 |
