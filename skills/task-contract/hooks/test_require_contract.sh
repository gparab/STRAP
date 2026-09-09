#!/usr/bin/env bash
# Runnable self-check for require-contract.sh. Not a framework, no fixtures --
# a handful of assert-style cases simulating the PreToolUse stdin payload.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HERE/require-contract.sh"
TMPDIR="$(mktemp -d)"
cd "$TMPDIR"

fail=0

run_hook() {
  local tool_name="$1"
  echo "{\"tool_name\": \"$tool_name\", \"tool_input\": {}}" | "$HOOK" >/tmp/strap_hook_stdout 2>/tmp/strap_hook_stderr
  echo $?
}

run_hook_with_path() {
  local tool_name="$1" file_path="$2"
  echo "{\"tool_name\": \"$tool_name\", \"tool_input\": {\"file_path\": \"$file_path\"}}" | "$HOOK" >/tmp/strap_hook_stdout 2>/tmp/strap_hook_stderr
  echo $?
}

check() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "ok   - $desc"
  else
    echo "FAIL - $desc (expected exit $expected, got $actual)"
    fail=1
  fi
}

# Case 1: no contract file, non-exempt tool -> blocked (exit 2)
rm -f TASK_CONTRACT.yaml
code="$(run_hook "Write")"
check "Write with no contract is blocked" 2 "$code"

# Case 2: no contract file, exempt tool -> allowed (exit 0)
code="$(run_hook "Read")"
check "Read with no contract is allowed" 0 "$code"

# Case 3: contract exists, non-exempt tool -> allowed (exit 0)
echo "objective: test" > TASK_CONTRACT.yaml
code="$(run_hook "Write")"
check "Write with a contract present is allowed" 0 "$code"

# Case 4: contract exists, Bash tool -> allowed
code="$(run_hook "Bash")"
check "Bash with a contract present is allowed" 0 "$code"

# Case 5: contract removed again -> blocked again (no stale allow-state)
rm -f TASK_CONTRACT.yaml
code="$(run_hook "Edit")"
check "Edit is blocked again once the contract is removed" 2 "$code"

# Case 6: malformed stdin payload -> fails CLOSED (exit 2), does not crash,
# and does not silently allow the call through.
code="$(echo 'not json' | "$HOOK" >/dev/null 2>/tmp/strap_hook_stderr; echo $?)"
check "malformed payload fails closed rather than crashing or allowing" 2 "$code"

# Case 7: python3 missing from PATH -> fails CLOSED (exit 2). Simulated by
# building a PATH containing only a directory of our own (no python3, but
# with a real bash/echo/cat/etc. via a wrapper) -- practical because require-
# contract.sh's only external dependency besides shell builtins is python3.
NOPY_DIR="$(mktemp -d)"
for bin in bash cat echo mktemp dirname pwd rm; do
  real="$(command -v "$bin")"
  [ -n "$real" ] && ln -sf "$real" "$NOPY_DIR/$bin"
done
code="$(echo "{\"tool_name\": \"Write\", \"tool_input\": {}}" | PATH="$NOPY_DIR" "$HOOK" >/dev/null 2>/tmp/strap_hook_stderr; echo $?)"
check "missing python3 on PATH is blocked, not silently allowed" 2 "$code"
rm -rf "$NOPY_DIR"

# Case 8: bootstrap deadlock, found via a real live-agent pilot run -- Write
# targeting the contract file itself must be allowed even when the contract
# does not yet exist, or nothing can ever create it.
rm -f TASK_CONTRACT.yaml
code="$(run_hook_with_path "Write" "TASK_CONTRACT.yaml")"
check "Write targeting the contract file itself is allowed before it exists (bootstrap)" 0 "$code"

# Case 9: the bootstrap exemption is narrow -- a Write to any OTHER path is
# still blocked when the contract doesn't exist, even though it's the same
# tool_name as case 8.
code="$(run_hook_with_path "Write" "some_other_file.py")"
check "Write to a non-contract path is still blocked before a contract exists" 2 "$code"

# Case 10: the bootstrap exemption never applies to Bash, which has no
# single target file_path -- creating the contract via a shell redirect is
# not exempted, only Write/Edit with a matching file_path are.
code="$(run_hook "Bash")"
check "Bash is never bootstrap-exempt, even with no contract present" 2 "$code"

cd /
rm -rf "$TMPDIR"

if [ "$fail" -eq 0 ]; then
  echo "All require-contract.sh checks passed."
else
  echo "One or more require-contract.sh checks FAILED."
fi
exit "$fail"
