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

G='\033[0;32m'; R='\033[0;31m'; Y='\033[1;33m'; NC='\033[0m'
[ -t 1 ] || { G=''; R=''; Y=''; NC=''; }
W=0; C=0; VERDICT=''
ok()   { echo -e "${G}[ OK ]${NC} $*"; }
warn() { echo -e "${Y}[WARN]${NC} $*"; W=$((W+1)); }
crit() { echo -e "${R}[CRIT]${NC} $*"; C=$((C+1)); }
fail() { crit "$2"; [ -z "$VERDICT" ] && VERDICT=$1; }
line() { echo "== $* =="; }

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

line "$(hostname) $(date '+%F %T')"

line "Local server"
UP=0
for P in /sys/class/net/*; do
  IF=${P##*/}
  [ "$IF" = lo ] || [ ! -d "$P" ] || [ -e "$P/master" ] && continue
  STATE=$(cat "$P/operstate")
  IP=$(ip -4 -o addr show dev "$IF" | awk '{print $4}' | head -1)
  if [ -z "$IP" ]; then echo "$IF: no IPv4 address (unused)"
  elif [ "$STATE" = down ]; then crit "$IF ($IP) is DOWN"
  else ok "$IF $IP $STATE"; UP=1; fi
  E=$(( $(cat "$P/statistics/rx_errors") + $(cat "$P/statistics/tx_errors") ))
  [ "$E" -gt 0 ] && warn "$IF has $E rx/tx errors since boot"
done
[ $UP -eq 0 ] && fail "LOCAL SERVER" "no interface is up with an IPv4 address"
for B in /proc/net/bonding/*; do
  [ -e "$B" ] || continue
  DOWN=$(awk '/^Slave Interface/{s=$3} /^MII Status/ && s{if ($3!="up")
         print s; s=""}' "$B" | tr '\n' ' ')
  if [ -n "$DOWN" ]; then warn "${B##*/}: slave down: $DOWN"
  else ok "${B##*/}: all slaves up"; fi
done
GW=$(ip -4 route show default | awk '{print $3; exit}')
if [ -z "$GW" ]; then fail "LOCAL SERVER" "no default route"
else ok "default route via $GW"; fi

if [ -n "$GW" ]; then
  line "Gateway"
  if ping -c 2 -W 2 -q "$GW" > /dev/null 2>&1; then
    ok "gateway $GW answers ping"
    if ping -c 1 -W 2 -M "do" -s 1472 "$GW" > /dev/null 2>&1; then
      ok "1500-byte packets reach the gateway (MTU)"
    else warn "1500-byte packets do not reach the gateway (MTU)"; fi
  else
    fail NETWORK "gateway $GW does not answer ping"
  fi
  ARP=$(ip neigh show "$GW" | awk '{print $NF}')
  case $ARP in FAILED|INCOMPLETE)
    fail NETWORK "gateway ARP $ARP: cable, switch port or VLAN" ;; esac
fi

line "Targets"
check() {
  case $1 in *[!0-9.]*)
    IP=$(timeout 10 getent ahostsv4 "$1" | awk '{print $1; exit}')
    if [ -z "$IP" ]; then
      fail DNS "cannot resolve $1 (run dns-check.sh $1)"; return
    fi
    echo "$1 = $IP" ;;
  esac
  RES=$(tcp "$1" "$2")
  case $RES in
    OK) ok "$1:$2 connected" ;;
    REFUSED) fail "TARGET SERVICE" "$1:$2 refused (host up, no listener)" ;;
    TIMEOUT|NOROUTE) fail NETWORK "$1:$2 $RES: firewall or host down"
      command -v tracepath > /dev/null &&
        timeout 20 tracepath -n -m 15 "$1" 2>&1 | tail -3 | sed 's/^/   /' ;;
    *) fail NETWORK "$1:$2 $RES" ;;
  esac
}
[ -n "$HOST" ] && check "$HOST" "$PORT"
while read -r H P; do
  case $H in ''|'#'*) continue ;; esac
  check "$H" "${P:-22}"
done <<< "$TARGETS"
[ -z "$HOST" ] && [ -z "${TARGETS//[[:space:]]/}" ] &&
  echo "no targets (give HOST PORT, or add lines to TARGETS)"

line "Result"
echo "crit=$C warn=$W"
echo "VERDICT: ${VERDICT:-OK}"
[ $C -gt 0 ] && exit 2
[ $W -gt 0 ] && exit 1
exit 0
