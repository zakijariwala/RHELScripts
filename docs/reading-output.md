# Reading the output

Every check script in this repo prints results the same way: one row per
check, four fields per row, one of four statuses. This page covers those
rules and each output format. What a single row means sits in the script's
own RUNBOOK (for the Oracle checklist:
[RUNBOOK.md](../scripts/oracle-rac-checklist/RUNBOOK.md)).

## The four fields

| Field | Example | Meaning |
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
| **INFO** | A fact with no limit: a name, a disabled check. | Nothing. |

Two rules hold in every script:

1. **No data is never OK.** A host the script cannot reach is CRIT. A
   number it could not read is WARN. A row that says OK always rests on a
   real measurement.
2. **The status vocabulary has four words.** You will never see Normal,
   High, Warning or CRITICAL. Those came from v1.

## The SUMMARY row

The first data row of every output:

```
SUMMARY,racnode1 / DEMODB / 02-10-2026 19:29:33,CRIT=0 WARN=5 OK=39,WARN
```

KEY holds host, database and run time. VALUE counts rows by status (INFO
not counted). STATUS is the worst status of all rows, called the overall
status.

## Exit codes

The [exit code](glossary.md#exit-code) tells a script or cron job the
overall result without reading the output. Print it right after a run:

```
echo $?
```

| Code | Meaning |
|---|---|
| 0 | every row OK or INFO |
| 1 | at least one WARN, no CRIT |
| 2 | at least one CRIT |
| 3 | another run of the same script is still going; this one did nothing |
| 64 | bad option on the command line, or invalid config file; nothing ran |

## Formats

### CSV (default)

```
bash ./checklist.sh
```

```
SECTION,DETAIL_KEY,VALUE,DESCRIPTION
SUMMARY,racnode1 / DEMODB / 02-10-2026 19:29:33,CRIT=0 WARN=5 OK=39,WARN
CONFIG,config.env,loaded from /home/oracle/scripts/oracle-rac-checklist/config.env,INFO
DB STATUS,OPEN_MODE inst 1,READ WRITE,OK
FILESYSTEM,Node 1,"5 checked, highest 83% on /u01",WARN
```

- The header keeps v1's column names. `DESCRIPTION` holds the status.
- A value containing a comma sits inside double quotes, as on the last
  line. Excel and LibreOffice open it correctly.

Full sample: [checklist.csv](../scripts/oracle-rac-checklist/sample-output/checklist.csv).

### Table

```
bash ./checklist.sh --table
```

```
SECTION           KEY                                      VALUE                     STATUS
SUMMARY           racnode1 / DEMODB / 02-10-2026 19:29:34  CRIT=0 WARN=5 OK=39       WARN
DB STATUS         OPEN_MODE inst 1                         READ WRITE                OK
```

For reading on screen. Columns line up with `column -t`. Long values make
the table wide; widen the terminal or pipe through `less -S` to scroll
sideways.

Full sample: [checklist.txt](../scripts/oracle-rac-checklist/sample-output/checklist.txt).

### HTML

```
bash ./checklist.sh --html > report.html
```

A page with the overall status in colour, a "Needs attention" list of
every WARN and CRIT row, and the full table with each status cell coloured:
red CRIT, yellow WARN, green OK. `--mail` sends this page. Outlook shows it
as written, because every style sits inside the tags.

Full sample: [checklist.html](../scripts/oracle-rac-checklist/sample-output/checklist.html).
Download it and open it in a browser.

## History log

Unless you pass `--no-history`, each run appends its rows to a daily file,
`LOG_DIR/checklist_YYYYMMDD.log` (default folder
`/home/oracle/checklist_history`). One line per row, `key=value` pairs:

```
ts="02-10-2026 19:39:05" host=racnode1 db=DEMODB section="TEMP USAGE" key="TEMP" value="Used=78.40% of 64G" status=WARN
ts="02-10-2026 19:39:05" host=racnode1 db=DEMODB section="SUMMARY" key="overall" value="CRIT=0 WARN=5 OK=39" status=WARN
```

| Field | Meaning |
|---|---|
| `ts` | run time, `DD-MM-YYYY HH:MM:SS` |
| `host` | short host name of the server that ran the script |
| `db` | database name |
| `section`, `key`, `value`, `status` | the row |

The SUMMARY row comes last in each run. Double quotes inside a value turn
into single quotes. Files older than `LOG_RETENTION_DAYS` (30) are deleted
at the end of each run.

Read the trend of one row across a day, as oracle on node 1:

```
grep 'key="TEMP"' /home/oracle/checklist_history/checklist_$(date +%Y%m%d).log
```

The format suits Splunk and similar tools: they read `key=value` pairs
without extra setup.
