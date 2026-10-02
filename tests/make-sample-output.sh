#!/bin/bash
#==============================================================================
# make-sample-output.sh  -  rebuild scripts/oracle-rac-checklist/sample-output/
#
# Runs checklist.sh against the stubs in tests/stubs/ and the fixture in
# tests/fixtures/sample/. Touches no real server and no real database.
#
# USAGE
#   tests/make-sample-output.sh
#
# Writes checklist.csv, checklist.txt (--table) and checklist.html, each
# from its own run. Temp paths in the output are replaced with the paths a
# real install uses, so the samples match what you see on a server.
#==============================================================================
set -o pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO/scripts/oracle-rac-checklist/sample-output"
WORK=$(mktemp -d) || exit 1
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/fixtures" "$OUT"
cp "$REPO/scripts/oracle-rac-checklist/checklist.sh" "$WORK/"
cp "$REPO/tests/fixtures/sample/"* "$WORK/fixtures/"
ckpt=$(date -d '-1 min' '+%Y-%m-%d %H:%M:%S')
sed -i "s/@CKPT@/$ckpt/" "$WORK/fixtures/gg2.out"

cat > "$WORK/config.env" <<EOF
NODE2_HOST=racnode2
GG_HOST=gghost01
GRID_HOME=$REPO/tests/stubs/grid
ACTIVESESSION_SCRIPT=$REPO/tests/stubs/activesession.sh
SFTP_FILE=$WORK/fixtures/sftp_output
SERVER_FILE=$WORK/fixtures/server_checklist
LOG_DIR=$WORK/history
APP_USER=APPUSER
SUBJECT_TAG=DEMO
EOF

# Replace temp paths with the paths of a real install.
tidy() {
    sed -e "s|$WORK/config.env|/home/oracle/scripts/oracle-rac-checklist/config.env|g" \
        -e "s|$WORK/fixtures/|/home/oracle/|g"
}

run() {
    PATH="$REPO/tests/stubs/bin:$PATH" STUB_FIXTURES="$WORK/fixtures" \
        bash "$WORK/checklist.sh" --no-history "$@"
}

run              | tidy > "$OUT/checklist.csv"
run --table      | tidy > "$OUT/checklist.txt"
run --html       | tidy > "$OUT/checklist.html"
rc=$(run > /dev/null; echo $?)

echo "Wrote $OUT/checklist.{csv,txt,html} (exit code of the run: $rc)"
