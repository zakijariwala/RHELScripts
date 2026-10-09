#!/bin/bash
# health-check.sh - health of THIS server. Read-only, writes no files.
# Usage: ./health-check.sh      Exit: 0 OK, 1 WARN, 2 CRIT
set -o pipefail

DB=vpsdb
AGENTS="splunkd crond chronyd ds_agent rscd tmxbc ragent ragentinst"
CRS="ohasd ocssd crsd evmd gpnpd gipcd mdnsd octssd osysmond"
FS_WARN=70
FS_CRIT=90

G='\033[0;32m'; R='\033[0;31m'; Y='\033[1;33m'; B='\033[1;36m'; NC='\033[0m'
[ -t 1 ] || { G=''; R=''; Y=''; B=''; NC=''; }
RULE=------------------------------------------------------------------
O=0; W=0; C=0; PROB=''
tag() { case $1 in OK) T=' OK '; COL=$G ;; WARN) T=WARN; COL=$Y ;;
                   *) T=CRIT; COL=$R ;; esac; }
add() { case $1 in OK) O=$((O+1)) ;;
        WARN) W=$((W+1)); PROB="$PROB    ${Y}[WARN]${NC} $2: $3\n" ;;
        *) C=$((C+1)); PROB="$PROB    ${R}[CRIT]${NC} $2: $3\n" ;; esac; }
say() { tag "$1"; printf "  %b[%s]%b %-14s %s\n" "$COL" "$T" "$NC" "$2" "$3"
        add "$@"; }
ok()   { say OK "$@"; }
warn() { say WARN "$@"; }
crit() { say CRIT "$@"; }
info() { printf "         %-14s %s\n" "$1" "$2"; }
line() { printf "\n%b-- %s %s%b\n" "$B" "$1" "${RULE:${#1}}" "$NC"; }

ORA=0
pgrep -f "^(ora|asm)_pmon_" > /dev/null || [ -e /etc/oracle/olr.loc ] && ORA=1
ROLE="no Oracle found: DB checks skipped"
[ $ORA -eq 1 ] && ROLE="Oracle DB node"
printf "%b%s%b\n" "$B" "$RULE---" "$NC"
printf "  %-8s %s\n" Host "$(hostname)" IP "$(hostname -I | xargs)" \
  OS "$(cat /etc/redhat-release 2>/dev/null)" Uptime "$(uptime -p)" \
  Time "$(date '+%F %T')" Role "$ROLE"
printf "%b%s%b\n" "$B" "$RULE---" "$NC"

line "Kernel"
RUN=$(uname -r)
NEW=$(rpm -q --last kernel-core 2>/dev/null | head -1 | awk '{print $1}')
NEW=${NEW#kernel-core-}
if [ -z "$NEW" ]; then warn Kernel "cannot read installed kernels"
elif [ "$NEW" = "$RUN" ]; then ok Kernel "$RUN (newest installed)"
else warn Kernel "running $RUN, newest $NEW: reboot pending"; fi

line "CPU and memory"
CPUS=$(nproc)
L15=$(cut -d' ' -f3 /proc/loadavg)
if [ "${L15%.*}" -ge $((CPUS * 2)) ]; then L=CRIT
elif [ "${L15%.*}" -ge "$CPUS" ]; then L=WARN; else L=OK; fi
say $L Load "$L15 (15 min) on $CPUS CPUs"
MEM=$(free -m | awk '/^Mem:/{print int($7*100/$2)}')
if [ "$MEM" -le 5 ]; then L=CRIT
elif [ "$MEM" -le 10 ]; then L=WARN; else L=OK; fi
say $L Memory "$MEM% available"
SWP=$(free -m | awk '/^Swap:/{if ($2>0) print int($3*100/$2); else print 0}')
if [ "$SWP" -ge 80 ]; then L=CRIT
elif [ "$SWP" -ge 50 ]; then L=WARN; else L=OK; fi
say $L Swap "$SWP% used"

line "Filesystems"
declare -A INO
DFI=$(timeout 10 df -P -l -i -x tmpfs -x devtmpfs | tail -n +2)
while read -r _ _ _ _ USE MNT; do INO[$MNT]=${USE%\%}; done <<< "$DFI"
DF=$(timeout 10 df -P -h -l -x tmpfs -x devtmpfs | tail -n +2)
[ $? -eq 124 ] && crit Filesystems "df hung: a filesystem is not responding"
printf "         %6s %5s %6s  %s\n" SIZE USED INODES MOUNT
while read -r _ SIZE _ _ USE MNT; do
  USE=${USE%\%}; IU=${INO[$MNT]:--}
  case $USE in ''|-) continue ;; esac
  L=OK
  [ "$USE" -ge $FS_WARN ] && L=WARN
  [ "$USE" -ge $FS_CRIT ] && L=CRIT
  [ "$IU" != - ] && [ "$IU" -ge $FS_WARN ] && [ $L = OK ] && L=WARN
  tag $L
  printf "  %b[%s]%b %6s %5s %6s  %s\n" "$COL" "$T" "$NC" \
    "$SIZE" "$USE%" "$IU%" "$MNT"
  add $L "$MNT" "$USE% used, inodes $IU%"
