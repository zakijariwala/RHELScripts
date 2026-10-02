#!/bin/bash
#==============================================================================
# install-hooks.sh  -  turn on the repo's pre-commit hook in this clone
#
# USAGE
#   tools/install-hooks.sh              install, then report what is missing
#   tools/install-hooks.sh --uninstall  turn the hook off again
#   tools/install-hooks.sh --help
#
# WHAT IT CHANGES
#   One git setting in this clone only (.git/config):
#     core.hooksPath = tools/git-hooks
#   Git then runs tools/git-hooks/pre-commit before every commit. Pulling a
#   newer version of the hook needs no reinstall.
#
# EXIT CODES
#   0 installed and every prerequisite found
#   1 installed, but a prerequisite is missing (the hook will block commits
#     until you add it)
#   64 bad usage, or not inside a clone of this repo
#==============================================================================
set -o pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "Run this from inside your clone of the repo." >&2; exit 64; }
cd "$ROOT" || exit 64

case "${1:-}" in
    "") ;;
    --uninstall)
        git config --unset core.hooksPath
        echo "Hook turned off. core.hooksPath removed."
        exit 0 ;;
    -h|--help) sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 64 ;;
esac

chmod +x tools/git-hooks/pre-commit tools/check-sanitized.sh tools/check-readonly-sql.sh
git config core.hooksPath tools/git-hooks
echo "OK   hook installed: core.hooksPath = $(git config core.hooksPath)"

rc=0
if command -v gitleaks >/dev/null; then
    echo "OK   gitleaks found: $(command -v gitleaks)"
else
    echo "MISSING gitleaks. Install it: docs/pre-commit-hook.md, step 2."; rc=1
fi
if [ -r tools/banned-terms.txt ] &&
   grep -qv -e '^[[:space:]]*#' -e '^[[:space:]]*$' tools/banned-terms.txt; then
    echo "OK   banned-terms list found: tools/banned-terms.txt"
else
    echo "MISSING tools/banned-terms.txt. Create it: docs/safety.md, section \"The banned-terms list\"."; rc=1
fi
exit "$rc"
