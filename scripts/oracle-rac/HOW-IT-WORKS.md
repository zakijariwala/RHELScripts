# How the Oracle RAC scripts work

A walk through the code for someone who knows basic Linux and is learning
bash. The scripts hold almost no comments, to keep typing short; the
explanation lives here. Read it with a script open next to it, for example
[db-check.sh](db-check/db-check.sh).

## 1. Sections

Every script is split into numbered sections. Each starts with a marker
line:

```
#== S01 settings
```

The markers serve two purposes. You type and check one section at a time
(each has its own hash), and every script shares the same layout:

| Section | In | Holds |
|---|---|---|
| S01 settings | every script | `VERSION`, `NAME`, the help text, the list of config keys, the defaults |
| S02 helpers | every script, identical | `die`, `add`, `rank`, `rate` |
| S03 output | every script, identical | `report`: the table or CSV, the summary, the exit code |
| S04 config | every script, identical | `cfg` (reads config.env), `detect`, `need` |
| S05 options | every script, identical | the command-line options and `show_cfg` |
| S06 sql | the four database scripts, identical | `find_sid` and `sql` |
| S06/S07 onwards | each script | its own checks, then `main` last |

CI compares every shared section with the master copy in
[tools/shared/](../../tools/shared/), so the shared sections carry the same
hash in every script.

## 2. Settings (S01)

```
VERSION=1.0.0
NAME="db-check"
KEYS="ORACLE_SID APP_USER GRID_HOME EXPECTED_INSTANCES RESTART_WARN_DAYS"
KEYS="$KEYS ACTIVE_MAX INACTIVE_MAX LIMIT_WARN LIMIT_CRIT BLOCK_SECS"
ORACLE_SID='' APP_USER='' GRID_HOME='' EXPECTED_INSTANCES='' RESTART_WARN_DAYS=1
```

- `KEYS` lists every key config.env may set. The second and third lines
  add to it (`"$KEYS ..."`) so no line passes 80 characters.
- `A=1 B=2` on one line sets both variables. `''` is an empty value: the
  script detects it, or you set it in config.env.

## 3. Results and ratings (S02)

```
R=()
add() { R+=("$1|$2|${3//|//}|$4"); }
```

`R` is an array of rows. `add SECTION KEY VALUE STATUS` appends one row,
the four fields joined with `|`. `${3//|//}` replaces any `|` inside the
value with `/`, so a value can never shift the columns.

```
rate() {
  awk -v v="$1" -v w="$2" -v c="$3" 'BEGIN {
    if (v !~ /^[0-9]+([.][0-9]+)?$/) print "WARN"
    else if (v + 0 > c + 0) print "CRIT"
    else if (v + 0 > w + 0) print "WARN"
    else print "OK" }'
}
```

`rate VALUE WARN CRIT` returns OK, WARN or CRIT. Bash compares whole
numbers only; `awk` handles `76.24`. A value that is not a number (empty,
`?`, `N/A`) means the script did not get a measurement, and gives WARN,
never OK.

`die CODE MESSAGE` prints the message and exits with the code. `rank`
turns CRIT/WARN/OK into 2/1/0.

## 4. Output (S03)

`report` counts the rows by status with `grep -c '|CRIT$'` and friends,
adds the SUMMARY row, and prints:

```
printf '%s\n' "SECTION|KEY|VALUE|STATUS" "${R[@]}" | if [ "$MODE" = csv ]
then tr -d '"' | sed 's/|/","/g; s/.*/"&"/'
else column -t -s '|'
fi
```

- `printf '%s\n' a b c` prints each argument on its own line.
- A pipe can feed an `if`: the `if` picks which command reads the rows.
- `column -t -s '|'` lines the columns up.
- For CSV, `tr -d '"'` removes double quotes, then `sed` turns each `|`
  into `","` and wraps the line in `"`. Every field ends up quoted, so a
  comma inside a value is safe.

Then `exit "$(rank "$all")"`: the exit code is 0, 1 or 2.

## 5. Config (S04)

```
while IFS='=' read -r k v; do
  ...
done < <(tr -d '\r' < "$f"; echo)
```

- `IFS='=' read -r k v` splits each line at the first `=`: the key in `k`,
  the rest in `v`.
- `tr -d '\r'` removes Windows line endings; the extra `echo` makes sure
  the last line counts even without a newline at its end.
- `[[ " $KEYS " == *" $k "* ]]` checks the key is in the list.
- `[[ $v =~ ^[A-Za-z0-9_./:,@+-]*$ ]]` allows letters, digits and
  `_ . / : , @ + -` only. No space, quote, `;`, `$` or `&`, so a value can
  never break out of the SQL it lands in.
- Keys ending in WARN, CRIT, MAX, SECS, MIN, HRS, DAYS, TIMEOUT, MB, PORT,
  or starting with CHECK_, must be numbers.
- `printf -v "$k" '%s' "$v"` stores the value in the variable named by
  `$k`, with no `eval`. `SRC[$k]=config` remembers where it came from.

`detect KEY VALUE` sets a key the script found on the server, unless
config.env already set it. If both exist and differ, `SRC` records
`MISMATCH, detected ...`, which `--check-config` shows as WARN.
`need KEY` stops with exit code 65 when a key is still empty.

## 6. Options (S05)

A `case` on `$1` sets `MODE` to `run`, `csv` or `check`, or prints the
version or help and exits. An unknown option exits 64. `show_cfg` adds one
CONFIG row per key, with its value and `[detected]`, `[config]` or
`[default]`.

## 7. Talking to the database (S06)

`find_sid` reads the process list:

```
s=$(ps -eo args= | awk '/^ora_pmon_/ { sub(/^ora_pmon_/, ""); print }')
```

