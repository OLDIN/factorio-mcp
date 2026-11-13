#!/usr/bin/env bash
# Run the pure-Lua mod tests (mod/tests/*_test.lua); stops at the first failure.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
LUA=${LUA:-$(command -v lua || echo /opt/homebrew/bin/lua)}
cd "$ROOT/mod"
shopt -s nullglob
tests=(tests/*_test.lua)
if [ ${#tests[@]} -eq 0 ]; then
  echo "no mod tests yet (mod/tests/*_test.lua)"
  exit 0
fi
for t in "${tests[@]}"; do
  echo "== $t"
  "$LUA" "$t"
done
echo "all mod tests passed"
