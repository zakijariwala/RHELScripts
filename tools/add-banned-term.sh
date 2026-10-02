#!/bin/bash
#==============================================================================
# add-banned-term.sh  -  add banned names to tools/banned-terms.sha256
#
# USAGE
#   tools/add-banned-term.sh
#
# Asks for one term at a time with hidden input (read -s). Each term is
# lowercased, hashed with SHA-256, and only the hash is appended. The term
# never reaches a file, the screen or the shell history. Press Enter on an
# empty prompt to finish.
#
# A term may hold only a-z, 0-9, ".", "_" and "-", at least 3 characters,
# because tools/check-banned.sh splits text at every other character. For
# a two-word name, add each word on its own.
#
# If the terminal cannot take input (for example inside an automated
# session), compute the hash on any Linux machine instead and hand over
# only the hash:
#   read -rs t; printf '%s' "${t,,}" | sha256sum | cut -c1-64
#==============================================================================
set -o pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HASHES="$ROOT/tools/banned-terms.sha256"
added=0
while true; do
    printf 'Term (Enter to finish): ' >&2
    IFS= read -rs t || break
    echo >&2
    [ -z "$t" ] && break
    t="${t,,}"
    if ! [[ $t =~ ^[a-z0-9._-]{3,}$ ]]; then
        echo "Rejected: use 3+ characters from a-z 0-9 . _ - only" >&2
        continue
    fi
    printf '%s' "$t" | sha256sum | cut -c1-64 >> "$HASHES"
    added=$((added + 1))
    t=''
done
if [ -f "$HASHES" ]; then
    sort -u -o "$HASHES" "$HASHES"
fi
echo "Added $added hash(es). Run tools/check-banned.sh next." >&2
