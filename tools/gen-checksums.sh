#!/bin/bash
#==============================================================================
# gen-checksums.sh  -  write the checksum table into each script's README
#
# USAGE
#   tools/gen-checksums.sh            rewrite every table
#   tools/gen-checksums.sh --check    change nothing; exit 1 if a table is
#                                     stale or missing
#
# For each scripts/**/NAME.sh it computes one hash for the whole file and
# one per section ("#== Snn name"), with exactly the two commands a fresher
# types (docs/typing-guide.md):
#
#   awk '{gsub(/\r/,"")}NF{$1=$1;print}' FILE | sha256sum | cut -c1-12
#   awk 'BEGIN{printf "S00 "}{gsub(/\r/,"")}NF{$1=$1}/^#== S/{close(c);
#        printf "%s %s ",$2,$3}NF{print|(c="sha256sum|cut -c1-12")}
#        END{close(c)}' FILE                       (one line when typed)
#
# Normalization: carriage returns deleted, blank lines dropped, every run of
# spaces and tabs squeezed to one space, both ends of each line trimmed.
# Indentation does not change a hash; a missing or extra space between two
# words does.
#
# The table goes into README.md in the script's folder, between the lines
#   <!-- checksums:start -->  and  <!-- checksums:end -->
#
# EXIT CODES
#   0 all tables current | 1 stale or missing table | 64 bad usage
#==============================================================================
set -o pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK=0
case "${1:-}" in
    "") ;;
    --check) CHECK=1 ;;
    -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 64 ;;
esac

whole() { awk '{gsub(/\r/,"")}NF{$1=$1;print}' "$1" | sha256sum | cut -c1-12; }
sections() {
    awk 'BEGIN{printf "S00 "}{gsub(/\r/,"")}NF{$1=$1}/^#== S/{close(c);printf "%s %s ",$2,$3}NF{print|(c="sha256sum|cut -c1-12")}END{close(c)}' "$1"
}

table() {                       # table SCRIPT -> markdown block
    local f="$1" v
    v=$(awk -F= '/^VERSION=/ { print $2; exit }' "$f")
    echo "<!-- checksums:start -->"
    echo "\`$(basename "$f")\` version $v, $(wc -l < "$f") lines."
    echo
    echo "| Part | Hash |"
    echo "|---|---|"
    echo "| whole file | \`$(whole "$f")\` |"
    sections "$f" | awk '{ h = $NF; $NF = ""; sub(/ $/, ""); printf "| %s | `%s` |\n", $0, h }'
    echo "<!-- checksums:end -->"
}

bad=0
while IFS= read -r f; do
    readme="$(dirname "$f")/README.md"
    rel="${readme#"$ROOT"/}"
    if [ ! -f "$readme" ] || ! grep -q '^<!-- checksums:start -->$' "$readme" ||
       ! grep -q '^<!-- checksums:end -->$' "$readme"; then
        echo "FAIL $rel: missing, or no checksums:start / checksums:end markers"
        bad=1; continue
    fi
    new=$(awk -v tbl="$(table "$f")" '
        /^<!-- checksums:start -->$/ { print tbl; skip = 1; next }
        /^<!-- checksums:end -->$/ { skip = 0; next }
        !skip { print }' "$readme")
    if [ "$new" != "$(cat "$readme")" ]; then
        if [ "$CHECK" = 1 ]; then
            echo "FAIL $rel: checksum table is stale; run tools/gen-checksums.sh"
            bad=1
        else
            printf '%s\n' "$new" > "$readme"
            echo "updated $rel"
        fi
    fi
done < <(find "$ROOT/scripts" -name '*.sh' -not -path '*/_template/*' | sort)

if [ "$bad" -ne 0 ]; then echo "RESULT: FAIL"; exit 1; fi
echo "RESULT: OK"
exit 0
