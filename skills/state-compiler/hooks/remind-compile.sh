#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# STRAP enforcement hook: PreCompact/SessionEnd reminder for state-compiler
# (STRAP Surface 2).
#
# A hook cannot force the model to invoke a skill -- there is no mechanism to
# make "compile state now" happen synchronously the way require-contract.sh
# can block a tool call. What a hook CAN do is guarantee the model is told,
# at the exact moment state would otherwise be silently lost, that it should
# do so -- turning "the agent forgot to invoke state-compiler" from a silent
# failure into a visible, remediable one. This is a weaker guarantee than
# require-contract.sh's hard block (see the paper's Threats to Validity /
# the review committee's practitioner finding on this exact gap), and this
# hook says so in the message it emits, rather than pretending to enforce
# what it cannot.
#
# Contract with Claude Code (verify against your installed version's hook
# docs): a PreCompact or SessionEnd hook receives JSON on stdin; printing
# plain text to stdout is surfaced to the model as additional context for
# that event on the versions this was written against. This hook never
# blocks (always exits 0) -- compaction and session end should not fail
# because state wasn't compiled; losing the reminder is better than losing
# the session.
#
# Install (project .claude/settings.json), both events recommended:
#   {
#     "hooks": {
#       "PreCompact": [{"matcher": "*", "hooks": [{"type": "command", "command": "skills/state-compiler/hooks/remind-compile.sh"}]}],
#       "SessionEnd": [{"matcher": "*", "hooks": [{"type": "command", "command": "skills/state-compiler/hooks/remind-compile.sh"}]}]
#     }
#   }

cat >&2 <<'EOF'
STRAP: this session is compacting or ending. If this task spans more than
one session, or the transcript has accumulated meaningful facts, decisions,
or progress since the last compile, run the state-compiler skill now to
write STATE.json before this context is gone. This is a reminder, not an
enforced gate -- nothing blocks the compaction/end if you skip it.
EOF

exit 0
