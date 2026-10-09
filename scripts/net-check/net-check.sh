#!/bin/bash
# net-check.sh - is it this server, DNS or the network? Read-only.
# Usage: ./net-check.sh [HOST [PORT]]   Exit: 0 OK, 1 WARN, 2 CRIT
set -o pipefail

# Fixed targets, tested on every run. One per line: NAME PORT
TARGETS="
"

HOST=$1
PORT=${2:-22}
case $PORT in *[!0-9]*|'') echo "usage: $0 [HOST [PORT]]"; exit 64 ;; esac

G='\033[0;32m'; R='\033[0;31m'; Y='\033[1;33m'; B='\033[1;36m'; NC='\033[0m'
[ -t 1 ] || { G=''; R=''; Y=''; B=''; NC=''; }
RULE=------------------------------------------------------------------
O=0; W=0; C=0; PROB=''; VERDICT=''
tag() { case $1 in OK) T=' OK '; COL=$G ;; WARN) T=WARN; COL=$Y ;;
                   *) T=CRIT; COL=$R ;; esac; }
add() { case $1 in OK) O=$((O+1)) ;;
        WARN) W=$((W+1)); PROB="$PROB    ${Y}[WARN]${NC} $2: $3\n" ;;
        *) C=$((C+1)); PROB="$PROB    ${R}[CRIT]${NC} $2: $3\n" ;; esac; }
say() { tag "$1"; printf "  %b[%s]%b %-14s %s\n" "$COL" "$T" "$NC" "$2" "$3"
        add "$@"; }
ok()   { say OK "$@"; }
warn() { say WARN "$@"; }
fail() { say CRIT "$2" "$3"; [ -z "$VERDICT" ] && VERDICT=$1; }
info() { printf "         %-14s %s\n" "$1" "$2"; }
line() { printf "\n%b-- %s %s%b\n" "$B" "$1" "${RULE:${#1}}" "$NC"; }

# tcp HOST PORT -> OK, REFUSED, TIMEOUT, NOROUTE or ERROR: message
tcp() {
  if command -v nc > /dev/null; then
    OUT=$(timeout 8 nc -zv -w 3 "$1" "$2" 2>&1)
  else
    OUT=$(timeout 3 bash -c "exec 3<>/dev/tcp/$1/$2" 2>&1) && OUT=Connected
  fi
  case $OUT in
    *Connected*) echo OK ;;
    *[Rr]efused*) echo REFUSED ;;
    *"No route"*) echo NOROUTE ;;
    *TIMEOUT*|*"timed out"*|'') echo TIMEOUT ;;
    *) echo "ERROR: $(echo "$OUT" | tail -1)" ;;
  esac
}

printf "%b%s%b\n" "$B" "$RULE---" "$NC"
printf "  %-8s %s\n" Host "$(hostname)" Time "$(date '+%F %T')" \
  Target "${HOST:-none given}${HOST:+ port $PORT}"
printf "%b%s%b\n" "$B" "$RULE---" "$NC"

line "Local server"
UP=0
for P in /sys/class/net/*; do
  IF=${P##*/}
  [ "$IF" = lo ] || [ ! -d "$P" ] || [ -e "$P/master" ] && continue
  case $IF in virbr*|docker*|veth*|vnet*|br-*|cni*)
    info "$IF" "virtual bridge, ignored"; continue ;; esac
  STATE=$(cat "$P/operstate")
  IP=$(ip -4 -o addr show dev "$IF" | awk '{print $4}' | head -1)
  if [ -z "$IP" ]; then info "$IF" "no IPv4 address (unused)"
  elif [ "$STATE" = down ]; then fail "LOCAL SERVER" "$IF" "$IP is DOWN"
  else ok "$IF" "$IP $STATE"; UP=1; fi
  E=$(( $(cat "$P/statistics/rx_errors") + $(cat "$P/statistics/tx_errors") ))
  [ "$E" -gt 0 ] && warn "$IF" "$E rx/tx errors since boot"
done
[ $UP -eq 0 ] && fail "LOCAL SERVER" Interfaces "none up with an IPv4 address"
for BF in /proc/net/bonding/*; do
  [ -e "$BF" ] || continue
  DOWN=$(awk '/^Slave Interface/{s=$3} /^MII Status/ && s{if ($3!="up")
         print s; s=""}' "$BF" | xargs)
  if [ -n "$DOWN" ]; then warn "${BF##*/}" "slave down: $DOWN"
  else ok "${BF##*/}" "all slaves up"; fi
done
GW=$(ip -4 route show default | awk '{print $3; exit}')
if [ -z "$GW" ]; then fail "LOCAL SERVER" Route "no default route"
else ok Route "default via $GW"; fi

if [ -n "$GW" ]; then
  line "Gateway"
  if ping -c 2 -W 2 -q "$GW" > /dev/null 2>&1; then
    ok Ping "$GW answers"
    if ping -c 1 -W 2 -M "do" -s 1472 "$GW" > /dev/null 2>&1; then
      ok MTU "1500-byte packets pass"
    else warn MTU "1500-byte packets do not pass"; fi
  else
    fail NETWORK Ping "$GW does not answer"
  fi
  ARP=$(ip neigh show "$GW" | awk '{print $NF}')
  case $ARP in FAILED|INCOMPLETE)
    fail NETWORK ARP "$ARP: cable, switch port or VLAN" ;; esac
fi

line "Targets"
check() {
  case $1 in *[!0-9.]*)
    IP=$(timeout 10 getent ahostsv4 "$1" | awk '{print $1; exit}')
    if [ -z "$IP" ]; then
      fail DNS "$1:$2" "cannot resolve (run dns-check.sh $1)"; return
    fi ;;
  *) IP=$1 ;;
  esac
  RES=$(tcp "$1" "$2")
  case $RES in
    OK) ok "$1:$2" "connected ($IP)" ;;
    REFUSED) fail "TARGET SERVICE" "$1:$2" "refused: host up, no listener" ;;
    TIMEOUT|NOROUTE) fail NETWORK "$1:$2" "$RES: firewall or host down"
      command -v tracepath > /dev/null &&
        timeout 20 tracepath -n -m 15 "$1" 2>&1 | tail -3 |
        while read -r X; do info "" "$X"; done ;;
    *) fail NETWORK "$1:$2" "$RES" ;;
  esac
}
[ -n "$HOST" ] && check "$HOST" "$PORT"
while read -r H P; do
  case $H in ''|'#'*) continue ;; esac
  check "$H" "${P:-22}"
done <<< "$TARGETS"
[ -z "$HOST" ] && [ -z "${TARGETS//[[:space:]]/}" ] &&
  info None "give HOST PORT, or add lines to TARGETS"

line "Summary"
if [ $C -gt 0 ]; then RC=2; OV="${R}CRIT$NC"
elif [ $W -gt 0 ]; then RC=1; OV="${Y}WARN$NC"
else RC=0; OV="${G}OK$NC"; fi
printf "  Overall  %b   (ok=%d warn=%d crit=%d)\n" "$OV" $O $W $C
VC=$G; [ -n "$VERDICT" ] && VC=$R
printf "  Verdict  %b%s%b\n" "$VC" "${VERDICT:-OK}" "$NC"
[ -n "$PROB" ] && { echo "  Needs attention:"; printf "%b" "$PROB"; }
printf "%b%s%b\n" "$B" "$RULE---" "$NC"
exit $RC
