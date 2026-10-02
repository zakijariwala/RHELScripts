# RUNBOOK: Linux host scripts

One entry per row `host-check.sh`, `disk-check.sh` and `hw-check.sh` can
print. Find the row by its SECTION (first column), then its KEY (second
column). The CONFIG, TEST, SUMMARY rows and the exit codes work as in the
[Oracle RAC RUNBOOK](../oracle-rac/RUNBOOK.md#config-and-test).

## How to act on a row

- **CRIT**: act now. Phone the on-call Linux admin; do not wait for mail.
- **WARN**: look today. Tell the Linux team if you do not know why.
- **OK**, **INFO**: nothing to do.

Every command below reads only. Run it as the same user as the script, on
the same server. Fixing the cause (reboots, package updates, mounts,
multipath) belongs to the Linux team under their procedures.

Contents: [KERNEL](#kernel) · [TIME SYNC](#time-sync) · [PROCESS](#process) ·
[SYSTEMD](#systemd) · [KERNEL LOG](#kernel-log) · [FILESYSTEM](#filesystem) ·
[INODES](#inodes) · [READ-ONLY FS](#read-only-fs) · [SCSI PATH](#scsi-path) ·
[MULTIPATH](#multipath) · [BONDING](#bonding) · [HUGEPAGES](#hugepages)

---

## KERNEL

`host-check`.

| KEY | VALUE | STATUS |
|---|---|---|
| `running` | `4.18.0-553.el8_10.x86_64, the newest installed` | OK |
| | `..., newest installed ...: reboot pending` | WARN |
| | `..., installed kernels not readable` | WARN |
| `needs-restarting` | `no reboot needed` | OK |
| | `reboot needed, core packages updated` | WARN |
| | `not installed (dnf-utils)` | WARN |

**Meaning.** A newer kernel or core library (glibc, systemd) is installed
but not in use until the server reboots. Security fixes in it do not
protect the server yet.

**How measured.** `uname -r` against the newest `kernel-core` package
(`rpm -q --last kernel-core`); `needs-restarting -r`.

**WARN (reboot pending).** Tell the Linux team, who schedule the reboot
under a change request. Do not reboot yourself.

**WARN (not installed).** Ask the Linux team to install `dnf-utils`
(RHEL 8) or `yum-utils` (RHEL 9), or ignore the row with their agreement.

## TIME SYNC

`host-check`.

| KEY | VALUE | STATUS |
|---|---|---|
| `chrony` | `offset 0.04 ms, source ...` | OK |
| | offset above `TIME_WARN_MS` (100) | WARN |
| | offset above `TIME_CRIT_MS` (1000) | CRIT |
| | `not synchronised, leap status ...` | CRIT |
| | `chronyc failed, rc=N: ...` | CRIT |

**Meaning.** How far this server's clock is from its time source. Oracle
RAC evicts nodes whose clocks drift apart; logs from different servers stop
lining up.

**How measured.** `chronyc tracking`: Leap status and System time.

**CRIT or WARN.** Show the time sources and their state:

```
chronyc sources -v
```

Send the output to the Linux team. `^*` marks the source in use; no `^*`
means no usable source.

**CRIT (chronyc failed, rc=127).** chrony is not installed; the server
may run ntpd instead. Tell the Linux team.

## PROCESS

`host-check`, one row per name in `PROCS`.

| KEY | VALUE | STATUS |
|---|---|---|
| process name, for example `crond` | `1 running` | OK |
| | `not running` | CRIT |

**Meaning.** Each listed process must run: the default list is `crond`,
`chronyd`, `sshd`; config.env adds the site's monitoring and security
agents ([config-from-inventory.md](../../docs/config-from-inventory.md)).

**How measured.** `pgrep -xc NAME`: the exact process name as `ps -eo comm`
shows it (15 characters at most).

**CRIT.** Check whether it stopped or never existed:

```
systemctl status NAME
```

Replace `NAME` with the service name (often the process name). Send the
output to the team that owns the agent, or the Linux team for system
services.

## SYSTEMD

`host-check`.

| KEY | VALUE | STATUS |
|---|---|---|
| `failed units` | `none` | OK |
| | unit names, for example `mdmonitor.service` | WARN |
| | `systemctl failed, rc=N` | CRIT |
| `kdump` | `active` | OK |
| | `inactive, no crash dump on a panic` | WARN |

Absent `kdump` row when `CHECK_KDUMP=0`.

**WARN (failed units).** For each unit named:

```
systemctl status UNIT --no-pager
```

Send the output to the Linux team.

**WARN (kdump).** If the server crashes, no dump is saved and the cause
may stay unknown. Tell the Linux team.

## KERNEL LOG

`host-check`.

| KEY | VALUE | STATUS |
|---|---|---|
| `errors` | `0 in 24h` | OK |
| | `N in 24h, latest: ...` | WARN |
| | `not readable: user not in systemd-journal` | WARN |
| | `journalctl failed, rc=N` | WARN |

**Meaning.** Kernel messages at priority err or worse in the last
`KLOG_HRS` (24) hours: disk I/O errors, filesystem errors, hardware faults.

**WARN (errors).** List them:

```
journalctl -k -p err --since -24h --no-pager
```

`I/O error`, `EXT4-fs error`, `XFS ... metadata`, `Hardware Error`, `Out of
memory`: call the Linux team today.

**WARN (not readable).** Ask the Linux team to add the user to the
`systemd-journal` group.

## FILESYSTEM

`disk-check`.

| KEY | VALUE | STATUS |
|---|---|---|
| `local` (summary) | `5 checked, highest 83% on /u01` | status of the fullest |
| a mount over a limit, for example `/u01` | `Used=83%` | WARN above `FS_WARN` (80), CRIT above `FS_CRIT` (90) |
| `local` | `no filesystems read` | WARN |

**Action.** Find what grew, as your user:

```
sudo du -xh --max-depth=2 /u01 2>/dev/null | sort -h | tail -15
```

Replace `/u01` with the mount. Send the output to the owner of that data
(DBA team for Oracle paths, Linux team for `/var`, `/`). Do not delete
files yourself.

## INODES

`disk-check`.

| KEY | VALUE | STATUS |
|---|---|---|
| `local` (summary) | `4 checked, highest 9% on /u01` | status of the fullest |
| a mount over a limit | `IUse=85%` | WARN above `INODE_WARN` (80), CRIT above `INODE_CRIT` (90) |

**Meaning.** Every file uses one inode. A filesystem out of inodes refuses
new files while it still shows free space. Millions of small files (trace
files, audit files, session files) cause it.

**Action.** Find the folder with the most files:

```
sudo find /u01 -xdev -type f | awk -F/ '{ print "/" $2 "/" $3 }' | sort | uniq -c | sort -n | tail
```

Send the output to the owner of that folder.

## READ-ONLY FS

`disk-check`.

| KEY | VALUE | STATUS |
|---|---|---|
| `local` | `none read-only` | OK |
| a mount, for example `/u01` | `mounted read-only` | CRIT |
| `local` | `/proc/mounts not readable` | WARN |

**Meaning.** The kernel switches a filesystem to read-only after an I/O or
metadata error to protect it. Nothing can write there; on `/u01` the
database stops.

**CRIT.** Call the on-call Linux admin now. Also read the KERNEL LOG row of
`host-check.sh`: it usually shows the error that caused it.

## SCSI PATH

`disk-check`.

| KEY | VALUE | STATUS |
|---|---|---|
| `all` | `N paths running` | OK |
| a disk, for example `sdc` | `state offline` (or `blocked`, `transport-offline`) | WARN |
| `all` | `no SCSI disks` | INFO |

**Meaning.** Each `sd` device is one path to a disk. A path that is not
`running` no longer carries I/O. With multipath, the disk stays reachable
over the other paths (see MULTIPATH).

**WARN.** Tell the Linux and storage teams the device names. Check the
MULTIPATH rows for the redundancy left.

## MULTIPATH

`disk-check`, one row per multipath device.

| KEY | VALUE | STATUS |
|---|---|---|
| device name, for example `mpatha` | `2 of 2 paths running` | OK |
| | fewer running than `MPATH_MIN` (2) | WARN |
| | `0 of N paths running` | CRIT |
| `all` | `no multipath devices` | INFO |

**Meaning.** A SAN disk reached over several paths. One path left means
the next failure takes the disk away. Zero paths means it is gone already.

**CRIT.** Call the on-call Linux admin and storage team now. On a database
node, also call the on-call DBA.

**WARN.** Tell the Linux and storage teams today.

## BONDING

`hw-check`.

| KEY | VALUE | STATUS |
|---|---|---|
| bond name, for example `bond0` | `2 of 2 slaves up` | OK |
| | some slaves down | WARN |
| | bond down, or no slave up | CRIT |
| bond and slave, for example `bond0 ens2f0` | `MII status down` | CRIT |
| `all` | `no bonded interfaces` | INFO |

**Meaning.** A bond joins two or more network ports so one cable or switch
port can fail. A slave down means that protection is gone.

**Action.** Send this to the Linux and network teams:

```
cat /proc/net/bonding/bond0
```

Replace `bond0` with the bond in the row.

## HUGEPAGES

`hw-check`.

| KEY | VALUE | STATUS |
|---|---|---|
| `configured` | `40960 x 2048kB, free 1024, reserved 512` | OK |
| | `0, the SGA uses normal pages` | WARN |
| | `/proc/meminfo not readable` | WARN |
| `transparent` | `never` | OK |
| | `always [madvise] never, Oracle advises never` (any setting other than never) | WARN |
| `all` | `not checked, CHECK_HUGEPAGES=0` | INFO |

**Meaning.** Oracle keeps its shared memory (SGA) in HugePages to save
memory and CPU. Transparent hugepages cause pauses for Oracle databases.
Both matter on database servers only; app and web servers set
`CHECK_HUGEPAGES=0`.

**WARN.** Tell the DBA team and the Linux team. Changing either needs a
change request and a database restart.
