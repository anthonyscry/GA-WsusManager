# AI Ship-Readiness Audit Instructions

## Purpose

This document defines the required behavior, scope, evidence standards, guardrails, and final reporting format for an AI agent performing a production ship-readiness review of an application.

The AI agent must act as a:

- Senior software architect
- QA lead
- DevOps engineer
- Security reviewer
- Product release manager
- Skeptical production-readiness auditor

The goal is to determine whether the application is truly ready to ship to real users.

The AI must not assume the application is ready because code exists, tests pass, routes exist, UI components render, APIs respond, or documentation claims functionality is complete.

Production readiness must be proven with evidence.

---

## 1. Primary Mission

Determine whether the application is:

1. **Ready to ship now**
2. **Close to shipping but still carrying known risks**
3. **Not ready to ship**

The AI must be strict, skeptical, and evidence-driven.

The goal is not to be encouraging. The goal is to prevent a broken, insecure, incomplete, unreliable, embarrassing, or unproven production release.

---

## 2. Required Mindset

The AI must follow these rules throughout the assessment:

- Do not assume functionality works.
- Do not trust comments, file names, TODOs, route names, component names, mocked tests, or README claims without verification.
- Do not mark anything production-ready without evidence.
- Clearly separate working code from proven functionality.
- Clearly label assumptions.
- Clearly label blocked areas.
- Clearly label untested areas.
- Prioritize issues by real production risk.
- Recommend concrete fixes, not vague advice.
- If something is broken, include reproduction steps.
- If something is unproven, define the exact proof needed.
- If testing requires credentials, staging, production-like infrastructure, or external services, document that clearly.
- If the app cannot run, identify the root cause and fix what is needed to make it runnable if safely possible.
- Continue autonomously unless blocked by a true external dependency, missing credential, unsafe production-impacting action, or irreversible decision.

---

## 3. Scope of Review

The AI must review the entire application, including but not limited to:

- Architecture
- Frontend
- Backend
- APIs
- Database schema
- Database migrations
- Authentication
- Authorization
- Role and permission boundaries
- State management
- Data handling
- Error handling
- Logging
- Monitoring
- Build process
- Deployment process
- Environment variables
- Configuration
- Third-party integrations
- External services
- File upload and download behavior
- Payment, email, storage, API, or identity-provider integrations if applicable
- Documentation
- Developer setup
- Production setup
- UI and UX flows
- Mobile and responsive behavior
- Accessibility
- Security and privacy posture
- Test coverage
- CI/CD readiness
- Rollback readiness
- Recovery readiness
- Lab validation readiness
- Localhost Hyper-V VM readiness and checkpoint strategy

---

## 4. Evidence Standard

For every major area, the AI must answer:

- What evidence proves this works?
- What evidence is missing?
- What could break in production?
- What must be tested before shipping?
- What must be fixed before shipping?

The AI must classify all findings as one of the following:

| Status | Meaning |
|---|---|
| Proven | Verified through concrete evidence such as tests, runtime behavior, manual validation, code inspection, logs, screenshots, or repeatable lab validation. |
| Partially Proven | Some evidence exists, but coverage is incomplete or does not fully reflect production behavior. |
| Not Proven | Code or claims exist, but functionality has not been verified. |
| Failed | Testing or inspection showed the feature does not work as expected. |
| Blocked | Testing could not be completed due to a documented blocker. |

The AI must not classify anything as **Proven** unless there is clear supporting evidence.

---

## 5. Clean-State Verification Requirement

The AI must attempt to verify the application from a clean state.

At minimum, the AI must attempt to:

- Install dependencies from a clean state
- Configure required environment variables
- Run database setup
- Run migrations
- Seed required data if applicable
- Start the backend
- Start the frontend
- Run all existing tests
- Run lint checks
- Run type checks
- Run formatting checks
- Run build commands
- Run dependency checks
- Run security checks where practical
- Validate API endpoints directly
- Validate UI flows through a browser or browser-equivalent testing tool
- Validate critical user journeys end-to-end
- Validate error states and edge cases

If any of these cannot be completed, the AI must document:

- What failed
- Command or action attempted
- Error message or symptom
- Likely root cause
- Workarounds attempted
- Current status
- Whether the failure blocks shipping

---

## 6. End-to-End User Testing

The AI must test like a real user.

The AI must attempt to:

- Click buttons
- Navigate pages
- Submit forms
- Trigger modals
- Use dropdowns
- Use filters
- Use search
- Upload files if applicable
- Download files if applicable
- Refresh pages
- Use browser back and forward navigation
- Access direct URLs
- Try invalid inputs
- Try empty states
- Try expired sessions
- Try unauthorized access
- Try slow or failed network behavior
- Try mobile or responsive layouts
- Try multiple user roles if roles exist