Every database instance runs a process named `ora_pmon_<SID>`. If exactly
one runs on this node, its SID is the one to use.

`sql` runs one batch of queries:

```
out=$({ printf 'DEFINE %s\n' "$@"; cat; } |
  timeout "$SQL_TIMEOUT" sqlplus -s -L / as sysdba 2>&1)
```

- The caller passes thresholds as `name=value` words. `printf` turns each
  into a SQL*Plus `DEFINE name=value` line.
- `cat` then copies the caller's SQL (its heredoc) after them.
- In the SQL, `&name` is a **substitution variable**: SQL*Plus replaces it
  with the DEFINEd value before running the statement.
- `timeout` kills sqlplus after `SQL_TIMEOUT` seconds (exit code 124).

A caller looks like this:

```
sql "restart=$RESTART_WARN_DAYS" "instances=$EXPECTED_INSTANCES" <<'SQL'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 VERIFY OFF TAB OFF LINESIZE 1000
SELECT 'INSTANCE STATUS|Instances OPEN|' || COUNT(*) || ' of &instances|'
  || CASE WHEN COUNT(*) < &instances THEN 'CRIT' ELSE 'OK' END
  FROM gv$instance WHERE status = 'OPEN';
EXIT
SQL
```

The quotes in `<<'SQL'` stop bash from touching anything inside: `$` in
`gv$instance` needs no escape, because bash never expands it. Each SELECT
builds one output line `SECTION|KEY|VALUE|STATUS` with Oracle's `||` join,
and decides the status with `CASE`.

`sql` reads every line sqlplus printed:

| Line | Becomes |
|---|---|
| four fields ending in OK, WARN, CRIT or INFO | a row |
| contains `ORA-` or `SP2-` | a CRIT `DB QUERY error` row |
| starts with `ERROR`, `Process`, `Session` | nothing (noise around an ORA- line) |
| anything else not blank | a WARN `DB QUERY unparsed line` row |

Then exit code 124 adds `timed out`, 126 or more adds `cannot run
sqlplus`, and a call that produced no row at all adds `no output`.

## 8. node-check: one function, every node

`collect` gathers everything about the node it runs on and prints it as
lines: `CPU|26.63`, `MEM|76.24`, `SWAP|0.73`, `LOAD|0.41`,
`FS|/u01|83`, `ALERT|0|`. On the local node the script calls it directly.
For every other node:

```
out=$(timeout "$SSH_TIMEOUT" ssh "${ssh_opts[@]}" "$node" bash -s \
  <<< "$(declare -f collect); collect ${args[*]}" 2>/dev/null)
```

`declare -f collect` prints the function's own source code. That text,
plus a call to it, goes over ssh into `bash -s` on the other node, which
runs what arrives on its input. The other node needs no copy of the
script, and nothing is written there.

For the alert log, `collect` finds the instance from `ora_pmon_` and that
process's `ORACLE_HOME` from `/proc/PID/environ` (readable by oracle,
which owns the process), so sqlplus works even in the bare environment an
ssh command gets.

`node_os` reads the lines back with `IFS='|' read -r tag a b` and a
`case` on the tag. `flag NAME VALUE WARN CRIT` rates one metric, keeps the
worst status in `st` and the names of flagged metrics in `why`.

## 9. crs-check: reading crsctl

`crsctl stat res -t` prints a resource name, then one indented line per
node with TARGET and STATE:

```
ora.LISTENER.lsnr
               ONLINE  ONLINE       racnode1                 STABLE
               ONLINE  OFFLINE      racnode2                 STABLE
```

The `awk` program in `not_online` remembers the last unindented line as
the resource name, takes the first state word on an indented line as
TARGET and the second as STATE, and prints the resource when TARGET is
ONLINE and STATE is not.

## 10. gg-check and inputs-check: other people's output

Both parse comma-separated lines another script or job produced.

- `${1//\"/}` deletes every `"`.
- `IFS=',' read -r name status started lag ckpt scn` splits at commas.
- `[[ $lag =~ ^([0-9]+):([0-9][0-9]):([0-9][0-9])$ ]]` accepts only
  `HH:MM:SS`; `BASH_REMATCH[1]` to `[3]` hold the parts, and `10#` makes
  bash read `08` as decimal eight.
- `date -d "$ckpt" +%s` turns a time into seconds since 1970.
- `fresh` (inputs-check) compares `stat -c %Y FILE` (last change, in
  seconds) with now, and adds a CRIT row when the file is missing or
  older than `STALE_MIN`.

## 11. main

Every script ends the same way:

1. `cfg` reads config.env.
2. `detect` fills what the server can tell (SID, Grid home, nodes).
3. `need` stops with exit code 65 if a required value is still empty.
4. With `--check-config`: `show_cfg`, the connection TEST rows, `report`.
5. Otherwise: the checks, then `report`.

## Bash features used

| Feature | Example | Meaning |
|---|---|---|
| Array | `R+=("a|b|c|OK")` | append to a list |
| Associative array | `declare -A SRC` | list indexed by name |
| Replace all | `${3//|//}` | every `|` becomes `/` |
| Default | `${!k:-(empty)}` | the variable named by `k`, or `(empty)` |
| Indirect | `${!1}` | the variable whose name is in `$1` |
| Regex test | `[[ $v =~ ^[0-9]+$ ]]` | true if `$v` matches |
| Here-string | `cmd <<< "$var"` | feed a variable to a command's input |
| Quoted heredoc | `cmd <<'SQL' ... SQL` | feed text, with no `$` expansion |
| Process substitution | `done < <(cmd)` | read a loop's input from a command |
| Command substitution | `out=$(cmd)` | capture a command's output |
| Named output | `printf -v name '%s' "$val"` | set a variable by its name |
