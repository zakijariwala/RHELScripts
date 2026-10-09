#!/bin/bash
# dns-check.sh - every line of resolv.conf, every nameserver. Read-only.
# Usage: ./dns-check.sh [NAME]          Exit: 0 OK, 1 WARN, 2 CRIT
set -o pipefail

TEST_NAME=CHANGE_ME   # name every nameserver must answer
RESOLV=/etc/resolv.conf

[ "$TEST_NAME" = CHANGE_ME ] && TEST_NAME=$(hostname -f)
Q=${1:-$TEST_NAME}

G='\033[0;32m'; R='\033[0;31m'; Y='\033[1;33m'; NC='\033[0m'
[ -t 1 ] || { G=''; R=''; Y=''; NC=''; }
W=0; C=0
ok()   { echo -e "${G}[ OK ]${NC} $*"; }
warn() { echo -e "${Y}[WARN]${NC} $*"; W=$((W+1)); }
crit() { echo -e "${R}[CRIT]${NC} $*"; C=$((C+1)); }
line() { echo "== $* =="; }

line "$(hostname) $(date '+%F %T')  query: $Q"

line "$RESOLV"
NS=''; N=0; SEARCH=''; OPTS=''
while read -r KEY VAL REST; do
  case $KEY in
    ''|'#'*|';'*|sortlist) ;;
    nameserver) N=$((N+1))
      case " $NS " in *" $VAL "*) warn "nameserver $VAL listed twice" ;;
                      *) NS="$NS $VAL" ;; esac ;;
    search|domain) SEARCH="$VAL $REST" ;;
    options) OPTS="$VAL $REST" ;;
    *) warn "unknown line: $KEY (the resolver ignores it)" ;;
  esac
done < "$RESOLV"
[ $N -eq 0 ] && crit "no nameserver line"
[ $N -gt 3 ] && warn "$N nameservers: only the first 3 are used"
[ "$(wc -w <<< "$SEARCH")" -gt 6 ] && warn "more than 6 search domains"
echo "nameservers:$NS"
echo "search: ${SEARCH:-none}"
echo "options: ${OPTS:-none}"
for O in $OPTS; do
  case $O in
    timeout:*) [ "${O#*:}" -gt 5 ] && warn "$O: slow failover" ;;
    attempts:*) [ "${O#*:}" -gt 3 ] && warn "$O: slow failover" ;;
  esac
done

line "Nameservers"
DIG=$(command -v dig)
[ -z "$DIG" ] && warn "dig not installed: only TCP 53 tested"
REF=''
for S in $NS; do
  if timeout 8 nc -zv -w 3 "$S" 53 2>&1 | grep -q Connected
  then T=open; else T=closed; fi
  if [ -z "$DIG" ]; then
    if [ $T = open ]; then ok "$S TCP 53 open"; else crit "$S TCP 53 closed"; fi
    continue
  fi
  D=$(dig @"$S" +search +notcp +time=2 +tries=1 "$Q" 2>&1)
  ST=$(echo "$D" | grep -o 'status: [A-Z]*' | cut -d' ' -f2)
  AN=$(echo "$D" | grep -o 'ANSWER: [0-9]*' | cut -d' ' -f2)
  MS=$(echo "$D" | awk '/Query time/{print $4}')
  ANS=$(echo "$D" | awk '$4=="A"{print $5}' | sort | tr '\n' ' ')
  ANS=${ANS% }
  if [ -z "$ST" ] && [ $T = closed ]; then crit "$S: no answer on UDP or TCP"
  elif [ -z "$ST" ]; then crit "$S: no UDP answer, TCP 53 open (firewall?)"
  elif [ "$ST" != NOERROR ]; then crit "$S: $Q status $ST"
  elif [ "${AN:-0}" -eq 0 ]; then crit "$S: no record for $Q"
  elif [ "${MS:-0}" -gt 1000 ]; then warn "$S: slow answer, $MS ms"
  else ok "$S: UDP $MS ms, TCP 53 $T, $Q = $ANS"; fi
  [ -z "$ST" ] && continue
  [ "$ST" = NOERROR ] && [ $T = closed ] && warn "$S: TCP 53 closed (UDP works)"
  [ -n "$ANS" ] && [ -n "$REF" ] && [ "$ANS" != "$REF" ] &&
    warn "$S answers $ANS, an earlier nameserver answered $REF"
  [ -z "$REF" ] && REF=$ANS
  for SD in $SEARCH; do
    X=$(dig @"$S" +notcp +time=2 +tries=1 "$SD" SOA | grep -o 'status: [A-Z]*')
    [ "$X" = "status: NOERROR" ] || warn "$S: search $SD: ${X:-no answer}"
  done
done

line "System resolver (what applications use)"
T0=$(date +%s%N)
IP=$(timeout 10 getent ahostsv4 "$Q" | awk '{print $1; exit}')
MS=$(( ($(date +%s%N) - T0) / 1000000 ))
if [ -z "$IP" ]; then crit "cannot resolve $Q ($MS ms)"
else
  ok "$Q = $IP ($MS ms)"
  [ $MS -gt 2000 ] && warn "slow lookup: first nameserver dead?"
  HF=$(awk -v n="$Q" '!/^#/{for(i=2;i<=NF;i++) if($i==n) print $1}' /etc/hosts)
  [ -n "$HF" ] && warn "$Q comes from /etc/hosts ($HF), not DNS"
  RV=$(getent hosts "$IP" | awk '{print $2}')
  if [ -z "$RV" ]; then echo "no reverse record for $IP"
  elif [ "${RV%%.*}" != "${Q%%.*}" ]; then warn "$IP reverses to $RV"; fi
fi

line "Result"
if [ $C -gt 0 ]; then echo -e "${R}CRIT${NC} crit=$C warn=$W"; exit 2; fi
if [ $W -gt 0 ]; then echo -e "${Y}WARN${NC} warn=$W"; exit 1; fi
echo -e "${G}OK${NC}"; exit 0
