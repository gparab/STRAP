# Contributing

This repo is a spec, four skills, two hooks, and the paper they're built from — no server, no build step beyond the paper.

- **Skill changes** (`skills/*/SKILL.md`): keep the schema examples consistent with `paper.pdf` §3 — a change to a field name or shape has to land in both, or the paper and the skill will disagree with each other, which is exactly the kind of inconsistency this project's own review process exists to catch.
- **Hook changes** (`skills/*/hooks/*.sh`): run `skills/task-contract/hooks/test_require_contract.sh` before and after — it must stay green. If you touch the fail-open/fail-closed behavior, say so explicitly in the PR; that tradeoff is documented in the hook's own header and in the paper, and both need to stay accurate.
- **Paper changes**: every number in the paper is a claim about something the author measured. If you have a correction, cite what changed and where; a stale number in a paper about evidence-based completion is the one bug this project can't afford.

## Before opening a PR

```bash
skills/task-contract/hooks/test_require_contract.sh   # hook self-check, 10/10
```

If a number changed, it should change everywhere it's cited — `README.md` and the paper.