done <<< "$DF"
while read -r DEV MNT TYPE OPT _; do
  case $TYPE in xfs|ext4|ext3) ;; *) continue ;; esac
  case ,$OPT, in *,ro,*) crit "$MNT" "mounted read-only ($DEV)" ;; esac
done < /proc/mounts
while read -r DEV MNT TYPE _; do
  case $TYPE in nfs|nfs4|cifs) ;; *) continue ;; esac
  if timeout 5 stat -t "$MNT" > /dev/null 2>&1; then ok "$MNT" "$TYPE responds"
  else crit "$MNT" "$TYPE from $DEV not responding"; fi
done < /proc/mounts

line "Time sync"
TRK=$(timeout 10 chronyc tracking 2>/dev/null)
LEAP=$(echo "$TRK" | awk -F': ' '/^Leap/{print $2}')
OFF=$(echo "$TRK" | awk '/^System time/{print int($4*1000)}')
if [ -z "$TRK" ]; then crit Chrony "no answer (chronyd down?)"
elif [ "$LEAP" != "Normal" ]; then crit Chrony "clock not synchronised"
elif [ "${OFF:-0}" -ge 100 ]; then warn Chrony "synchronised, offset $OFF ms"
else ok Chrony "synchronised, offset ${OFF:-0} ms"; fi

line "Agents and services"
for A in $AGENTS; do
  if pgrep -x "$A" > /dev/null; then L=OK; TXT=running
  else L=CRIT; TXT="not running"; fi
  if [ "$(systemctl is-enabled "$A" 2>/dev/null)" = disabled ]; then
    TXT="$TXT, unit disabled (no start after reboot)"
    [ $L = OK ] && L=WARN
  fi
  say $L "$A" "$TXT"
done
FAILED=$(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}')
if [ $? -ne 0 ]; then warn systemd "systemctl did not answer"
elif [ -n "$FAILED" ]; then warn systemd "failed: $(echo "$FAILED" | xargs)"
else ok systemd "no failed units"; fi

if [ $ORA -eq 1 ]; then
  line "Database"
  SIDS=$(ps -eo args= | grep "^ora_pmon_$DB" | cut -d_ -f3 | xargs)
  if [ -n "$SIDS" ]; then ok Instance "$SIDS running"
  else crit Instance "no $DB instance running"; fi
  if pgrep -f "^asm_pmon_" > /dev/null; then ok ASM running
  else crit ASM "not running"; fi
  LSNR=$(ps -eo args= | grep "/tnslsnr " | grep -v grep | awk '{print $2}')
  if echo "$LSNR" | grep -qx LISTENER; then ok LISTENER running
  else crit LISTENER "not running"; fi
  for L in $LSNR; do [ "$L" = LISTENER ] || info "$L" running; done

  line "Cluster"
  for D in $CRS; do
    if pgrep -x "$D.bin" > /dev/null; then ok "$D" running
    else crit "$D" "not running"; fi
  done
  GH=$(grep "^crs_home=" /etc/oracle/olr.loc 2>/dev/null | cut -d= -f2)
  if [ ! -x "$GH/bin/crsctl" ]; then warn crsctl "not found"
  else
    N=$(timeout 30 "$GH/bin/crsctl" check crs | grep -c "is online")
    if [ "$N" -ge 4 ]; then ok crsctl "check crs: 4 of 4 online"
    else crit crsctl "check crs: $N of 4 online"; fi
  fi
fi

line "Summary"
if [ $C -gt 0 ]; then RC=2; OV="${R}CRIT$NC"
elif [ $W -gt 0 ]; then RC=1; OV="${Y}WARN$NC"
else RC=0; OV="${G}OK$NC"; fi
printf "  Overall  %b   (ok=%d warn=%d crit=%d)\n" "$OV" $O $W $C
[ -n "$PROB" ] && { echo "  Needs attention:"; printf "%b" "$PROB"; }
printf "%b%s%b\n" "$B" "$RULE---" "$NC"
exit $RC
