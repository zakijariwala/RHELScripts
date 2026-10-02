#!/bin/bash
#==============================================================================
# check-banned.sh  -  fail if any file holds a banned name, compared by hash
#
# USAGE
#   tools/check-banned.sh            scan every file git would commit
#   tools/check-banned.sh PATH...    scan these files or folders
#
# The banned names (employer, people, real hosts, databases, schemas) are
# stored only as SHA-256 hashes in tools/banned-terms.sha256, one per line.
# Add one with tools/add-banned-term.sh.
#
# HOW IT MATCHES
#   Each file is lowercased and split into tokens at every character
#   outside [a-z0-9._-]. Each token is hashed, and so is each part of it
#   split at ".", "_" and "-". "dbhost01.prod.example" checks
#   "dbhost01.prod.example", "dbhost01", "prod" and "example". File paths are
#   checked the same way. A term with a space in it can never match: add
#   each word on its own.
#
# OUTPUT
#   FILE:LINE: FAIL banned term. Never the term itself.
#
# LIMIT
#   Hashes hide the list from casual readers only. Anyone who guesses a
#   candidate name can hash it and test it against the file.
#
# EXIT CODES
#   0 clean | 1 a banned term found, or the hash file missing or empty
#   64 bad usage
#==============================================================================
set -o pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HASHES="$ROOT/tools/banned-terms.sha256"
case "${1:-}" in
    -h|--help) sed -n '2,31p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "Unknown option: $1" >&2; exit 64 ;;
esac

if [ ! -r "$HASHES" ]; then
    echo "FAIL ${HASHES#"$ROOT"/} missing"; echo "RESULT: FAIL"; exit 1
fi
if ! grep -qE '^[0-9a-f]{64}$' "$HASHES"; then
    echo "FAIL ${HASHES#"$ROOT"/} holds no hashes"; echo "RESULT: FAIL"; exit 1
fi
if grep -nvE '^[0-9a-f]{64}$' "$HASHES"; then
    echo "FAIL ${HASHES#"$ROOT"/}: lines above are not lowercase SHA-256"
    echo "RESULT: FAIL"; exit 1
fi
command -v python3 >/dev/null || {
    echo "FAIL python3 not found (needed for hashing)"; echo "RESULT: FAIL"; exit 1; }

list() {
    if [ $# -gt 0 ]; then
        find "$@" -type d -name .git -prune -o -type f -print0
    elif git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        (cd "$ROOT" && git ls-files -z -co --exclude-standard) |
            while IFS= read -r -d '' f; do
                [ -f "$ROOT/$f" ] && printf '%s\0' "$ROOT/$f"
            done
    else
        find "$ROOT" -type d -name .git -prune -o -type f -print0
    fi
}

list "$@" | python3 -c '
import hashlib, re, sys
root, hashfile = sys.argv[1], sys.argv[2]
banned = set(l.strip() for l in open(hashfile) if l.strip())
split = re.compile(r"[^a-z0-9._-]+")
def hits(text):
    for tok in split.split(text.lower()):
        if not tok:
            continue
        for part in [tok] + re.split(r"[._-]+", tok):
            if part and hashlib.sha256(part.encode()).hexdigest() in banned:
                return True
    return False
files = [f for f in sys.stdin.buffer.read().decode().split("\0") if f]
bad = 0
for f in files:
    rel = f[len(root) + 1:] if f.startswith(root + "/") else f
    if hits(rel):
        print(rel + ":0: FAIL banned term in file name"); bad += 1
    try:
        data = open(f, "rb").read()
    except OSError:
        continue
    if b"\0" in data:
        continue
    for n, line in enumerate(data.decode("utf-8", "replace").splitlines(), 1):
        if hits(line):
            print("%s:%d: FAIL banned term" % (rel, n)); bad += 1
if bad:
    print("RESULT: FAIL (%d hits in %d files)" % (bad, len(files))); sys.exit(1)
print("RESULT: OK (%d files, %d hashes)" % (len(files), len(banned)))
' "$ROOT" "$HASHES"
