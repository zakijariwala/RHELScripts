# Fixture: sample

Inputs for the stub run that builds `scripts/oracle-rac-checklist/sample-output/`.
A mostly healthy two-node cluster with four findings, so the sample shows
every status:

- TEMP at 78% (WARN, limit 75)
- tablespace APP_DATA at 86% (WARN, limit 85)
- node 1 memory at 76% (WARN, limit 75)
- node 1 /u01 at 83% (WARN, limit 80)

`@CKPT@` in `gg2.out` is replaced with a time one minute before the run,
so the GoldenGate checkpoint always looks fresh.
