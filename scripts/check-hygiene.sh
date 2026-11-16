#!/usr/bin/env bash
# Public-repo hygiene gate. Exits non-zero if tracked content (index) or git history contains
# private details, assistant attribution, or committed binaries (saves).
#
# Built-in patterns are below. Extra patterns (real nicknames, host names, ...) are read from
# the untracked dev/hygiene-patterns.txt, one extended regex per line ('#' comments allowed).
# This file contains the patterns themselves, so it is excluded from the scan.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
SELF=scripts/check-hygiene.sh

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
fail=0
report() { echo "HYGIENE FAIL: $1" >&2; fail=1; }

# label|flags|extended regex (no \b: it is not portable to BSD/macOS regex)
PATTERNS=(
  'private IPv4 range (192.168)|-E|192\.168\.'
  'private IPv4 range (10/172.16-31)|-E|(^|[^0-9.])(10\.[0-9]+\.[0-9]+\.[0-9]+|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]+\.[0-9]+)([^0-9]|$)'
  'CGNAT / VPN address (100.64-127)|-E|(^|[^0-9.])100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]+\.[0-9]+'
  'tailnet host name|-E|\.ts\.net'
  'home directory path|-E|/Users/[A-Za-z]|/home/[a-z]'
  'credential shape (GitHub, AWS, Slack, Atlassian, private key)|-E|ghp_[A-Za-z0-9]|github_pat_|gho_[A-Za-z0-9]|AKIA[0-9A-Z]{12}|xox[bp]-[0-9A-Za-z]|ATATT[A-Za-z0-9]|BEGIN [A-Z ]*PRIVATE KEY'
  'container number|-E|(^|[^A-Za-z0-9_])CT ?[0-9]{3}([^A-Za-z0-9_]|$)'
  'server data path|-E|/opt/factorio/data'
  'assistant co-author trailer|-Ei|Co-Authored-By'
  'assistant attribution|-Ei|Generated with Claude Code'
)
if [ -f dev/hygiene-patterns.txt ]; then
  grep -v -e '^[[:space:]]*$' -e '^[[:space:]]*#' dev/hygiene-patterns.txt > "$TMP" || true
  if [ -s "$TMP" ]; then
    PATTERNS+=("local pattern file|-E|$(paste -sd'|' "$TMP")")
  fi
fi

has_history=0
git rev-parse --verify -q HEAD >/dev/null && has_history=1

for entry in "${PATTERNS[@]}"; do
  label=${entry%%|*}; rest=${entry#*|}
  flags=${rest%%|*}; pattern=${rest#*|}

  # 1. tracked content (the index, so staged files count before they are committed)
  if hits=$(git grep --cached -I -n "$flags" -e "$pattern" -- . ":(exclude)$SELF") && [ -n "$hits" ]; then
    report "$label in tracked files"; echo "$hits" | sed 's/^/  /' >&2
  fi

  if [ "$has_history" = 1 ]; then
    # 2. commit messages
    if git log --all --format='%H %B' | grep "$flags" -e "$pattern" >/dev/null; then
      report "$label in a commit message"
    fi
    # 3. content of every past commit (also catches files deleted since)
    if git log --all -p --no-color --format= -- . ":(exclude)$SELF" | grep "$flags" -e "$pattern" >/dev/null; then
      report "$label in git history"
    fi
  fi
done

# Saves and other binaries must never be tracked, now or in history.
bad=$(git ls-files --cached | grep -E '\.(zip|dat)$' || true)
[ -n "$bad" ] && { report "tracked zip/dat files"; echo "$bad" | sed 's/^/  /' >&2; }
if [ "$has_history" = 1 ]; then
  bad=$(git log --all --name-only --format= | grep -E '\.(zip|dat)$' | sort -u || true)
  [ -n "$bad" ] && { report "zip/dat files in git history"; echo "$bad" | sed 's/^/  /' >&2; }
fi

if [ "$fail" = 0 ]; then
  echo "hygiene: ok"
fi
exit "$fail"
