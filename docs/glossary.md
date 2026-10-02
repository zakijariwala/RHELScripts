# Glossary

Every term the docs use, in alphabetical order. Other pages link here the
first time they use a term. Phase 1 and Phase 3 add entries as their
scripts arrive.

Each entry: what it is in one or two sentences, then where you meet it in
this repo.

## Linux and general

### config.env
The settings file next to a check script. It holds real host names and
thresholds, so git never stores it; the repo ships `config.env.example`
instead. The checklist reads it as `KEY=value` lines and never runs it.

### cron
The Linux scheduler. A line in a crontab file runs a command at set times.
The checklist runs by hand today; a cron rollout guide comes later.

### exit code
A number a command hands back when it finishes. `echo $?` prints it. In
this repo 0 means OK, 1 WARN, 2 CRIT, 3 already running, 64 bad usage.

### file descriptor
A number a process uses for an open file. 0 is input, 1 is output, 2 is
errors. `exec 9>file` opens a file as number 9 for the rest of a script.

### flock
A command that takes a lock on a file. The checklist uses it so two runs
cannot overlap; the second exits with code 3.

### heredoc
A block of text inside a shell script, fed to a command as its input.
It starts with `<<EOF` and ends at a line holding `EOF`. The checklist
sends its SQL to sqlplus this way.

### load average
The number of processes running or waiting for CPU, averaged over 1, 5
and 15 minutes (`/proc/loadavg`). Divided by the number of cores, above 1
means work queues for CPU.

### MTA
Mail transfer agent. The program on a server that accepts mail
(`/usr/sbin/sendmail`) and passes it to the company mail server. Postfix
is the usual MTA on RHEL.

### passwordless ssh
ssh login with a key pair instead of a password. The private key stays in
`~/.ssh` on the client; the public key sits in `~/.ssh/authorized_keys` on
the server. Scripts need it, because nobody types a password at 3 a.m.

### Postfix
The MTA on RHEL. Its settings live in `/etc/postfix/main.cf`; `postconf
relayhost` shows where it forwards mail. It logs to `/var/log/maillog`.

### relay host
The company mail server that accepts mail from servers and passes it to
Exchange. Exchange accepts it only from servers listed on its **receive
connector**, which the mail team manages.

### sar
A command from the `sysstat` package that reports CPU, memory and disk
use. The checklist reads CPU from it.

### shellcheck
A program that reads a bash script and reports bugs and risky lines. CI
runs it on every `.sh` file.

### ssh BatchMode
An ssh option (`-o BatchMode=yes`) that makes ssh fail at once instead of
waiting for a password nobody will type. Every ssh call in this repo uses
it.

### stale file
An input file older than expected. The checklist reads files that other
jobs rewrite every few minutes. If a file stops changing, the job that
writes it has stopped, and the script reports CRIT instead of trusting old
numbers.

### stub
A fake version of a command (`sqlplus`, `ssh`, `sar`) used in tests. It
prints canned output, so tests run with no real server.

### swap
Disk space Linux uses as overflow memory. A database server that swaps
slows down, because disk is far slower than memory.

### timeout
A command that runs another command and kills it after a set number of
seconds (`timeout 60 crsctl ...`). It then returns exit code 124.

## Oracle

### alert log
A text log each Oracle instance writes. Errors appear in it as lines
containing `ORA-` followed by a number.

### archive destination
A place the database sends archive logs: local disk (the FRA) or a
standby database. `v$archive_dest` lists them.

### archive log
A copy of a filled redo log. The database writes one after each log
switch. Backups and Data Guard both depend on them.

### ARCHIVELOG mode
A database setting that keeps every redo log as an archive log. Production
databases run in this mode.

### ASM
Automatic Storage Management. Oracle's own volume manager. It groups disks
into **diskgroups** (for example DATA and FRA) and stores database files
in them.

### autoextend
A data file setting that lets Oracle grow the file on its own, up to a
maximum size (`maxbytes`). The checklist measures tablespaces against that
maximum, not the current size.

### Clusterware
Oracle's cluster software (part of Grid Infrastructure). It starts,
stops and watches instances, listeners, ASM and virtual IPs on every node.
`crsctl stat res -t` lists what it manages.

### crsctl
The Clusterware command-line tool, in `GRID_HOME/bin`. `crsctl stat res -t`
lists every cluster resource with its TARGET (wanted state) and STATE
(actual state).

