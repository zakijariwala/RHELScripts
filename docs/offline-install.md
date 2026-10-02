# Offline install

The servers have no internet access, so `dnf install` cannot reach Red Hat.
This page installs packages from a source you bring to the server
yourself.

| Package | Needed by | Where |
|---|---|---|
| `sysstat` | Oracle RAC checklist (`sar`) | node 1 and node 2 |
| `gitleaks` | pre-commit hook | your machine; see [pre-commit-hook.md](pre-commit-hook.md) |
| `bats` | running the tests | your machine (Phase 2) |
| `ansible-core` | Ansible playbooks | control node (Phase 3) |

Installing a package on a production server is a change. Raise a change
request first ([change-requests.md](change-requests.md)). On
pre-production, follow your team's rule.

## Check whether sysstat is already there

**Your user, on each node:**

```
rpm -q sysstat
```

Installed:

```
sysstat-11.7.3-9.el8.x86_64
```

Not installed:

```
package sysstat is not installed
```

If it is installed on both nodes, stop here.

## Option A: the server already has an internal repository

Many sites mirror Red Hat inside the network (Red Hat Satellite, a Nexus
or Artifactory proxy, an NFS share). Try this first.

1. **Your user, the node**: see which repositories `dnf` knows.

   ```
   sudo dnf repolist
   ```

   Expected, with an internal mirror:

   ```
   repo id                              repo name
   rhel-8-for-x86_64-appstream-rpms     Red Hat Enterprise Linux 8 for x86_64 - AppStream (RPMs)
   rhel-8-for-x86_64-baseos-rpms        Red Hat Enterprise Linux 8 for x86_64 - BaseOS (RPMs)
   ```

   If you see `This system is not registered with an entitlement server`
   and no repo list, go to Option B.

2. **Your user, the node**: install.

   ```
   sudo dnf install -y sysstat
   ```

   Expected, near the end:

   ```
   Installed:
     sysstat-11.7.3-9.el8.x86_64
   Complete!
   ```

   If you see `Cannot download repomd.xml` or `Curl error`, the
   repository is listed but unreachable. Go to Option B, or ask the Linux
   team.

## Option B: download the RPM on a connected machine

You need a machine with internet access that runs **the same RHEL major
version** as the server (RHEL 8 for RHEL 8, RHEL 9 for RHEL 9), registered
with Red Hat. Ask the Linux team for one.

1. **Your user, the connected machine**: download sysstat and every
   package it needs into a folder.

   ```
   mkdir -p ~/rpms && sudo dnf download --resolve --destdir ~/rpms sysstat
   ```

   Expected: one line per downloaded file, for example:

   ```
   sysstat-11.7.3-9.el8.x86_64.rpm          1.2 MB/s | 425 kB     00:00
   ```

   `--resolve` also fetches the packages sysstat depends on; on most
   servers these are already installed and `dnf` skips them later.

2. **Your user, the connected machine**: record checksums, so you can prove
   the files did not change on the way.

   ```
   cd ~/rpms && sha256sum *.rpm > SHA256SUMS && cat SHA256SUMS
   ```

3. **Your user, the connected machine**: copy the folder to the node,
   directly or through your jump host.

   ```
   scp -r ~/rpms CHANGE_ME_YOUR_USER@CHANGE_ME_NODE_HOST:/tmp/
   ```

4. **Your user, the node**: check the checksums.

   ```
   cd /tmp/rpms && sha256sum -c SHA256SUMS
   ```

   Expected: every line ends in `OK`. If any line says `FAILED`, delete the
   folder and copy it again.

5. **Your user, the node**: install from the folder.

   ```
   sudo dnf install -y /tmp/rpms/*.rpm
   ```

   Expected, near the end: `Complete!`. `dnf` still checks the Red Hat
   signature on each file. If you see `GPG check FAILED`, the file is not
   a genuine Red Hat package. Stop and tell the Linux team.

6. **Your user, the node**: remove the copies.

   ```
   rm -r /tmp/rpms
   ```

## Option C: the RHEL installation ISO

The RHEL DVD image contains sysstat. The Linux team keeps a copy for
server builds. This works on any server, connected or not.

1. **Your user, your machine**: copy the ISO matching the server's exact
   release to the node. Find the release on the node with
   `cat /etc/redhat-release`.

   ```
   scp CHANGE_ME_RHEL_ISO.iso CHANGE_ME_YOUR_USER@CHANGE_ME_NODE_HOST:/tmp/rhel.iso
   ```

2. **Your user, the node**: mount it read-only.

   ```
   sudo mkdir -p /mnt/rhel-iso && sudo mount -o loop,ro /tmp/rhel.iso /mnt/rhel-iso
   ```

   Expected: no output. `ls /mnt/rhel-iso` shows `AppStream` and `BaseOS`.

3. **Your user, the node**: install sysstat from the ISO only. The two
   `--repofrompath` options point `dnf` at the ISO for this one command;
   nothing is added to the system's repository settings.

   ```
   sudo dnf install -y --disablerepo='*' --repofrompath=iso-base,/mnt/rhel-iso/BaseOS --repofrompath=iso-app,/mnt/rhel-iso/AppStream --enablerepo=iso-base --enablerepo=iso-app sysstat
   ```

   Expected, near the end: `Complete!`.

   If you see `Public key for sysstat-... is not installed`, the server has
   not yet trusted the Red Hat signing key. Import the key that ships with
   RHEL, then repeat this step:

   ```
   sudo rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
   ```

4. **Your user, the node**: unmount and delete the ISO.

   ```
   sudo umount /mnt/rhel-iso && rm /tmp/rhel.iso
   ```

## Check sar works

**Your user, the node:**

```
sar -u 1 1 | tail -1
```

Expected:

```
Average:        all      3.52      0.00      1.01      0.13      0.00     95.34
```

The checklist runs `sar -u 1 3`, which samples live. It does not need the
`sysstat` service that records history, so you do not have to enable it.