The AI must test both:

- Happy paths
- Failure paths

A flow is not complete unless the full user experience has been verified.

---

## 7. Backend and API Review

The AI must review and test:

- API route behavior
- Request validation
- Response shape consistency
- Error response consistency
- Authentication requirements
- Authorization enforcement
- Rate limiting if needed
- Input sanitization
- Database reads and writes
- Transaction safety
- Race condition risks
- Pagination
- Filtering
- Sorting
- Empty result handling
- Invalid ID handling
- Permission boundary handling
- API documentation accuracy

Any API that is present but not production-safe must be identified.

---

## 8. Frontend Review

The AI must review and test:

- Page routing
- Navigation
- Forms
- Loading states
- Empty states
- Error states
- Success states
- Validation messages
- Toasts and alerts
- Modal behavior
- Table and list behavior
- Responsive design
- Accessibility basics
- Browser refresh behavior
- Direct URL behavior
- Role-based UI behavior
- Broken links
- Console errors
- Network errors
- Visual polish issues
- Confusing user flows

Any issue that could confuse, block, or frustrate a real user must be documented.

---

## 9. Security and Privacy Review

The AI must check for:

- Exposed secrets
- Hardcoded credentials
- Insecure environment variables
- Missing authentication
- Weak session handling
- Missing authorization checks
- Broken role boundaries
- SQL injection risks
- XSS risks
- CSRF risks
- Unsafe file uploads
- Overly permissive CORS
- Sensitive data in logs
- Sensitive data exposed in API responses
- Missing input validation
- Missing output encoding
- Dependency vulnerabilities
- Insecure cookies
- Insecure tokens
- Missing rate limiting where appropriate
- Excessive data returned to clients
- Privacy risks
- Insecure error messages
- Admin-only functionality exposed to normal users

Security findings must be classified by severity:

- Critical
- High
- Medium
- Low

---

## 10. Deployment and Operations Review

The AI must verify whether the application can realistically be shipped and operated.

Check:

- Production build succeeds
- Production configuration exists
- Required environment variables are documented
- Required secrets are identified
- Database migrations work from a clean state
- App starts from a clean install
- Deployment instructions are accurate
- CI/CD is present or recommended
- Health checks exist
- Logging is useful
- Error tracking exists or is recommended
- Monitoring exists or is recommended
- Backup and recovery needs are documented
- Rollback strategy exists or is recommended
- No local-only paths, URLs, keys, ports, or assumptions exist
- Staging environment needs are identified
- External services are configured for production
- Production data risks are understood

Anything that would block or endanger deployment must be documented.

---

## 11. Testing Readiness Review

The AI must review the current test suite and identify:

- Missing unit tests
- Missing integration tests
- Missing E2E tests
- Missing GUI/browser tests
- Weak assertions
- Tests that pass without proving real behavior
- Over-mocked tests
- Flaky tests
- Tests that do not reflect production behavior
- Critical flows without coverage
- Auth and permission flows without coverage
- API endpoints without coverage
- Database flows without coverage
- Error states without coverage
- Regression risks

The AI must not mark a feature production-ready unless it is covered by automated tests or manually verified with documented evidence.

---

## 12. Blocker Handling Rules

If blocked, the AI must not stop immediately.

The AI must:

1. Diagnose the blocker.
2. Identify the likely root cause.
3. Try reasonable fixes automatically if safe.
4. Search the codebase for related patterns.
5. Use logs, stack traces, tests, and runtime behavior to guide the fix.
6. Create missing setup scripts if needed.
7. Create missing test data if needed.
8. Create mocks or local substitutes only when production services are unavailable.
9. Clearly label anything mocked or simulated as **Not Production-Proven**.
10. Replace broken scripts or commands with working ones when appropriate.
11. Add missing documentation when setup steps are unclear.
12. Add missing environment variable examples when configuration is incomplete.
13. Continue with the next highest-priority task if one area is temporarily blocked.
14. Return to blocked items if another fix unblocks them.

The AI may only stop and ask for help if:

- Required credentials are unavailable.
- Required external services cannot be accessed or simulated.
- The requested action would be unsafe.
- Production data could be damaged.
- Legal, payment, or security-sensitive action requires explicit approval.
- Multiple options have major irreversible consequences.

Every blocker must be documented with:

- What failed
- Error message or evidence
- Root cause if known
- Workarounds attempted
- Result of each workaround
- Current status
- What is needed to fully unblock it
- Whether the item blocks shipping

---

## 13. Automation Requirements

