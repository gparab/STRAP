# STRAP skills: skill vs. hook

Each `SKILL.md` here is a prompt: instructions a model reads and, if it recognizes the trigger, follows. That makes `task-contract` and `adversarial-verifier` and the rest genuinely useful, but a prompt alone is advisory — a model under deadline pressure can rationalize past its own instructions ("this one's simple enough to skip the contract"), and nothing in a markdown file stops it.

Two of the four skills ship an optional **hook** — real, runnable shell code registered with Claude Code's hook system — that enforces what the skill can only ask for:

| Skill | Enforcement | Mechanism |
|---|---|---|
| [`task-contract`](task-contract/hooks/require-contract.sh) | **Strong, usually-reliable gate — not a proven-airtight one.** Blocks `Edit`/`Write`/`Bash`/`NotebookEdit` (or whatever you match) until `TASK_CONTRACT.yaml` exists, and correctly blocks every time it is actually invoked (verified via `--debug hooks` logging). But a real live-agent investigation (2026-09-09, methodology in the paper's §7) found Claude Code's own hook dispatch occasionally skips invoking the hook at all, with no deterministic trigger identified — a platform gap, not a bug in this script, and not fixable from inside a hook. Fails closed on a missing `python3` or an unparseable hook payload when it does run — see the script's header. Its exempt-tool allowlist matches by name only; a custom/MCP tool sharing one of those names is exempted incorrectly, so narrow your `settings.json` matcher if that's a risk in your project. Keep `task-contract`'s own instructions active alongside this hook; neither has been shown to be airtight alone. | `PreToolUse` hook, exit code 2 |
| [`state-compiler`](state-compiler/hooks/remind-compile.sh) | **Reminder only** — a hook cannot force a skill invocation, only guarantee the model is told to do one. | `PreCompact`/`SessionEnd` hook, stderr message |
| `adversarial-verifier` | None shipped — its trigger (a completion claim) is low-risk to misfire on; see the skill file. | — |
| `failure-router` | None shipped — invoked reactively off a tool error or a verifier rejection, which is already a concrete, hard-to-miss signal. | — |

**This repository does not ship enforcement for `approval_required` actions (§3 of the paper) — you have to build it.** The intended design reuses the same mechanism as `task-contract`: extend `require-contract.sh`'s tool/policy check to consult a Policy risk table (STRAP Surface 5, schema-only — see the paper §3.5) and block (exit 2) any call tagged `approval_required` until the user has explicitly confirmed it earlier in the same conversation. There is no hook primitive for "wait for a future chat message" — the block is synchronous per call, so the pattern is: the agent proposes the action, the hook blocks it, the agent asks the user, the user replies, the agent retries the same call, and this time it's authorized. Building this requires a per-project Policy table to check against, which is inherently project-specific and therefore out of scope here — `require-contract.sh` is a complete, tested reference for the blocking mechanism itself, but the Policy table and the block-until-confirmed logic are yours to write.

## Install

```bash
cp -r skills/* ~/.claude/skills/         # the four SKILL.md files (always)
```

To add enforcement, register the hooks in your project's `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write|Bash|NotebookEdit",
        "hooks": [{"type": "command", "command": "skills/task-contract/hooks/require-contract.sh"}]
      }
    ],
    "PreCompact": [
      {"matcher": "*", "hooks": [{"type": "command", "command": "skills/state-compiler/hooks/remind-compile.sh"}]}
    ],
    "SessionEnd": [
      {"matcher": "*", "hooks": [{"type": "command", "command": "skills/state-compiler/hooks/remind-compile.sh"}]}
    ]
  }
}
```

This is the same JSON documented in the header comment of each hook script (`task-contract/hooks/require-contract.sh`, `state-compiler/hooks/remind-compile.sh`), combined into one example. The contract hook has a runnable self-check (`task-contract/hooks/test_require_contract.sh`); the reminder hook does not yet. Run the self-check after copying to confirm it still blocks/allows correctly in your environment before trusting it on a real project.

`require-contract.sh` has been verified against a real, live Claude Code session, not just the synthetic-payload self-check: a fresh project with the hook registered in `.claude/settings.json` (matcher `Write`, no `TASK_CONTRACT.yaml` present) was given the prompt "write a file called hello.txt" with only `Write` in `--allowedTools`; the session's own transcript confirmed the `PreToolUse` hook blocked the `Write` call, and the agent worked around the gate by creating a contract file first, then retried — exactly the intended behavior. This is one exact-version data point (Claude Code 2.1.207), not a guarantee across versions; re-run the self-check and, ideally, this same live check after any Claude Code upgrade.

**Verify against your installed Claude Code version's hook documentation before relying on this in production.** Hook stdin/stdout contracts have changed across versions; the header comment in each script states the contract it was written against and how to adapt it if yours differs.
