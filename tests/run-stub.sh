#!/bin/bash
#==============================================================================
# run-stub.sh  -  run one typed script against the stubs, never a real server
#
# USAGE
#   tests/run-stub.sh NAME [FIXTURE] [-- SCRIPT OPTIONS...]
#   tests/run-stub.sh db-check
#   tests/run-stub.sh node-check sample -- --check-config
#
# Copies scripts/oracle-rac/NAME/NAME.sh and the fixture's config/NAME.env
# into a temp folder, fills @GRID@, @WORK@, @STUBS@ and @CKPT@, puts
# tests/stubs/bin first on PATH, runs the script and prints its output.
# The exit code is the script's exit code. TIDY=1 rewrites temp paths to
# the paths of a real install, for sample output.
#==============================================================================
set -o pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
name="$1"; shift
fixture=sample
if [ $# -gt 0 ] && [ "$1" != -- ]; then fixture="$1"; shift; fi
[ "${1:-}" = -- ] && shift
src="$REPO/scripts/oracle-rac/$name/$name.sh"
fx="$REPO/tests/fixtures/$fixture"
[ -r "$src" ] || { echo "no script $src" >&2; exit 64; }
WORK=$(mktemp -d) || exit 1
trap 'rm -rf "$WORK"' EXIT
cp "$src" "$WORK/"
cp "$fx"/* "$WORK/" 2>/dev/null
ckpt=$(date -d '-1 min' '+%Y-%m-%d %H:%M:%S')
sed -i "s/@CKPT@/$ckpt/" "$WORK/gg2.out" 2>/dev/null
if [ -r "$fx/config/$name.env" ]; then
    sed -e "s|@GRID@|$REPO/tests/stubs/grid|; s|@WORK@|$WORK|" \
        -e "s|@STUBS@|$REPO/tests/stubs|" "$fx/config/$name.env" > "$WORK/config.env"
fi
# Re-align a table after tidy changed path lengths. CSV passes through.
realign() {
    local all
    all=$(cat)
    case "$all" in
        \"*) printf '%s\n' "$all" ;;
        *) printf '%s\n' "$all" | sed -E 's/ {2,}/|/g; s/ +$//' | column -t -s '|' ;;
    esac
}
tidy() {
    if [ "${TIDY:-0}" = 1 ]; then
        sed -e "s|$REPO/tests/stubs/grid|/u01/app/19.0.0/grid|g" \
            -e "s|$REPO/tests/stubs|/home/oracle/scripts|g" \
            -e "s|$WORK/config.env|/home/oracle/scripts/oracle-rac/$name/config.env|g" \
            -e "s|$WORK|/home/oracle|g" | realign
    else cat; fi
}
PATH="$REPO/tests/stubs/bin:$PATH" STUB_FIXTURES="$WORK" \
    bash "$WORK/$name.sh" "$@" < /dev/null 2>&1 | tidy
exit "${PIPESTATUS[0]}"
