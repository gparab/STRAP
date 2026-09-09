# STRAP — Structured Task and Recovery Agent Protocol

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Paper](https://img.shields.io/badge/paper-24%20pages-blue)](paper.pdf)

**Strap your agent in before it runs wild.**

Your agent doesn't have a reasoning problem. It has a seatbelt problem. It doesn't know what "done" means, it forgets what it decided ten tool calls ago, it says "this should work" instead of proving it, and when something breaks it just... tries the same thing again. STRAP is four small, plain-text skills that fix exactly that — no framework, no new model, no database, nothing to `pip install`.

Read the [full paper](paper.pdf) for the design rationale, or skip straight to `skills/` and install what you need in five minutes.

## The problem in one sentence

When an agent fails, most teams make the prompt longer. The prompt was never the problem — the missing **contract**, **memory**, **verification**, and **recovery routing** around the model was.

## What's in the box

Four independent, model-agnostic skills. Use one, use all four, drop them into any agent that reads `SKILL.md`-style instructions (Claude Code, or adapt the prompts to your own harness).

| Skill | Fixes this failure | |
|---|---|---|
| [`task-contract`](skills/task-contract/SKILL.md) | Agent starts working from a vague sentence and scope-creeps or under-delivers | turns a request into a bounded, checkable spec *before* any action |
| [`state-compiler`](skills/state-compiler/SKILL.md) | Agent forgets a decision it made three tool calls ago once context scrolls past it | compiles the transcript into durable Facts / Decisions / Progress / Lessons |
| [`adversarial-verifier`](skills/adversarial-verifier/SKILL.md) | Agent says "done" or "this should work" with nothing to back it up | checks the artifact against the contract and is rewarded for finding a reason to reject it |
| [`failure-router`](skills/failure-router/SKILL.md) | Agent hits an error and retries the identical thing, or spirals into rewriting the wrong thing twice | classifies the failure into one of 7 classes, dispatches the matching fix, stops the loop on repeats |

## Why this instead of a framework

- **No service dependencies.** Each skill is a markdown file with a trigger, an input, and an output. No SDK version to track, no service to run — the optional enforcement hooks below are plain shell scripts, not a service either.
- **Model-agnostic.** Nothing here assumes a provider, a tool-calling format, or an orchestration runtime.
- **Composable.** Install one skill without the other three. Swap any one for your own implementation — they only share plain YAML/JSON, not code.
- **Readable in one sitting.** The whole spec is ~4 pages. You will actually remember what it does next week.
- **Scoped honestly.** The [paper](paper.pdf) tells you exactly when four skills are enough and when you need more (unattended multi-session agents, real external side effects, concurrent agents — see §5).

## Install (Claude Code)

```bash
cp -r skills/* ~/.claude/skills/
```

Or copy the one skill you need. Each `SKILL.md` is self-contained.

## Quick start

Ask the agent to "fix the login bug." With `task-contract` installed, before touching any file it writes a `TASK_CONTRACT.yaml` like:

```yaml
objective: "Fix login failing for users with uppercase email addresses"
scope: ["src/auth/login.js"]
constraints: ["no changes to the session token format"]
acceptance:
  - id: acc-1
    statement: "login succeeds for an email with mixed-case letters"
```

Only after that file exists does it start editing code.

**A skill alone is advisory** — it's a prompt, and a model under deadline pressure can rationalize past its own instructions. `task-contract` ships an optional [enforcement hook](skills/README.md) that blocks tool calls until a contract file exists (not just an instruction asking for one), and `state-compiler` ships a reminder hook so state doesn't silently go uncompiled at a session boundary. Both are plain shell scripts; the contract gate ships with a runnable self-check and correctly blocks every single time it's actually invoked (verified via Claude Code's own `--debug hooks` logging). **It is not a proven-airtight gate, though**: a real live-agent investigation found Claude Code's own hook dispatch occasionally skips invoking the hook at all, with no deterministic trigger found — a platform gap, not a bug here, and not fixable from inside a hook script. Treat it as a strong, usually-reliable deterrent and keep `task-contract`'s own instructions active too, not a mathematically guaranteed block. It also **fails closed — if `python3` is missing from your environment (common in minimal CI/container images), it blocks *all* matched tool calls, not just the ones missing a contract.** Confirm `python3 --version` works in your target environment before relying on this hook there. The reminder hook has no self-check yet — see [`skills/README.md`](skills/README.md) for what's enforced vs. advisory across all four skills, and how to wire the hooks into `.claude/settings.json`.

## Advantages at a glance

