#!/bin/bash
#==============================================================================
# make-samples.sh  -  refresh the sample output blocks in every script README
#
# USAGE
#   tests/make-samples.sh
#
# Runs each script under scripts/oracle-rac/ twice against the stubs and the
# "sample" fixture (tests/run-stub.sh): once with --check-config, once
# plain. The output replaces the text between
#   <!-- sample:check-config:start --> / <!-- sample:check-config:end -->
#   <!-- sample:run:start -->          / <!-- sample:run:end -->
# in the script's README.md. Temp paths become the paths of a real install.
#==============================================================================
set -o pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"

fill() {                        # fill README TAG TEXT
    local block
    local fence='```'
    block=$(printf '%s\n%s\n%s' "$fence" "$3" "$fence")
    awk -v tag="$2" -v txt="$block" '
        $0 == "<!-- sample:" tag ":start -->" { print; print txt; skip = 1; next }
        $0 == "<!-- sample:" tag ":end -->" { skip = 0 }
        !skip { print }' "$1" > "$1.new" && mv "$1.new" "$1"
}

for dir in "$REPO"/scripts/*/*/; do
    name=$(basename "$dir")
    [ -f "$dir/$name.sh" ] || continue
    fill "$dir/README.md" check-config \
        "$(TIDY=1 "$REPO/tests/run-stub.sh" "$name" sample -- --check-config)"
    fill "$dir/README.md" run "$(TIDY=1 "$REPO/tests/run-stub.sh" "$name" sample)"
    echo "updated ${dir#"$REPO"/}README.md"
done
