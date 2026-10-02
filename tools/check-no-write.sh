#!/bin/bash
#==============================================================================
# check-no-write.sh  -  fail if a typed script could write a file
#
# USAGE
#   tools/check-no-write.sh            check every scripts/**/*.sh
#   tools/check-no-write.sh FILE...    check these files
#
# RULES (FOR-CLAUDE.md, 3.3)
#   Shell code, outside heredoc bodies and outside quoted strings:
#     a. no ">" or ">>" except to /dev/null or to another descriptor (>&2)
#     b. no exec N>file
#     c. none of these commands: rm rmdir mv cp mkdir touch tee truncate dd
#        install ln chmod chown mktemp shred, and no "sed -i" or "-delete"
#   Anywhere in the file, quoted or not:
#     d. no "/tmp"
#   Inside single-quoted awk programs:
#     e. no print or printf redirected with ">" or "|", no system(
#
# Heredoc bodies hold SQL; tools/check-readonly-sql.sh checks those.
# The tool is strict: a ">" used as a test inside [[ ]] or $(( )) fails.
# Write those with -gt / -lt instead.
#
# EXIT CODES
#   0 clean | 1 at least one problem | 64 bad usage
#==============================================================================
set -o pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FILES=()
for a in "$@"; do
    case "$a" in
        -h|--help) sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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
    awk -v F="$rel" '
    function fail(msg) { printf "%s:%d: FAIL %s: %s\n", F, NR, msg, $0; bad = 1 }
    # Heredoc delimiter opened on a line of shell code, or "".
    function delim_of(s,   i, r) {
        while ((i = index(s, "<<")) > 0) {
            r = substr(s, i + 2)
            if (substr(r, 1, 1) == "<") { s = substr(r, 2); continue }
            sub(/^-?[ \t]*/, "", r); gsub(/["\047]/, "", r)
            if (match(r, /^[A-Za-z_][A-Za-z0-9_]*/)) return substr(r, 1, RLENGTH)
            s = r
        }
        return ""
    }
    /\/tmp/ { fail("/tmp") }
    hd != "" { if ($0 ~ "^[ \t]*" hd "[ \t]*$") hd = ""; next }
    {
        # Split the line into code (outside quotes) and awk text (inside
        # single quotes). Single-quote state carries over lines.
        code = ""; sq = ""; dq = 0
        for (i = 1; i <= length($0); i++) {
            c = substr($0, i, 1)
            if (insq) { if (c == "\047") insq = 0; else sq = sq c; continue }
            if (dq) { if (c == "\\") i++; else if (c == "\"") dq = 0; continue }
            if (c == "\047") { insq = 1; code = code "Q"; continue }
            if (c == "\"") { dq = 1; code = code "Q"; continue }
            if (c == "#" && (i == 1 || substr($0, i - 1, 1) ~ /[ \t]/)) break
            code = code c
        }
        gsub(/"[^"]*"/, "\"\"", sq)
        if (sq ~ /print[^;}]*[>|]/ || sq ~ /system[ ]*\(/)
            fail("awk program writes or runs a command")
        d = delim_of(code)
        if (d != "") hd = d
        t = code
        gsub(/[0-9&]?>>?[ ]*\/dev\/null/, "", t)
        gsub(/[0-9]?>&[0-9-]/, "", t)
        gsub(/<<</, "", t); gsub(/<</, "", t)
        if (t ~ />/) fail("redirect to a file")
        if (code ~ /(^|[^A-Za-z0-9_-])(rm|rmdir|mv|cp|mkdir|touch|tee|truncate|dd|install|ln|chmod|chown|mktemp|shred)([ \t;|&)]|$)/)
            fail("command that writes")
        if (code ~ /sed[ \t]+(-[a-zA-Z]*[ \t]+)*-i/ || code ~ /-delete/)
            fail("sed -i or -delete")
    }
    END { exit bad }' "$f" || bad=1
done

if [ "$bad" -ne 0 ]; then echo "RESULT: FAIL"; exit 1; fi
echo "RESULT: OK (${#FILES[@]} scripts)"
exit 0
