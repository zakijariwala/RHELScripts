# Reading the output

Every script in this repo prints results the same way: one row per check,
four columns, one of four statuses, then a summary row. This page covers
those rules. What a single row means is in the
[RUNBOOK](../scripts/oracle-rac/RUNBOOK.md).

## The four columns

| Column | Example | Meaning |
|---|---|---|
| SECTION | `TEMP USAGE` | the area checked |
| KEY | `TEMP` | which item in that area |
| VALUE | `Used=78.40% of 64G` | what the script measured |
| STATUS | `WARN` | the verdict |

## The four statuses

| Status | Meaning | You |
|---|---|---|
| **CRIT** | Broken now, or about to break. Also: the script could not reach a host or a command failed. | Act now. Follow the RUNBOOK entry. |
| **WARN** | Over a warning limit. Also: a value the script could not measure. | Look today. |
| **OK** | Measured, and inside its limits. | Nothing. |
| **INFO** | A fact with no limit: a name, a setting, a check switched off. | Nothing. |

Two rules hold in every script:

1. **No data is never OK.** A host the script cannot reach is CRIT. A
   number it could not read is WARN. A row that says OK always rests on a
   real measurement.
2. **Four words only.** You will never see Normal, High, Warning or
   CRITICAL. Those came from the first version.

## The SUMMARY row

The last row:

```
SUMMARY  racnode1 db-check 1.0.0 2026-10-02 20:03:49  CRIT=0 WARN=0 OK=16  OK
```

KEY holds host, script, version and run time. VALUE counts rows by
status; INFO is not counted. STATUS is the worst status of all rows, called
the overall status.

## Exit codes

The [exit code](glossary.md#exit-code) gives the overall result as a
number. Print it right after a run:

```
echo $?
```

| Code | Meaning |
|---|---|
| 0 | every row OK or INFO |
| 1 | at least one WARN, no CRIT |
| 2 | at least one CRIT |
| 64 | bad option on the command line; nothing ran |
| 65 | config.env holds a bad key or value, or a required value is missing; nothing ran |

`--check-config` uses the same codes: 0 when every TEST row passed, 2 when
one failed.

## Formats

### Table (default)

```
bash db-check.sh
```

```
SECTION          KEY                                          VALUE                STATUS
DATABASE         name                                         DEMODB               INFO
DB STATUS        OPEN_MODE inst 1                             READ WRITE           OK
...
SUMMARY          racnode1 db-check 1.0.0 2026-10-02 20:03:49  CRIT=0 WARN=0 OK=16  OK
```

Columns line up for the screen. Long values make the table wide; widen
the terminal, or pipe through `less -S` and scroll sideways with the arrow
keys.

### CSV

```
bash db-check.sh --csv
```

```
"SECTION","KEY","VALUE","STATUS"
"DATABASE","name","DEMODB","INFO"
"SESSION LIMIT","Inst 1 processes","612 of 1500","OK"
"SUMMARY","racnode1 db-check 1.0.0 2026-10-02 20:03:49","CRIT=0 WARN=0 OK=16","OK"
```

Every field sits in double quotes, so a comma inside a value is safe in
Excel or LibreOffice. Double quotes inside a value are dropped.

### --check-config

The same table, with CONFIG rows (one per setting, and where its value
came from) and TEST rows (connections it tried). See
[RUNBOOK, CONFIG and TEST](../scripts/oracle-rac/RUNBOOK.md#config-and-test).

## Messages outside the table

A message without a table means the script stopped before checking
anything:

| Message | Exit code | Do this |
|---|---|---|
| `db-check: unknown option: --x (try --help)` | 64 | use one of `--csv`, `--check-config`, `--version`, `--help` |
| `db-check: config.env: bad key FOO` | 65 | the key is not one this script knows; compare with its README |
| `db-check: config.env: bad value APP_USER` | 65 | the value holds a space, quote or other character not allowed |
| `db-check: config.env: ACTIVE_MAX not a number` | 65 | type digits only |
| `db-check: APP_USER missing: docs/config-from-inventory.md` | 65 | add the key; the page says where the value comes from |
