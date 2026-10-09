#!/bin/bash
# health-check.sh - health of THIS server. Read-only, writes no files.
# Usage: ./health-check.sh      Exit: 0 OK, 1 WARN, 2 CRIT
set -o pipefail

DB=vpsdb
AGENTS="splunkd crond chronyd ds_agent rscd tmxbc ragent ragentinst"
CRS="ohasd ocssd crsd evmd gpnpd gipcd mdnsd octssd osysmond"
FS_WARN=70
FS_CRIT=90

G='\033[0;32m'; R='\033[0;31m'; Y='\033[1;33m'; NC='\033[0m'
[ -t 1 ] || { G=''; R=''; Y=''; NC=''; }
W=0; C=0
ok()   { echo -e "${G}[ OK ]${NC} $*"; }
warn() { echo -e "${Y}[WARN]${NC} $*"; W=$((W+1)); }
crit() { echo -e "${R}[CRIT]${NC} $*"; C=$((C+1)); }
line() { echo "== $* =="; }

line "$(hostname) $(date '+%F %T')"

line "Kernel"
RUN=$(uname -r)
NEW=$(rpm -q --last kernel-core 2>/dev/null | head -1 | awk '{print $1}')
NEW=${NEW#kernel-core-}
if [ -z "$NEW" ]; then warn "cannot read installed kernels"
elif [ "$NEW" = "$RUN" ]; then ok "running newest kernel $RUN"
else warn "running $RUN, newest installed $NEW: reboot pending"; fi
echo "uptime: $(uptime -p)"

line "CPU and memory"
CPUS=$(nproc)
L15=$(cut -d' ' -f3 /proc/loadavg)
if [ "${L15%.*}" -ge $((CPUS * 2)) ]; then crit "load $L15 on $CPUS CPUs"
elif [ "${L15%.*}" -ge "$CPUS" ]; then warn "load $L15 on $CPUS CPUs"
else ok "load $L15 on $CPUS CPUs"; fi
MEM=$(free -m | awk '/^Mem:/{print int($7*100/$2)}')
if [ "$MEM" -le 5 ]; then crit "memory available $MEM%"
elif [ "$MEM" -le 10 ]; then warn "memory available $MEM%"
else ok "memory available $MEM%"; fi
SWP=$(free -m | awk '/^Swap:/{if ($2>0) print int($3*100/$2); else print 0}')
if [ "$SWP" -ge 80 ]; then crit "swap used $SWP%"
elif [ "$SWP" -ge 50 ]; then warn "swap used $SWP%"
else ok "swap used $SWP%"; fi

line "Filesystems"
DF=$(timeout 10 df -P -l -x tmpfs -x devtmpfs | tail -n +2)
[ $? -eq 124 ] && crit "df hung: a filesystem is not responding"
DFI=$(timeout 10 df -P -l -i -x tmpfs -x devtmpfs | tail -n +2)
BAD=0
while read -r DEV _ _ _ USE MNT; do
  USE=${USE%\%}
  case $USE in ''|-) continue ;; esac
  if [ "$USE" -ge $FS_CRIT ]; then crit "$MNT $USE% full"; BAD=1
  elif [ "$USE" -ge $FS_WARN ]; then warn "$MNT $USE% full"; BAD=1; fi
done <<< "$DF"
while read -r DEV _ _ _ USE MNT; do
  USE=${USE%\%}
  case $USE in ''|-) continue ;; esac
  if [ "$USE" -ge $FS_WARN ]; then warn "$MNT inodes $USE% used"; BAD=1; fi
done <<< "$DFI"
[ $BAD -eq 0 ] && ok "all filesystems below $FS_WARN% space and inodes"
while read -r DEV MNT TYPE OPT _; do
  case $TYPE in xfs|ext4|ext3) ;; *) continue ;; esac
  case ,$OPT, in *,ro,*) crit "$MNT is read-only ($DEV)" ;; esac
done < /proc/mounts
while read -r DEV MNT TYPE _; do
  case $TYPE in nfs|nfs4|cifs) ;; *) continue ;; esac
  if timeout 5 stat -t "$MNT" > /dev/null 2>&1; then ok "$MNT responds"
  else crit "$MNT ($TYPE from $DEV) not responding"; fi
done < /proc/mounts

line "Time sync"
TRK=$(timeout 10 chronyc tracking 2>/dev/null)
LEAP=$(echo "$TRK" | awk -F': ' '/^Leap/{print $2}')
OFF=$(echo "$TRK" | awk '/^System time/{print int($4*1000)}')
if [ -z "$TRK" ]; then crit "chronyc gave no answer (chronyd down?)"
elif [ "$LEAP" != "Normal" ]; then crit "clock not synchronised"
elif [ "${OFF:-0}" -ge 100 ]; then warn "synchronised, offset $OFF ms"
else ok "synchronised, offset ${OFF:-0} ms"; fi

line "Agents"
for A in $AGENTS; do
  if pgrep -x "$A" > /dev/null; then ok "$A running"
  else crit "$A not running"; fi
  [ "$(systemctl is-enabled "$A" 2>/dev/null)" = disabled ] &&
    warn "$A unit is disabled: will not start after a reboot"
done
FAILED=$(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}')
if [ $? -ne 0 ]; then warn "systemctl did not answer"
elif [ -n "$FAILED" ]; then warn "failed units: $(echo "$FAILED" | tr '\n' ' ')"
else ok "no failed systemd units"; fi

if pgrep -f "^(ora|asm)_pmon_" > /dev/null || [ -e /etc/oracle/olr.loc ]
then
  line "Database"
  SIDS=$(ps -eo args= | grep "^ora_pmon_$DB" | cut -d_ -f3 | tr '\n' ' ')
  if [ -n "$SIDS" ]; then ok "instance running: $SIDS"
  else crit "no $DB instance running"; fi
  if pgrep -f "^asm_pmon_" > /dev/null; then ok "ASM running"
  else crit "ASM not running"; fi
  LSNR=$(ps -eo args= | grep "/tnslsnr " | grep -v grep | awk '{print $2}')
  if echo "$LSNR" | grep -qx LISTENER; then ok "LISTENER running"
  else crit "LISTENER not running"; fi
  for L in $LSNR; do
    [ "$L" = "LISTENER" ] || echo "also running: $L"
  done

  line "Cluster"
  for D in $CRS; do
    if pgrep -x "$D.bin" > /dev/null; then ok "$D running"
    else crit "$D not running"; fi
  done
  GH=$(grep "^crs_home=" /etc/oracle/olr.loc 2>/dev/null | cut -d= -f2)
  if [ ! -x "$GH/bin/crsctl" ]; then warn "crsctl not found"
  else
    N=$(timeout 30 "$GH/bin/crsctl" check crs | grep -c "is online")
    if [ "$N" -ge 4 ]; then ok "crsctl check crs: 4 of 4 online"
    else crit "crsctl check crs: $N of 4 online"; fi
  fi
fi

line "Summary"
if [ $C -gt 0 ]; then echo -e "${R}CRIT${NC} crit=$C warn=$W"; exit 2; fi
if [ $W -gt 0 ]; then echo -e "${Y}WARN${NC} warn=$W"; exit 1; fi
echo -e "${G}OK${NC}"; exit 0
