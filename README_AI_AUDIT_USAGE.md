# How to Use These AI Audit Instructions

## Recommended File Placement

Place these files at the root of the repository:

```text
/AI_SHIP_READINESS_AUDIT.md
/AI_LAB_ENVIRONMENT.md
/AI_AUDIT_OUTPUT_TEMPLATE.md
/AI_AGENT_STARTER_PROMPT.md
```

Optional folder layout:

```text
/docs/ai-audit/AI_SHIP_READINESS_AUDIT.md
/docs/ai-audit/AI_LAB_ENVIRONMENT.md
/docs/ai-audit/AI_AUDIT_OUTPUT_TEMPLATE.md
/docs/ai-audit/AI_AGENT_STARTER_PROMPT.md
```

If you place them under `/docs/ai-audit/`, update the starter prompt paths.

---

## Best Way to Use

1. Add the Markdown files to the repo.
2. Open the repo in your AI coding tool.
3. Paste the contents of `AI_AGENT_STARTER_PROMPT.md`.
4. Tell the AI to read the Markdown files before making changes.
5. Require the AI to produce the final report using `AI_AUDIT_OUTPUT_TEMPLATE.md`.

---

## Suggested Command to Give the AI

```text
Read AI_AGENT_STARTER_PROMPT.md and follow it exactly.
```

Or paste the full starter prompt manually.

---

## Why This Is Better Than One Giant Prompt

Using Markdown files gives you:

- Reusable repo instructions
- Version-controlled audit rules
- Easier updates
- Less prompt clutter
- A standard output format
- Clear AI guardrails
- Better repeatability between audits
- Easier onboarding for different AI tools

---

## Important Rule

The AI should not treat the Markdown files as casual guidance.

The files are operating instructions.

If there is a conflict between casual chat instructions and these Markdown files, the AI should follow the Markdown files unless the user explicitly overrides them.


## Default Lab Assumption

These instructions now assume lab VMs are hosted on:

```text
Hyper-V on localhost
```

AutomatedLab should target local Hyper-V when practical.

If AutomatedLab is not available, the AI should fall back to local Hyper-V PowerShell automation and document the VM inventory, checkpoints, restore testing, and limitations.


## Blocker Recovery Behavior

If lab testing gets blocked by a bad VM, unknown credentials, failed state, missing checkpoint, or questionable environment, the AI should create a new lab-only Hyper-V VM on localhost with new lab-only credentials and continue from a clean baseline.

The AI should not waste time trying to prove readiness on a dirty or untrusted VM.

The AI should not modify unrelated existing VMs.


## Remediation After the Report

The instruction pack now requires the AI to continue after the initial report.

The AI should:

1. Create a remediation plan.
2. Fix critical and high-risk findings first.
3. Add or update tests that prove the fix.
4. Rerun relevant tests.
5. Update the verification matrix.
6. Update the remediation tracking table.
7. Perform a second ship-readiness assessment.
8. Clearly state whether the final ship recommendation changed.

The AI should not mark a finding resolved unless it has evidence.
