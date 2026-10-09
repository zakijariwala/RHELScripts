#!/bin/bash
# dns-check.sh - every line of resolv.conf, every nameserver. Read-only.
# Usage: ./dns-check.sh [NAME]          Exit: 0 OK, 1 WARN, 2 CRIT
set -o pipefail

TEST_NAME=CHANGE_ME   # name every nameserver must answer
RESOLV=/etc/resolv.conf

Q=${1:-$TEST_NAME}
if [ "$Q" = CHANGE_ME ]; then
  echo "Set TEST_NAME at the top of the script, or run: $0 NAME"; exit 64
fi

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

printf "%b%s%b\n" "$B" "$RULE---" "$NC"
printf "  %-8s %s\n" Host "$(hostname)" IP "$(hostname -I | xargs)" \
  Time "$(date '+%F %T')" Query "$Q"
printf "%b%s%b\n" "$B" "$RULE---" "$NC"

line "$RESOLV"
NS=''; FIRST3=''; N=0; SEARCH=''; OPTS=''
while read -r KEY VAL REST; do
  case $KEY in
    ''|'#'*|';'*|sortlist) ;;
    nameserver) N=$((N+1)); [ $N -le 3 ] && FIRST3="$FIRST3 $VAL "
      case " $NS " in *" $VAL "*) warn resolv.conf "$VAL listed twice" ;;
                      *) NS="$NS $VAL" ;; esac ;;
    search|domain) SEARCH="$VAL${REST:+ $REST}" ;;
    options) OPTS="$VAL $REST" ;;
    *) warn resolv.conf "unknown line '$KEY' (the resolver ignores it)" ;;
  esac
done < "$RESOLV"
info Nameservers "$N:$NS"
info Search "${SEARCH:-none}"
info Options "${OPTS:-none}"
[ $N -eq 0 ] && crit resolv.conf "no nameserver line"
[ $N -gt 3 ] && warn resolv.conf "$N nameservers: only the first 3 are asked"
[ "$(wc -w <<< "$SEARCH")" -gt 6 ] && warn resolv.conf "over 6 search domains"
for OP in $OPTS; do
  case $OP in
    timeout:*) [ "${OP#*:}" -gt 5 ] && warn resolv.conf "$OP: slow failover" ;;
    attempts:*) [ "${OP#*:}" -gt 3 ] && warn resolv.conf "$OP: slow failover" ;;
  esac
done

line "Nameservers (only the first 3 are asked)"
DIG=$(command -v dig)
[ -z "$DIG" ] && warn dig "not installed: only TCP 53 tested"
FMT='  %b[%s]%b %-16s %-4s %-8s %-6s %7s  %-16s %s\n'
printf "         %-16s %-4s %-8s %-6s %7s  %-16s %s\n" \
  NAMESERVER USED UDP TCP53 TIME ANSWER NOTE
REF=''
for S in $NS; do
  case $FIRST3 in *" $S "*) USED=yes ;; *) USED=no ;; esac
  if timeout 8 nc -zv -w 3 "$S" 53 2>&1 | grep -q Connected
  then TCP=open; else TCP=closed; fi
  ST=''; MS=''; ANS=''; AN=0
  if [ -n "$DIG" ]; then
    D=$(dig @"$S" +search +notcp +time=2 +tries=1 "$Q" 2>&1)
    ST=$(echo "$D" | grep -o 'status: [A-Z]*' | cut -d' ' -f2)
    AN=$(echo "$D" | grep -o 'ANSWER: [0-9]*' | cut -d' ' -f2)
    MS=$(echo "$D" | awk '/Query time/{print $4}')
    ANS=$(echo "$D" | awk '$4=="A"{print $5}' | sort | xargs)
  fi
  L=OK; NOTE=''
  if [ -z "$DIG" ]; then [ $TCP = closed ] && L=CRIT NOTE="TCP 53 closed"
  elif [ -z "$ST" ] && [ $TCP = closed ]; then L=CRIT NOTE="no answer at all"
  elif [ -z "$ST" ]; then L=CRIT NOTE="no UDP answer (firewall?)"
  elif [ "$ST" != NOERROR ]; then L=CRIT NOTE="server says $ST"
  elif [ "${AN:-0}" -eq 0 ]; then L=CRIT NOTE="no record"
  elif [ "${MS:-0}" -gt 1000 ]; then L=WARN NOTE="slow"
  elif [ $TCP = closed ]; then L=WARN NOTE="TCP 53 closed: large answers fail"
  elif [ -n "$REF" ] && [ "$ANS" != "$REF" ]; then L=WARN NOTE="answer differs"
  fi
  [ $USED = no ] && [ $L = CRIT ] && L=WARN NOTE="$NOTE (never asked)"
  [ -z "$REF" ] && REF=$ANS
  A1=${ANS%% *}; [ "$A1" != "$ANS" ] && A1="$A1+"
  tag $L
  printf "$FMT" "$COL" "$T" "$NC" "$S" "$USED" "${ST:-none}" "$TCP" \
    "${MS:+$MS ms}" "${A1:--}" "$NOTE"
  add $L "$S" "${NOTE:-ok}"
  [ -z "$ST" ] && continue
  for SD in $SEARCH; do
    X=$(dig @"$S" +notcp +time=2 +tries=1 "$SD" SOA | grep -o 'status: [A-Z]*')
    [ "$X" = "status: NOERROR" ] || warn "$S" "search $SD: ${X:-no answer}"
  done
done

line "System resolver (what applications use)"
T0=$(date +%s%N)
IP=$(timeout 10 getent ahostsv4 "$Q" | awk '{print $1; exit}')
MS=$(( ($(date +%s%N) - T0) / 1000000 ))
if [ -z "$IP" ]; then crit Lookup "cannot resolve $Q ($MS ms)"
else
  ok Lookup "$Q = $IP ($MS ms)"
  [ $MS -gt 2000 ] && warn Lookup "slow: first nameserver dead?"
  HF=$(awk -v n="$Q" '!/^#/{for(i=2;i<=NF;i++) if($i==n) print $1}' /etc/hosts)
  [ -n "$HF" ] && warn /etc/hosts "$Q comes from /etc/hosts ($HF), not DNS"
  [ "${Q%%.*}" = "$(hostname -s)" ] &&
    info Note "this server's own name: nsswitch can answer it without DNS"
  RV=$(getent hosts "$IP" | awk '{print $2; exit}')
  if [ -z "$RV" ]; then info Reverse "no reverse record for $IP"
  elif [ "${RV%%.*}" != "${Q%%.*}" ]; then warn Reverse "$IP is $RV"
  else ok Reverse "$IP is $RV"; fi
fi

line "Summary"
if [ $C -gt 0 ]; then RC=2; OV="${R}CRIT$NC"
elif [ $W -gt 0 ]; then RC=1; OV="${Y}WARN$NC"
else RC=0; OV="${G}OK$NC"; fi
printf "  Overall  %b   (ok=%d warn=%d crit=%d)\n" "$OV" $O $W $C
[ -n "$PROB" ] && { echo "  Needs attention:"; printf "%b" "$PROB"; }
printf "%b%s%b\n" "$B" "$RULE---" "$NC"
exit $RC
