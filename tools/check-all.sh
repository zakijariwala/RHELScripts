#!/bin/bash
#==============================================================================
# check-all.sh  -  every repo check, in one run. The pre-commit hook and CI
#                  both run exactly this.
#
# USAGE
#   tools/check-all.sh
#
# CHECKS
#   1. shellcheck        every .sh file, the hook and the test stubs
#   2. check-budget      typing budget: 200 lines, 80 columns, ASCII, no
#                        tabs, backticks, backslash-dollar, l/O/I, markers
#   3. check-no-write    typed scripts write no files
#   4. check-readonly-sql  SQL is SELECT/WITH/SET/EXIT, DEFINE rules
#   5. check-sanitized   no IPv4, email, port other than 22, internal host
#   6. check-banned      no banned term (hashed list)
#   7. sync-shared       shared sections identical to tools/shared/
#   8. gen-checksums     every README checksum table current
#
# A missing tool (shellcheck, python3) is a failure, never a skip.
#
# EXIT CODES
#   0 every check passed | 1 at least one failed
#==============================================================================
set -o pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
failed=()

step() {                        # step NAME COMMAND...
    local name="$1"; shift
    echo "=== $name"
    if "$@"; then echo "--- $name: OK"; else echo "--- $name: FAILED"; failed+=("$name"); fi
}

shellcheck_all() {
    command -v shellcheck >/dev/null || { echo "FAIL shellcheck not installed"; return 1; }
    # tools/shared/ holds fragments; they are checked inside every script.
    find scripts tools tests -name '*.sh' -not -path 'tools/shared/*' -print0 |
        xargs -0 shellcheck .githooks/pre-commit tests/stubs/bin/* tests/stubs/grid/bin/*
}

step shellcheck          shellcheck_all
step check-budget        tools/check-budget.sh
step check-no-write      tools/check-no-write.sh
step check-readonly-sql  tools/check-readonly-sql.sh
step check-sanitized     tools/check-sanitized.sh
step check-banned        tools/check-banned.sh
step sync-shared         tools/sync-shared.sh --check
step gen-checksums       tools/gen-checksums.sh --check

echo
if [ "${#failed[@]}" -gt 0 ]; then
    echo "RESULT: FAIL (${failed[*]})"; exit 1
fi
echo "RESULT: OK (8 checks)"
exit 0