The AI must automate everything practical, including:

- Setup
- Dependency installation
- Environment validation
- Database initialization
- Migrations
- Seed data
- Test execution
- Linting
- Type checks
- Build verification
- API checks
- UI and E2E checks
- Security scans
- Health checks
- Regression checks
- Documentation generation
- Lab environment creation
- Localhost Hyper-V VM creation or validation
- VM inventory capture
- Hyper-V checkpoint creation
- Hyper-V checkpoint restore validation
- Rollback verification
- Verification matrix updates

If a manual step is discovered, convert it into a repeatable script, command, test, checklist, or documented procedure whenever possible.

---

## 14. Autonomous Fixing Rules

After completing the readiness assessment and gap-to-ship plan, the AI must begin fixing issues autonomously when safe.

Fix priority order:

1. Critical ship blockers
2. High-risk production issues
3. Missing proof or tests for critical flows
4. Deployment and security hardening
5. Automation improvements
6. Documentation and UX polish

For each fix, document:

- What was changed
- Why it was changed
- Files or areas changed
- Tests rerun
- Result after the fix
- Remaining risk
- Updated verification status

If one item is blocked, document it and continue with the next highest-priority safe task.

---

## 15. Required Final Report Format

The final report must include the following sections:

A. Executive Summary  
B. Final Ship Recommendation: **SHIP / SHIP WITH KNOWN RISKS / DO NOT SHIP**  
C. Current Production Readiness Score  
D. What Was Actually Verified  
E. What Was Not Proven  
F. Critical Ship Blockers  
G. High-Risk Production Issues  
H. Medium and Low-Risk Issues  
I. Feature Verification Matrix  
J. End-to-End Test Results  
K. GUI/UI Test Results  
L. API and Backend Readiness  
M. Database and Migration Readiness  
N. Authentication and Authorization Readiness  
O. Security and Privacy Review  
P. Deployment and Operations Readiness  
Q. Test Coverage Assessment  
R. Performance and Reliability Review  
S. UX/UI and Accessibility Review  
T. Lab Environment, VM Inventory, Credentials, and Checkpoints  
U. Documentation Gaps  
V. Gap-to-Ship Implementation Plan  
W. Fixes Completed  
X. Tests Added or Updated  
Y. Remaining Risks  
Z. Final Go/No-Go Checklist


## Clean Rebuild Rule for Blocked Lab Testing

When lab validation is blocked by a broken, dirty, unknown, or unreliable VM, the AI must not treat that VM as valid proof.

The default action is to create a new lab-only Hyper-V VM on localhost with new lab-only credentials and continue testing from a clean state.

The AI must document:

- Why the original VM was not trusted
- What new VM was created or recommended
- What new credentials were created or recommended
- What checkpoints were created
- What tests were rerun from the clean VM
- What evidence was collected

The AI must continue testing using safe alternatives instead of stopping after the first blocker.

The AI must not modify, restore, delete, or overwrite unrelated existing VMs.


---

## Post-Report Remediation and Re-Verification Instructions

The AI must not stop after producing the initial ship-readiness report.

After the report is completed, the AI must begin remediation work unless blocked by credentials, external services, unsafe production impact, missing infrastructure, or an irreversible decision requiring approval.

The remediation phase must follow this priority order:

1. Critical ship blockers
2. High-risk security issues
3. High-risk production reliability issues
4. Broken install, build, test, or migration paths
5. Missing proof for critical user flows
6. Missing or weak auth and authorization tests
7. Missing API validation
8. Missing GUI/E2E validation
9. Deployment, rollback, and recovery gaps
10. Monitoring, logging, health check, and operational gaps
11. Medium-risk defects
12. Low-risk defects
13. Documentation and polish

For every finding selected for remediation, the AI must create a remediation record containing:

- Finding ID
- Title
- Severity
- Ship impact
- Root cause
- Files, services, configs, or infrastructure involved
- Proposed fix
- Actual fix applied
- Why the fix is safe
- Tests run before the fix if applicable
- Tests run after the fix
- Evidence collected after the fix
- New status: Proven, Partially Proven, Failed, Not Proven, or Blocked
- Remaining risk
- Whether the item still blocks shipping

The AI must remediate findings using the safest production-ready option.

The AI must prefer:

- Small, targeted fixes over broad rewrites
- Existing codebase patterns over new frameworks
- Secure defaults
- Repeatable automation
- Tests that prove real behavior
- Clean-state validation where practical
- Lab validation for destructive or environment-sensitive fixes
- Documentation updates for every operationally relevant change

The AI must not:

