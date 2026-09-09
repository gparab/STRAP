#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# STRAP enforcement hook: PreToolUse gate for task-contract (STRAP Surface 1).
#
# Turns "hard gate, not a style preference" (paper §3.1) from a prompt-writer's
# aspiration into a real mechanism: this blocks side-effecting tool calls
# until TASK_CONTRACT.yaml exists in the working tree. The task-contract
# SKILL.md is advisory on its own -- a model can rationalize past its own
# instructions under deadline pressure. This hook cannot be rationalized past
# WHEN IT RUNS.
#
# IMPORTANT, from a real live-agent investigation (2026-09-09, logged in
# the paper's §7): this hook has
# been observed, using Claude Code's own --debug hooks logging, to correctly
# block every single time it is actually invoked -- but Claude Code's own
# PreToolUse dispatch layer has, in a small number of real live sessions,
# skipped invoking the hook entirely for a matched tool call (confirmed via
# permissionDecisionMs=0 and no PreToolUse:Write log line -- the hook
# process never ran). No deterministic trigger for this was found despite
# directed attempts to reproduce it. This is a real gap in Claude Code's
# hook dispatch, not a bug in this script, and this project cannot fix it
# from inside a hook. Treat this hook as a strong, usually-reliable
# deterrent, not a mathematically proven guarantee -- and keep the
# task-contract SKILL.md's own instructions active alongside it, since
# neither the hook nor the prompt alone has been shown to be airtight.
#
# Contract with Claude Code (verify against your installed version's hook
# docs before relying on this in production -- hook I/O has changed across
# versions): a PreToolUse hook receives a JSON payload on stdin with at least
# `tool_name` and `tool_input`; exiting with status 2 blocks the tool call and
# surfaces this script's stderr to the model as the reason. Exiting 0 allows
# the call through unmodified. This is the long-stable blocking mechanism;
# some versions additionally support a JSON stdout contract
# ({"hookSpecificOutput": {"permissionDecision": "deny", ...}}) -- if your
# installed version prefers that, adapt the `block` calls below.
#
# Fail-closed by design: anything this hook cannot verify -- python3 missing,
# stdin not the expected JSON shape -- now BLOCKS (exit 2) instead of
# allowing the call through. A gate that silently allows everything when it
# can't parse its own input isn't a hard gate, it's a hard gate with a hole
# in it. Tradeoff, stated plainly: if this hook itself is broken or
# misconfigured in an environment (e.g. no python3 on PATH), it will now
# block ALL matched tool calls in that environment, not just the ones
# missing a contract. That's an availability risk you're accepting in
# exchange for removing the old silent-allow risk. If that tradeoff is wrong
# for your setup, don't install this hook rather than patching it back to
# fail open.
#
# Install (project .claude/settings.json):
#   {
#     "hooks": {
#       "PreToolUse": [
#         {
#           "matcher": "Edit|Write|Bash|NotebookEdit",
#           "hooks": [{"type": "command", "command": "skills/task-contract/hooks/require-contract.sh"}]
#         }
#       ]
#     }
#   }
#
# What this hook does NOT do: validate the contract's contents (six keys,
# checkable acceptance statements, unique ids) -- that validation is the
# task-contract skill's job, run by the model when it authors the file. This
# hook only enforces that the file exists before a side-effecting tool runs.
# It also does not distinguish read-only exploration from a genuine first
# write -- see CONTRACT_EXEMPT_TOOLS below for the (intentionally short)
# allowlist of tools this gate never blocks.
#
# This hook has no atomicity guarantee between its existence check and the
# tool call it gates; a concurrent deletion of the contract file between
# check and use is a TOCTOU gap this hook does not close.
#
# BOOTSTRAP CASE (found via a real live-agent pilot run, not a synthetic
# test, described in the paper's §7): a
# naive version of this hook deadlocks on the very first task. Creating
# TASK_CONTRACT.yaml is itself a Write call; if Write is gated on the
# contract already existing, nothing can ever create it, and no tool in the
# matcher is exempt enough to bootstrap past that. This hook special-cases
# exactly one thing to break that deadlock: a Write or Edit whose target
# path IS the contract file itself is always allowed through, regardless of
# whether the file currently exists -- because writing that specific file
# is the act this whole gate exists to require, not something to block. No
# other path, and no other tool, gets this exemption.

