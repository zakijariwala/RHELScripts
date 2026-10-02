#!/bin/bash
#==============================================================================
# sync-shared.sh  -  copy the shared sections into every typed script
#
# USAGE
#   tools/sync-shared.sh            rewrite scripts in place
#   tools/sync-shared.sh --check    change nothing; exit 1 if any differ
#
# Masters live in tools/shared/<name>.sh. Each starts with its own marker
# line, for example "#== S02 helpers". In every script under scripts/, a
# section whose marker line equals a master's marker line is replaced by
# that master, up to the next "#== S" marker.
#
# --check also fails when a script lacks one of the required sections
# (helpers, output, config, options) or a master is over 25 lines.
#
# EXIT CODES
#   0 in sync | 1 differences or problems found | 64 bad usage
#==============================================================================
set -o pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SHARED="$ROOT/tools/shared"
REQUIRED="helpers output config options"
CHECK=0
case "${1:-}" in
    "") ;;
    --check) CHECK=1 ;;
    -h|--help) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 64 ;;
esac

bad=0
for m in "$SHARED"/*.sh; do
    n=$(wc -l < "$m")
    if [ "$n" -gt 25 ]; then
        echo "FAIL ${m#"$ROOT"/}: $n lines, limit 25"; bad=1
    fi
done

# sync_one FILE : print FILE with every shared section replaced by its master
sync_one() {
    awk -v dir="$SHARED" '
    function load(name,   f, line, txt) {
        f = dir "/" name ".sh"; txt = ""
        while ((getline line < f) > 0) txt = txt line "\n"
        close(f); return txt
    }
    /^#== S[0-9]+ / {
        skip = 0
        name = $3
        m = load(name)
        if (m != "") {
            split(m, first, "\n")
            if (first[1] == $0) { printf "%s", m; skip = 1; next }
        }
    }
    !skip { print }' "$1"
}

while IFS= read -r f; do
    rel="${f#"$ROOT"/}"
    for r in $REQUIRED; do
        grep -q "^#== S[0-9]* $r\$" "$f" || {
            echo "FAIL $rel: missing shared section \"$r\""; bad=1; }
    done
    new=$(sync_one "$f")
    if [ "$new" != "$(cat "$f")" ]; then
        if [ "$CHECK" = 1 ]; then
            echo "FAIL $rel: shared sections differ from tools/shared/"
            diff <(printf '%s\n' "$new") "$f" | head -20
            bad=1
        else
            printf '%s\n' "$new" > "$f"
            echo "updated $rel"
        fi
    fi
done < <(find "$ROOT/scripts" -name '*.sh' -not -path '*/_template/*' | sort)

if [ "$bad" -ne 0 ]; then echo "RESULT: FAIL"; exit 1; fi
echo "RESULT: OK"
exit 0