- ✅ **Fewer silent scope creeps** — nothing runs until `objective`, `scope`, `constraints`, and checkable `acceptance` criteria exist.
- ✅ **No more lost decisions** — state is a file, not a hope that the model rereads the whole transcript.
- ✅ **No more "trust me, it works"** — every completion claim is checked against evidence, with an explicit incentive to reject.
- ✅ **No more infinite retry loops** — every failure is classified and budgeted; repeats stop and escalate instead of burning tokens forever.
- ✅ **Takes an afternoon, not a sprint** — plain text in, plain text out, nothing to deploy.
- ✅ **Honest about its own limits** — tells you when you've outgrown it, instead of pretending to be the whole answer.

## The paper

[`paper.pdf`](paper.pdf) — *STRAP: A Structured Task and Recovery Agent Protocol for Reliable AI Agent Harnesses*. Covers the full 8-surface protocol (Contract, Context, Tools, State, Policy, Verification, Recovery, Observability), the acceptance-item identity scheme, the four fully-specified schemas behind these skills, and ties each design choice to a real published result (ReAct, Toolformer, Reflexion, Self-Refine, the "LLMs cannot self-correct" and LLM-as-judge findings, MemGPT, Generative Agents, SWE-bench, AutoGen, AgentBench — full list in the paper's References). Every empirical claim below is reported exactly as measured, including the ones that came out lower than expected:

- The Failure Router's classification rule scores **88.0% accuracy** on a labeled 50-case self-authored corpus, **71.4%** (n=14) on real command output blind-labeled by an agent instance, and **45.0%** (n=20 evaluated, Wilson 95% CI [25.8%, 65.8%]) on a larger corpus of real GitHub Actions failure logs, independently sourced and blind-labeled — the same, unmodified classifier, all three numbers reported as measured, not adjusted to close the gap. The trend is real and gets worse, not better, as the corpus gets more independent.
- In a controlled simulation, routing a failure to its matched recovery action resolves **76.6%** of episodes with perfect classification (the ceiling) and **68.1%** once the classifier's actual measured error rate is folded in (the realistic figure), versus **40.3%** for a policy that retries the same action blindly. A sensitivity sweep shows neither figure's advantage is unconditional — the paper reports the actual crossover points (naive retry overtakes the realistic figure at roughly 0.245 and the ceiling at roughly 0.30) rather than only checking the range where the claim looks best.
- A second, independently-authored implementation was built internally during development to pressure-test the schema for cross-implementation interoperability — it parsed a real contract, ran real acceptance checks as subprocesses against a real fixture, and its independently-designed classifier agreed with ground truth on 39/48 (81.2%) of the corpus above. That code isn't published in this repo, so the paper reports it as a design note, not as independently-reproducible evidence.
- The **live-agent benchmark** was pre-registered (hypothesis, sampling procedure, N=94/arm with the power calculation, stopping rule, and analysis plan all fixed before data collection) and was run at a small, logged pilot scope: 1 of 6 real SWE-bench Lite tasks, both arms. Control resolved it cleanly. Treatment hit a real, previously-unknown bootstrap deadlock in the enforcement hook — fixed and regression-tested live, during the same run — then resolved it too. A follow-up investigation using Claude Code's own debug logging found the real cause: an intermittent skip in Claude Code's own hook dispatch (not a bug in this project's code, confirmed via `--debug hooks` logs), with no deterministic trigger despite directed reproduction attempts. See `skills/README.md` for what this means for how reliable the hook actually is. The confirmatory N=94 study remains unrun.
- The **independent classification corpus** was pre-registered (target N=100 with a human labeler, source-sampling procedure, and analysis plan fixed in advance) and was run at reduced scope (N=30, AI labeler instead of human — both logged as amendments before data collection) — that's the 45.0% figure above. The confirmatory version, at full scale with a genuine independent human, remains unrun.

The figures follow the monochrome/coral-accent "Decision Intelligence Design" visual grammar.

The paper is 24 pages: 8 numbered sections (Introduction through Conclusion) plus a Colophon and References.

Motivated by the practitioner framing in ["Harness Engineering"](https://x.com/LunarResearcher/article/2096570562625655088) by Lunar (@LunarResearcher) — the paper itself cites only peer-reviewed / arXiv research, not that post.

## Contributing

Every number in the paper is reported exactly as measured — see [`CONTRIBUTING.md`](CONTRIBUTING.md) for what to run before opening a PR.

## License

MIT — use it, fork it, put your team's name on your fork of it. If STRAP saves you from a 3am "why did the agent delete the migration" incident, tell someone.
