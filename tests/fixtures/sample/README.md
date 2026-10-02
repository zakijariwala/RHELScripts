# Fixture: sample

Canned output for the stub commands, used by `tests/run-stub.sh` and
`tests/make-samples.sh`. A two-node cluster, mostly healthy, with a few
findings so the samples show more than OK:

- TEMP at 78% (WARN, limit 75), tablespace APP_DATA at 86% (WARN, limit 85)
- racnode1 memory at 76% (WARN, limit 75), racnode1 /u01 at 83% (WARN)
- racnode2 alert log: 2 ORA- errors (WARN)

| File | Fake output of |
|---|---|
| `status.out`, `sessions.out`, `load.out` | db-check SQL |
| `temp.out`, `space.out` | space-check SQL |
| `dest.out`, `sync.out` | dr-check SQL |
| `fra.out`, `rman.out` | backup-check SQL |
| `alert.node1`, `alert.node2` | node-check alert log SQL, per node |
| `test-*.out` | the `--check-config` TEST queries |
| `sar.nodeN`, `free.nodeN`, `df.nodeN` | OS commands, per node |
| `crsctl.out` | `crsctl stat res -t` |
| `gg2.out` | `gg2.sh`; `@CKPT@` becomes a time one minute ago |
| `activesession.out` | `activesession.sh` |
| `sftp_output`, `server_checklist` | the two input files |
| `ps.nodeN` | process command lines per node (ps, pgrep, proc-check) |
| `uname.out`, `rpm.out`, `chronyc.out`, `journalctl.out` | host-check commands |
| `systemctl-failed.out`, `systemctl-active.out`, `id-groups.out` | host-check systemd and group lookups |
| `df-i.node1` | `df -i` for disk-check |
| `proc/`, `sys/` | fake `/proc` and `/sys`: mounts, meminfo, bonding, block devices, transparent hugepages |
| `config/NAME.env` | the config.env each script gets; `@GRID@`, `@WORK@`, `@STUBS@` are filled in |
