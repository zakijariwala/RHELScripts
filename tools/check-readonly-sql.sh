#!/bin/bash
#==============================================================================
# check-readonly-sql.sh  -  fail if monitoring SQL could change the database
#
# USAGE
#   tools/check-readonly-sql.sh            scan the default set (see below)
#   tools/check-readonly-sql.sh FILE...    scan only these files
#   tools/check-readonly-sql.sh --help
#
# DEFAULT SET
#   Every *.sh and *.sql file under scripts/, except scripts/actions/.
#
# WHAT COUNTS AS SQL
#   1. A heredoc opened on a line that runs sqlplus:
#          out=$(sqlplus -s / as sysdba <<EOF
#   2. A heredoc whose delimiter contains "SQL" (EOSQL, SQL, END_SQL ...):
#          sql_rman=$(cat <<EOSQL
#   3. The whole of a *.sql file.
#   Write every SQL heredoc one of these two ways, or this tool cannot see it.
#
# RULES (each break is reported with file and line)
#   a. Lines starting with "--" are SQL comments and are skipped.
#      Lines holding only a shell variable ($sql_rman) are skipped; the
#      heredoc that fills that variable is scanned on its own.
#   b. Every statement must start with SELECT or WITH (SQL), or SET or EXIT
#      (SQL*Plus). Anything else fails: INSERT, BEGIN, @script, HOST, SPOOL,
#      a lone "/", and so on.
#   c. SET TRANSACTION, SET ROLE and SET CONSTRAINT(S) fail.
#   d. No line may contain a write keyword as a whole word:
#      INSERT UPDATE DELETE MERGE DROP TRUNCATE ALTER CREATE GRANT REVOKE
#      EXEC EXECUTE BEGIN COMMIT ROLLBACK PURGE SHUTDOWN STARTUP KILL
#      FLASHBACK CALL LOCK, or anything starting DBMS_.
#      This also catches SELECT ... FOR UPDATE.
#   e. A shell line that runs sqlplus fails unless it opens a SQL heredoc
#      itself or reads from a group closed by "} |" on the same or the line
#      before: { printf 'DEFINE ...'; cat <<'SQL' ... SQL } | sqlplus
#   f. printf in a script may print only DEFINE lines (format 'DEFINE ...').
#   g. Every call of the sql helper (a line starting "sql ") must reach a
#      <<'SQL' heredoc, directly or through "\" line continuations.
#   h. In SQL, "&" only starts a substitution variable (&name), and
#      SET DEFINE is not allowed (substitution must stay on).
#
# The tool is strict on purpose. A keyword inside a string literal or an
# inline comment still fails. Reword the SQL; do not weaken the tool.
#
# LIMITS
#   SQL built in a shell string (sql="SELECT ...") is not scanned.
#   Scripts called by a monitoring script (gg2.sh, activesession.sh) are not
#   scanned unless you pass them as FILE arguments. See docs/safety.md.
#
# EXIT CODES
#   0 clean | 1 at least one problem | 64 bad usage
#==============================================================================
set -o pipefail

usage() { sed -n '2,53p' "$0" | sed 's/^# \{0,1\}//'; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FILES=()

for arg in "$@"; do
    case "$arg" in
        -h|--help) usage; exit 0 ;;
        -*)        echo "Unknown option: $arg (try --help)" >&2; exit 64 ;;
        *)         FILES+=("$arg") ;;
    esac
done

if [ "${#FILES[@]}" -eq 0 ]; then
    while IFS= read -r f; do FILES+=("$f"); done < <(
        find "$ROOT/scripts" -type f \( -name '*.sh' -o -name '*.sql' \) \
             -not -path "$ROOT/scripts/actions/*" 2>/dev/null | sort)
fi

for f in "${FILES[@]}"; do
    if [ ! -r "$f" ]; then echo "Cannot read: $f" >&2; exit 64; fi
done

if [ "${#FILES[@]}" -eq 0 ]; then
    echo "No files to scan."
    echo "RESULT: OK (0 files)"
    exit 0
fi

