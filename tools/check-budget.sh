#!/bin/bash
#==============================================================================
# check-budget.sh  -  enforce the typing budget on every typed script
#
# USAGE
#   tools/check-budget.sh            check every scripts/**/*.sh
#   tools/check-budget.sh FILE...    check these files
#
# RULES (FOR-CLAUDE.md, 3.4)
#   - at most 200 lines, at most 80 characters per line
#   - ASCII only, no tabs, no backticks, no backslash-dollar
#   - no variable named l, O or I
#   - line 1 is #!/bin/bash, line 2 is "#== S01 settings"
#   - section markers "#== Snn name" numbered 01, 02, 03... in order
#   - at most one comment line per section (markers and line 1 excluded)
#   - a VERSION= line in section S01
#
# EXIT CODES
#   0 all within budget | 1 at least one break | 64 bad usage
#==============================================================================
set -o pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FILES=()
for a in "$@"; do
    case "$a" in
        -h|--help) sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "Unknown option: $a" >&2; exit 64 ;;
        *) FILES+=("$a") ;;
    esac
done
if [ "${#FILES[@]}" -eq 0 ]; then
    while IFS= read -r f; do FILES+=("$f"); done < <(
        find "$ROOT/scripts" -name '*.sh' -not -path '*/_template/*' | sort)
fi
if [ "${#FILES[@]}" -eq 0 ]; then
    echo "FAIL no scripts found under scripts/"; exit 1
fi

bad=0
for f in "${FILES[@]}"; do
    rel="${f#"$ROOT"/}"
    LC_ALL=C awk -v F="$rel" '
    function fail(msg) { printf "%s:%d: FAIL %s\n", F, NR, msg; bad = 1 }
    NR == 1 && $0 != "#!/bin/bash" { fail("line 1 must be #!/bin/bash") }
    NR == 2 && $0 != "#== S01 settings" { fail("line 2 must be #== S01 settings") }
    length($0) > 80        { fail("line is " length($0) " characters, limit 80") }
    /[^\001-\177]/         { fail("non-ASCII character") }
    /\t/                   { fail("tab character") }
    /`/                    { fail("backtick") }
    /\\\$/                 { fail("backslash-dollar") }
    /(^|[^A-Za-z0-9_$.])(l|O|I)[ ]*=([^=]|$)/ ||
    /\$\{?(l|O|I)([^A-Za-z0-9_]|$)/ ||
    /(for|local|read)[^;|]*[ ](l|O|I)([ ;]|$)/ { fail("variable named l, O or I") }
    /^#== S[0-9][0-9] [a-z]/ {
        n++
        want = sprintf("%02d", n)
        if (substr($2, 2) != want) fail("section number " $2 ", expected S" want)
        comments = 0; sect = $2; next
    }
    NR > 1 && /^[ ]*#/ {
        if (++comments > 1) fail("second comment line in section " sect)
    }
    sect == "S01" && /^VERSION=/ { version = 1 }
    END {
        if (NR > 200) { printf "%s: FAIL %d lines, limit 200\n", F, NR; bad = 1 }
        if (!version) { printf "%s: FAIL no VERSION= line in S01\n", F; bad = 1 }
        exit bad
    }' "$f" || bad=1
done

if [ "$bad" -ne 0 ]; then echo "RESULT: FAIL"; exit 1; fi
echo "RESULT: OK (${#FILES[@]} scripts)"
exit 0