### Data Guard
Oracle's standby database feature. A second database on a DR site
receives redo from production and applies it, so it stays a few minutes
behind and can take over.

### DR
Disaster recovery. The second site that takes over if the main site fails.

### FRA
Fast Recovery Area. A disk area where Oracle keeps archive logs and
backups. When it fills in ARCHIVELOG mode, the database stops.

### gg2.sh, activesession.sh
Two site scripts that already live on the servers and report GoldenGate
extracts and active session peaks. This repo does not contain them. The
checklist runs them and parses their output.

### GoldenGate
Oracle's replication product. An **extract** process reads changes from
the database; **pumps** and **replicats** carry and apply them elsewhere.
`gg2.sh` reports extract status to the checklist.

### Grid Infrastructure
The Oracle software layer under the database: Clusterware plus ASM. Its
install directory is the **GRID_HOME**.

### GRID_HOME
The folder where Grid Infrastructure is installed, for example
`/u01/app/19.0.0/grid`. `/etc/oracle/olr.loc` records it in its `crs_home`
line.

### instance
The set of Oracle processes and memory that serves a database on one
server. A two-node RAC has one database and two instances.

### lag
How far behind a copy is, in time. Data Guard lag and GoldenGate lag both
appear in the checklist.

### listener
The Oracle process that accepts new client connections on a network port.

### ORA- error
An Oracle error message, such as `ORA-01034: ORACLE not available`.

### ORACLE_HOME
The folder where the Oracle database software is installed. `sqlplus`
lives in `$ORACLE_HOME/bin`. The oracle user's login profile sets it.

### ORACLE_SID
The name of the instance on the current server. The `oracle` user's
profile sets it. sqlplus needs it to know which instance to connect to.

### RAC
Real Application Clusters. One Oracle database served by two or more
servers (nodes) at the same time. If one node fails, the other keeps the
database open.

### redo log
Files where Oracle records every change before writing it to the data
files.

### RMAN
Recovery Manager. Oracle's backup tool.

### SCAN
Single Client Access Name. One name for the whole cluster that clients
connect to; Clusterware runs SCAN listeners and VIPs behind it.

### schema
A database user and the tables it owns. The application's tables sit in
one schema.

### SCN
System Change Number. A counter Oracle raises with every change. Tools
compare SCNs to see how far behind a copy is.

### sqlplus
Oracle's command-line SQL client. The checklist runs it as
`sqlplus -s / as sysdba`.

### standby
The Data Guard copy of the database on the DR site.

### sysdba
The top Oracle administrative privilege. `/ as sysdba` logs in as SYS
with no password, using the fact that the Linux user belongs to the `dba`
group.

### tablespace
A named storage area inside the database. **TEMP** holds sort space,
**UNDO** holds old row versions, the rest hold tables and indexes.

### thread
In RAC, each instance writes its own redo stream, called a thread. Node 1
writes thread 1, node 2 writes thread 2.

### VIP
Virtual IP. An extra IP address per node that Clusterware moves to the
other node when a node fails, so clients get a fast error instead of a
long timeout.

## Ansible

### Ansible
A tool that runs tasks on many servers over ssh from one machine. It
needs no agent on the servers. Arrives in Phase 3.

### control node
The server where Ansible is installed and from where it reaches every
other server.

### FQCN
Fully qualified collection name. The full name of an Ansible module, such
as `ansible.builtin.command`. This repo uses FQCNs only.

### inventory
The file that lists the servers Ansible manages and their groups. Real
inventories stay out of git; the repo ships `example.ini`.

### playbook
A YAML file listing tasks for Ansible to run on a group of servers.

### serial
A playbook setting. `serial: 1` makes Ansible finish one server before
starting the next. Every action playbook uses it.

### vault
Ansible's encrypted file format for passwords and keys. Vault files stay
out of git.

## Repo terms

### change request (CR)
An approved ticket that allows a change on production. See
[change-requests.md](change-requests.md).

### CRIT, WARN, OK, INFO
The four statuses every script prints. CRIT needs action now. WARN needs a
look today. OK means the value was measured and is inside its limits.
INFO is a fact with no limit. [reading-output.md](reading-output.md)
covers them in full.

### fresher
A new team member who knows basic Linux and none of Oracle or Ansible.
Every doc in this repo is written so a fresher can follow it alone.