set -euo pipefail

CONTRACT_FILE="${STRAP_CONTRACT_FILE:-TASK_CONTRACT.yaml}"

# Tools this gate never blocks, regardless of the matcher configured in
# settings.json -- read-only or inherently low-risk actions a contract
# shouldn't have to precede. Keep this list short and explicit; the matcher
# in settings.json is the primary filter, this is a second, defensive check
# -- not the primary safety boundary. It matches on tool_name only: if your
# project registers a custom or MCP tool that happens to share one of these
# four names but behaves differently (e.g. a non-read-only "Read"), it will
# be exempted incorrectly. Confirm no custom tool name collides with this
# list, or narrow the settings.json matcher instead of relying on this list.
CONTRACT_EXEMPT_TOOLS="Read Grep Glob TodoWrite"

block() {
  echo "STRAP: blocked -- $1" >&2
  echo "Run the task-contract skill to create ${CONTRACT_FILE} before this action, or set STRAP_CONTRACT_FILE if your project uses a different path/name." >&2
  exit 2
}

if ! command -v python3 >/dev/null 2>&1; then
  echo "STRAP: BLOCKED (environment failure, not a missing-contract failure) -- python3 is not on PATH, so require-contract.sh cannot parse the PreToolUse payload at all. This is not 'no ${CONTRACT_FILE}'; it's this hook itself being unable to run. Install python3, or fix your PATH, before any matched tool call can proceed." >&2
  exit 2
fi

payload="$(cat)"

tool_name="$(printf '%s' "$payload" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_name",""))' 2>/dev/null || echo "")"
# Write/Edit payloads carry the target path under file_path in the shapes
# this hook has been observed against; empty if absent or the tool is
# something else (Bash has no single target path -- never eligible for the
# bootstrap exemption below, by design).
target_path="$(printf '%s' "$payload" | python3 -c 'import json,sys; d=json.load(sys.stdin); ti=d.get("tool_input") or {}; print(ti.get("file_path") or ti.get("path") or "")' 2>/dev/null || echo "")"

if [ -z "$tool_name" ]; then
  # Malformed or unrecognized payload shape -- fail CLOSED. We cannot verify
  # this call is safe, which is different from verifying a contract is
  # missing; the message below says so explicitly.
  echo "STRAP: BLOCKED (environment failure, not a missing-contract failure) -- could not parse tool_name from stdin. This is not 'no ${CONTRACT_FILE}'; it's this hook being unable to read its own PreToolUse payload. Check this hook against your Claude Code version's PreToolUse payload shape." >&2
  exit 2
fi

for exempt in $CONTRACT_EXEMPT_TOOLS; do
  if [ "$tool_name" = "$exempt" ]; then
    exit 0
  fi
done

# Bootstrap exemption: writing the contract file itself is always allowed,
# even before it exists -- see the header comment above for why this has to
# be here at all.
if [ -n "$target_path" ] && { [ "$tool_name" = "Write" ] || [ "$tool_name" = "Edit" ]; }; then
  base_target="$(basename -- "$target_path")"
  base_contract="$(basename -- "$CONTRACT_FILE")"
  if [ "$target_path" = "$CONTRACT_FILE" ] || [ "$base_target" = "$base_contract" ]; then
    exit 0
  fi
fi

if [ ! -f "$CONTRACT_FILE" ]; then
  block "no ${CONTRACT_FILE} in the working tree, and ${tool_name} is not on the exempt list (${CONTRACT_EXEMPT_TOOLS}) or writing the contract file itself."
fi

exit 0
