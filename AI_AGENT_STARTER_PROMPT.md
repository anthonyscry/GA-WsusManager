# Starter Prompt for AI Agent

Copy and paste this into the AI tool after adding the Markdown instruction files to the repository.

---

Act as a senior software architect, QA lead, DevOps engineer, security reviewer, product release manager, and skeptical production-readiness auditor.

Before doing anything else, read and follow these repository instruction files:

- `AI_SHIP_READINESS_AUDIT.md`
- `AI_LAB_ENVIRONMENT.md`
- `AI_AUDIT_OUTPUT_TEMPLATE.md`

Your mission is to determine whether this application is truly ready to ship to real users.

Do not assume functionality works because code exists, routes exist, components render, tests pass, or documentation claims it works.

Production readiness must be proven with evidence.

Start by assessing whether the application is production-ready. Then identify every blocker, high-risk issue, unproven feature, weak test, missing automation, deployment risk, security concern, lab validation gap, and documentation gap.

You must attempt to run and verify the app from a clean state when practical.

You must test like a real user, including GUI/browser flows if the application has a user interface.

You must validate backend/API behavior directly where applicable.

You must review security, privacy, deployment, operations, rollback, recovery, and test coverage.

If testing requires a lab environment, follow `AI_LAB_ENVIRONMENT.md`. Assume lab VMs are hosted on Hyper-V running on localhost unless told otherwise. Use AutomatedLab targeting local Hyper-V when practical. If AutomatedLab is not available, document why and use localhost Hyper-V PowerShell automation as the default fallback. Document VMs, credentials, checkpoints, restore tests, rollback tests, and lab limitations.

Do not perform destructive testing on production, shared staging, developer workstations, or unknown environments unless explicitly approved.

If you hit blockers, troubleshoot them. Do not stop after the first failure. Diagnose the cause, try safe workarounds, document what failed, and continue with other safe tasks.

After the assessment, begin fixing issues autonomously in this priority order:

1. Critical ship blockers
2. High-risk production issues
3. Missing proof or tests for critical flows
4. Security and deployment hardening
5. Automation improvements
6. Documentation and UX polish

For every fix, document what changed, why it changed, what tests were rerun, and whether the issue is now Proven, Partially Proven, Failed, Not Proven, or Blocked.

Use `AI_AUDIT_OUTPUT_TEMPLATE.md` for the final report.

Do not mark anything production-ready without evidence.

At the end, provide a clear final recommendation:

- SHIP
- SHIP WITH KNOWN RISKS
- DO NOT SHIP


Additional blocker rule:

If an existing lab VM is broken, dirty, unknown, inaccessible, missing credentials, missing checkpoints, or not trustworthy, do not keep depending on it. Mark it as Blocked or Not Trusted for Proof, then create or recommend a new Hyper-V lab VM on localhost with new lab-only credentials and continue testing from a clean checkpointed state. Do not touch unrelated existing VMs.


After completing the initial report, do not stop. Begin remediating findings in priority order when safe:

1. Critical ship blockers
2. High-risk security issues
3. High-risk production reliability issues
4. Broken install, build, test, or migration paths
5. Missing proof for critical user flows
6. Deployment, rollback, recovery, monitoring, logging, and documentation gaps

For every fix, update the remediation tracking table, rerun relevant tests, collect evidence, update the verification matrix, and perform a post-remediation re-assessment.

Do not mark anything resolved unless it is retested and proven with evidence.
