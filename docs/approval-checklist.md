# Approval checklist

One form per script, per host, per run. The fresher fills sections A to D,
the senior fills E. Print this page, or copy its fields into the team's
internal system.

**Never commit a filled form to this repo.** It holds real host names.

---

## A. Script

| Field | Value |
|---|---|
| Script name | ______________________ |
| Version (`bash NAME.sh --version`) | ______________________ |
| README checksum table, version shown | ______________________ |

## B. Typed copy verified

| Check | Expected | Result |
|---|---|---|
| Every section hash matches the README | all match | Y / N |
| Whole-file hash | `____________` (12 characters, from the README) | `____________` Y / N |
| `bash -n NAME.sh && echo SYNTAX OK` | `SYNTAX OK` | Y / N |
| Typed by | name | ______________________ |
| Hashes checked by (a second person, if your team requires one) | name | ______________________ |

## C. Where and how

| Field | Value |
|---|---|
| Host | ______________________ |
| Environment | production / pre-production |
| User | oracle |
| Folder | `/home/oracle/scripts/oracle-rac/______________` |
| Change request, if your team requires one ([change-requests.md](change-requests.md)) | ______________________ |

## D. Configuration

Write every line of `config.env` (`cat config.env`):

```
_____________________________________________
_____________________________________________
_____________________________________________
_____________________________________________
```

| Check | Result |
|---|---|
| `bash NAME.sh --check-config` output attached | Y / N |
| Every TEST row is OK | Y / N |
| No CONFIG row says MISMATCH, or each mismatch is explained here: ______________ | Y / N |
| Thresholds changed from the README defaults (list them, with who asked): ______________ | none / listed |

**What the script reads and writes** (copy from the README's Safety
section):

Reads: ______________________________________________________________

Writes: nothing (prints to the screen only)

| Field | Value |
|---|---|
| Expected run time (README) | ______ seconds |
| Planned run date and time | ______________________ |

## E. Decision (senior)

| Field | Value |
|---|---|
| Decision | approved / approved with changes / rejected |
| Changes required before the run | ______________________ |
| Approver | ______________________ |
| Date | ______________________ |
| Signature | ______________________ |

---

## After the run

| Field | Value |
|---|---|
| Exit code (`echo $?`) | 0 / 1 / 2 / other: ____ |
| SUMMARY line | ______________________ |
| WARN and CRIT rows, each with the RUNBOOK action taken | ______________________ |