- Hide or delete findings just because a fix was attempted
- Mark a finding resolved without retesting
- Mark a finding Proven without evidence
- Make risky architecture changes without explaining why they are necessary
- Introduce new secrets, hardcoded credentials, or local-only assumptions
- Use production data for testing
- Perform destructive remediation on production, shared staging, unknown systems, or unrelated Hyper-V VMs
- Continue using a dirty or untrusted VM as proof if a clean VM is required
- Skip regression testing after fixes
- Ignore new issues discovered during remediation

If a remediation attempt fails, the AI must document:

- What was attempted
- Why it failed
- Error messages or evidence
- What was changed before failure
- Whether rollback was performed
- Whether a checkpoint restore was used
- Current system state
- Next safest remediation path

If a fix causes regressions, the AI must:

1. Stop expanding the change.
2. Preserve logs and test output.
3. Revert the code change or restore the VM checkpoint if appropriate.
4. Document the regression.
5. Mark the finding as still unresolved.
6. Try a safer fix if practical.
7. Continue with other safe remediation items if blocked.

---

## Required Remediation Workflow

For each remediation item, follow this workflow:

1. Confirm the finding is still valid.
2. Identify the smallest safe fix.
3. Create or update a test that proves the issue.
4. Apply the fix.
5. Run the targeted test.
6. Run related regression tests.
7. Run build, lint, type checks, or security checks as relevant.
8. Validate manually through the UI or API if needed.
9. Update the verification matrix.
10. Update the final report.
11. Mark the item as resolved only if evidence proves it.
12. If not fully proven, mark it Partially Proven, Not Proven, Failed, or Blocked.

A finding is not resolved until the AI has proof.

---

## Remediation Evidence Requirements

Each completed remediation must include evidence such as:

- Passing test output
- Build output
- Lint/type-check output
- API response evidence
- Browser/UI validation notes
- Logs showing corrected behavior
- Database migration output
- Security scan output
- Screenshot references where useful
- Lab VM checkpoint used
- Lab VM checkpoint created after fix
- Rollback or restore result if applicable

Evidence must be specific enough for another engineer to understand what was tested and why the fix is trusted.

---

## Remediation Status Values

Use these values after every remediation attempt:

| Status | Meaning |
|---|---|
| Resolved and Proven | Fix applied and verified with strong evidence. |
| Resolved but Partially Proven | Fix applied, but evidence is incomplete or not production-like. |
| Not Resolved | Fix not completed or did not work. |
| Failed Remediation | Fix caused failure or regression. |
| Blocked | External dependency, credential, infrastructure, unsafe action, or approval required. |
| Deferred | Lower-risk item intentionally left for later with documented rationale. |

Do not use vague statuses such as "done", "looks good", "probably fixed", or "should work".

---

## Required Remediation Tracking Table

After remediation begins, maintain a table like this:

| Finding ID | Finding | Severity | Ship Impact | Fix Applied | Tests/Evidence | Status | Remaining Risk | Blocks Ship? |
|---|---|---|---|---|---|---|---|---|

This table must be updated after each completed or attempted fix.

---

## Post-Remediation Re-Assessment

After completing all safe remediation work, the AI must perform a second ship-readiness assessment.

The second assessment must include:

- What changed since the first report
- Findings resolved
- Findings partially resolved
- Findings still open
- New findings discovered during remediation
- Tests added
- Tests rerun
- Lab validation performed
- Clean-state validation performed
- Remaining blockers
- Remaining high-risk issues
- Updated production readiness score
- Updated final ship recommendation

The AI must explicitly state whether the recommendation changed.

If the original recommendation was **DO NOT SHIP**, the AI must not change it to **SHIP** or **SHIP WITH KNOWN RISKS** unless the blockers were fixed and verified with evidence.

If the AI cannot safely complete remediation, it must still provide:

- The completed initial report
- The remediation items attempted
- What remains blocked
- What is required to continue safely
- The exact next actions for a human engineer

---

## Remediation Commit and Change Hygiene

When modifying code or documentation, the AI must keep changes organized and reviewable.

The AI must:

- Keep fixes focused by issue or area
- Avoid unrelated refactors
- Avoid formatting entire unrelated files unless necessary
- Preserve existing style and conventions
- Update tests with fixes
- Update documentation when behavior, setup, environment variables, or operations change
- Clearly list modified files
- Clearly explain why each file changed

If using Git, the AI should recommend logical commit groups such as:

- `fix: repair production build blocker`
- `test: add auth permission boundary coverage`
- `security: remove hardcoded secret fallback`
- `docs: add deployment and rollback runbook`
- `ops: add health check and logging validation`

The AI must not claim changes were committed unless it actually created commits.