# One awk pass per file. Portable awk only (RHEL gawk and Ubuntu mawk).
scan() {                        # scan PATH DISPLAY_NAME IS_SQL_FILE
    awk -v FILE="$2" -v ISSQL="$3" '
    function trim(s) { sub(/^[ \t\r]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
    function problem(msg) {
        printf "%s:%d: FAIL %s: %s\n", FILE, NR, msg, trim($0); bad++
    }
    # Delimiter of a heredoc opened on this line, or "" if none.
    function heredoc_delim(s,   i, rest, d) {
        while ((i = index(s, "<<")) > 0) {
            rest = substr(s, i + 2)
            if (substr(rest, 1, 1) == "<") { s = substr(rest, 2); continue }   # <<< herestring
            if (substr(rest, 1, 1) == "-") rest = substr(rest, 2)
            sub(/^[ \t]*/, "", rest)
            gsub(/["\047\\]/, "", rest)
            if (match(rest, /^[A-Za-z_][A-Za-z0-9_]*/)) return substr(rest, 1, RLENGTH)
            s = rest
        }
        return ""
    }
    function split_unquoted(s, out,   i, c, n, cur) {
        n = 0; cur = ""
        for (i = 1; i <= length(s); i++) {
            c = substr(s, i, 1)
            if (c == "\047") in_quote = !in_quote
            if (c == ";" && !in_quote) { out[++n] = cur; cur = "" } else cur = cur c
        }
        out[++n] = cur
        return n
    }
    function runs_sqlplus(s) { return s ~ /(^|[ \t;|&(`])sqlplus[ \t]+-/ }

    # Check one SQL line against rules a-d.
    function check_sql(line,   t, up, n, segs, k, seg, w, kw, i) {
        t = trim(line)
        if (t == "" || t ~ /^--/) return
        if (t ~ /^\$\{?[A-Za-z_][A-Za-z0-9_]*\}?$/) return
        up = toupper(t)
        for (i = 1; i <= NKW; i++) {
            kw = KW[i]
            if (up ~ ("(^|[^A-Z0-9_$#])" kw "([^A-Z0-9_$#]|$)")) problem("write keyword " kw)
        }
        if (up ~ /(^|[^A-Z0-9_$#])DBMS_/) problem("write keyword DBMS_")
        amp = t; gsub(/&[a-z_][a-z0-9_]*/, "", amp)
        if (amp ~ /&/) problem("& that is not a substitution variable")
        if (up ~ /^SET[ \t].*DEFINE/) problem("SET DEFINE (keep DEFINE on)")

        # Statement starts. A line may hold several statements split by ";".
        # A ";" inside a quoted string does not split.
        n = split_unquoted(up, segs)
        for (k = 1; k <= n; k++) {
            seg = trim(segs[k])
            if (seg != "" && !in_stmt) {
                w = seg; sub(/[ \t(].*$/, "", w)
                if (w == "SELECT" || w == "WITH") { cnt[w]++; in_stmt = 1 }
                else if (w == "SET") {
                    cnt[w]++
                    if (seg ~ /^SET[ \t]+(TRANSACTION|ROLE|CONSTRAINTS?)([ \t]|$)/) problem("SET that changes session state")
                }
                else if (w == "EXIT" || w == "QUIT") cnt["EXIT"]++
                else problem("statement starts with \"" w "\" (allowed: SELECT WITH SET EXIT)")
            }
            if (k < n) in_stmt = 0          # a ";" ended the statement
        }
    }

    BEGIN {
        NKW = split("INSERT UPDATE DELETE MERGE DROP TRUNCATE ALTER CREATE GRANT REVOKE EXEC EXECUTE BEGIN COMMIT ROLLBACK PURGE SHUTDOWN STARTUP KILL FLASHBACK CALL LOCK", KW, " ")
        bad = 0; in_stmt = 0; in_quote = 0; delim = ""; capture = 0
    }

    ISSQL == 1 { check_sql($0); next }

    # Inside a heredoc body
    delim != "" {
        if (trim($0) == delim) { delim = ""; capture = 0; in_stmt = 0; in_quote = 0; next }
        if (capture) check_sql($0)
        next
    }

    # Shell line
    {
        if ($0 ~ /^[ \t]*#/) next                 # shell comment, incl. #~ struck-out v1 lines
        code = $0; sub(/[ \t]#.*$/, "", code)    # drop a trailing shell comment
        d = heredoc_delim(code)
        # A call of the sql() helper must feed it a SQL heredoc.
        if (code ~ /^[ \t]*sql[ \t]/) sqlcall = 1
        if (sqlcall) {
            if (d != "" && toupper(d) ~ /SQL/) sqlcall = 0
            else if (code !~ /\\$/) { problem("sql called without a <<\047SQL\047 heredoc"); sqlcall = 0 }
        }
        # printf may feed sqlplus DEFINE lines only.
        if (code ~ /printf[ \t]+\047[A-Z]/ && code !~ /printf[ \t]+\047DEFINE /)
            problem("printf of a SQL*Plus command other than DEFINE")
        grouped = (code ~ /\}[ \t]*\|/ || prev ~ /\}[ \t]*\|/)
        prev = code
        if (d != "") {
            delim = d
            capture = (runs_sqlplus(code) || toupper(d) ~ /SQL/)
            if (capture) heredocs++
            next
        }
        if (runs_sqlplus(code) && !grouped)
            problem("sqlplus fed by something other than a { DEFINE; heredoc } group")
    }

    END {
        if (heredocs > 0 || ISSQL == 1)
            printf "%s: %d SELECT, %d WITH, %d SET, %d EXIT\n", FILE, cnt["SELECT"], cnt["WITH"], cnt["SET"], cnt["EXIT"]
        exit (bad > 0)
    }' "$1"
}

total_bad=0
for f in "${FILES[@]}"; do
    rel="${f#"$ROOT"/}"
    case "$f" in *.sql) sqlfile=1 ;; *) sqlfile=0 ;; esac
    if ! scan "$f" "$rel" "$sqlfile"; then
        total_bad=$((total_bad + 1))
    fi
done

if [ "$total_bad" -gt 0 ]; then
    echo "RESULT: FAIL ($total_bad of ${#FILES[@]} files have problems)"
    exit 1
fi
echo "RESULT: OK (${#FILES[@]} files)"
exit 0
