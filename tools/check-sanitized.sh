#!/bin/bash
#==============================================================================
# check-sanitized.sh  -  fail if the repo contains real identifiers
#
# USAGE
#   tools/check-sanitized.sh                     scan the repo (see FILES)
#   tools/check-sanitized.sh PATH...             scan only these files/dirs
#   tools/check-sanitized.sh --show              also print each offending line
#   tools/check-sanitized.sh --help
#
# FILES
#   Default: every file git would commit: tracked files plus untracked files
#   that .gitignore does not exclude. Run it before "git add" and it still
#   sees your new files.
#
# CHECKS
#   1. IPv4 addresses. Allowed: 0.0.0.0, 127.0.0.1 and the documentation
#      ranges 192.0.2.x, 198.51.100.x, 203.0.113.x (RFC 5737).
#   2. Email addresses. Allowed: example.com, example.org, example.net and
#      their subdomains, a domain ending .example, .invalid or .test, and
#      git@github.com.
#   3. Ports other than 22, written as PORT=N, NODE2_PORT=N, port N,
#      port: N, ansible_port: N, -o Port=N, ssh -p N, scp -P N.
#   4. Internal host names ending .corp .local .lan .internal .intra
#      .intranet .localdomain (localhost.localdomain is allowed).
#   Banned names (employer, people, hosts, databases) are a separate check:
#   tools/check-banned.sh, which compares hashes.
#
#   A line containing the marker  sanitize:allow  skips checks 1-4. Use it
#   only for generic values a reviewer can confirm by eye.
#
# OUTPUT
#   One line per hit:  FILE:LINE: FAIL <check>
#   The offending text is NOT printed unless you pass --show, because CI
#   logs of a public repo are public. Run --show only on your own machine.
#
# EXIT CODES
#   0 clean | 1 at least one hit | 64 bad usage
#==============================================================================
set -o pipefail

usage() { sed -n '2,49p' "$0" | sed 's/^# \{0,1\}//'; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SHOW=0; PATHS=()

for arg in "$@"; do
    case "$arg" in
        --show)                SHOW=1 ;;
        -h|--help)             usage; exit 0 ;;
        -*)                    echo "Unknown option: $arg (try --help)" >&2; exit 64 ;;
        *)                     PATHS+=("$arg") ;;
    esac
done

#--------------------------------- file list ----------------------------------
LIST=$(mktemp) || exit 1
HITS=$(mktemp) || exit 1
trap 'rm -f "$LIST" "$HITS"' EXIT

if [ "${#PATHS[@]}" -gt 0 ]; then
    for p in "${PATHS[@]}"; do
        if [ -d "$p" ]; then
            find "$p" -type d -name .git -prune -o -type f -print0
        elif [ -f "$p" ]; then
            printf '%s\0' "$p"
        else
            echo "Not found: $p" >&2; exit 64
        fi
    done > "$LIST"
elif git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    (cd "$ROOT" && git ls-files -z -co --exclude-standard) |
        while IFS= read -r -d '' f; do
            [ -f "$ROOT/$f" ] && printf '%s\0' "$ROOT/$f"
        done > "$LIST"
else
    find "$ROOT" -type d -name .git -prune -o -type f -print0 > "$LIST"
fi

NFILES=$(tr -cd '\0' < "$LIST" | wc -c)
if [ "$NFILES" -eq 0 ]; then
    echo "No files to scan."; echo "RESULT: OK (0 files)"; exit 0
fi

# grep_all OPTIONS... : grep every file in the list, never fail on "no match"
grep_all() { xargs -0 grep -HnI "$@" < "$LIST" 2>/dev/null; true; }

# Lines carrying the exemption marker, as FILE:LINE
ALLOWED=$(grep_all -F 'sanitize:allow' | cut -d: -f1,2)

# hit FILE LINE CHECK : record one finding unless the line is exempt
hit() {
    if grep -qxF -- "$1:$2" <<< "$ALLOWED"; then return; fi
    printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$HITS"
}

#--------------------------------- 1. IPv4 ------------------------------------
while IFS=: read -r f n ip; do
    if awk -v ip="$ip" 'BEGIN {
            split(ip, o, "."); for (i = 1; i <= 4; i++) if (o[i] + 0 > 255) exit 1
            if (ip == "0.0.0.0" || ip == "127.0.0.1") exit 1
            if (ip ~ /^(192\.0\.2|198\.51\.100|203\.0\.113)\./) exit 1
            exit 0 }'; then
        hit "$f" "$n" "IPv4 address"
    fi
done < <(grep_all -oP '(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])')

#--------------------------------- 2. Email -----------------------------------
while IFS=: read -r f n addr; do
    dom="${addr#*@}"; dom="${dom,,}"
    case "$addr" in git@github.com) continue ;; esac
    case "$dom" in
        example.com|example.org|example.net|*.example.com|*.example.org|*.example.net|*.example|*.invalid|*.test) continue ;;
    esac
    hit "$f" "$n" "email address"
done < <(grep_all -oP '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}')

#--------------------------------- 3. Ports -----------------------------------
while IFS=: read -r f n port; do
    [ "$port" = 22 ] && continue
    hit "$f" "$n" "port other than 22"
done < <(
    grep_all -oiP '(?:\b|_)port["'\'']?[ \t]*[=:]?[ \t]*["'\'']?\K\d+\b'
    grep_all -oP '(?<=[ \t])-[pP][ \t]*\K\d+\b'
)

#------------------------------ 4. Host names ---------------------------------
while IFS=: read -r f n name; do
    [ "${name,,}" = localhost.localdomain ] && continue
    hit "$f" "$n" "internal host name"
done < <(grep_all -oiP '\b[a-z0-9][a-z0-9-]*(?:\.[a-z0-9-]+)*\.(?:corp|local|lan|internal|intra|intranet|localdomain)\b(?![.-])')

#--------------------------------- report -------------------------------------
NHITS=0
if [ -s "$HITS" ]; then
    sort -u "$HITS" | sort -t$'\t' -k1,1 -k2,2n | while IFS=$'\t' read -r f n what; do
        rel="${f#"$ROOT"/}"
        printf '%s:%s: FAIL %s\n' "$rel" "$n" "$what"
        if [ "$SHOW" = 1 ] && [ "$n" != 0 ]; then
            printf '    %s\n' "$(sed -n "${n}p" "$f")"
        fi
    done
    NHITS=$(sort -u "$HITS" | wc -l)
fi

rc=0
if [ "$NHITS" -gt 0 ]; then rc=1; fi

if [ "$rc" -eq 0 ]; then
    echo "RESULT: OK ($NFILES files)"
else
    echo "RESULT: FAIL ($NHITS hits in $NFILES files)"
fi
exit "$rc"
