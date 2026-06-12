# AI Ship-Readiness Final Report Template

Use this exact structure for the final report.

---

# A. Executive Summary

Summarize the application readiness in plain language.

Include:

- Overall readiness
- Biggest blockers
- Highest-risk issues
- Whether the app can safely ship
- What must happen next

---

# B. Final Ship Recommendation

Choose one:

- **SHIP**
- **SHIP WITH KNOWN RISKS**
- **DO NOT SHIP**

Explain why.

---

# C. Current Production Readiness Score

Provide a score from 0 to 100.

Use this guide:

| Score | Meaning |
|---|---|
| 90-100 | Production-ready with minor risks |
| 75-89 | Close, but requires fixes or proof |
| 50-74 | Significant gaps remain |
| 25-49 | Not ready; major blockers |
| 0-24 | Cannot assess or fundamentally broken |

---

# D. What Was Actually Verified

List only items actually verified by evidence.

Include:

- Command run
- Test performed
- Manual validation performed
- Runtime behavior observed
- Logs or screenshots collected
- Result

---

# E. What Was Not Proven

List all unproven areas.

For each item include:

- What is unproven
- Why it matters
- What evidence is needed
- Whether it blocks shipping

---

# F. Critical Ship Blockers

For each blocker:

- Issue
- Evidence
- Impact
- Reproduction steps
- Required fix
- Test needed to prove fix
- Ship impact

---

# G. High-Risk Production Issues

For each high-risk issue:

- Issue
- Evidence
- Impact
- Required fix
- Test needed
- Ship impact

---

# H. Medium and Low-Risk Issues

Group by risk level.

---

# I. Feature Verification Matrix

| Feature / Workflow | Expected Behavior | Current Status | How Tested | Evidence | Result | Remaining Gaps | Risk | Required Fix or Proof | Recommended Test Coverage | Ship Impact |
|---|---|---|---|---|---|---|---|---|---|---|

Allowed result values:

- Proven
- Partially Proven
- Not Proven
- Failed
- Blocked

Allowed risk values:

- Critical
- High
- Medium
- Low

Allowed ship impact values:

- Blocks Ship
- Ship Risk
- Acceptable Risk

---

# J. End-to-End Test Results

Document all user-flow testing.

Include:

- User journey
- Steps tested
- Expected result
- Actual result
- Evidence
- Pass/fail
- Gaps

---

# K. GUI/UI Test Results

Include:

- Pages tested
- Buttons clicked
- Forms submitted
- Modals tested
- Direct URLs tested
- Refresh/back button behavior
- Empty states
- Error states
- Mobile/responsive checks
- Accessibility checks
- Console errors
- Network errors

---

# L. API and Backend Readiness

Include:

- API routes tested
- Request validation
- Error responses
- Auth requirements
- Authorization enforcement
- Database reads/writes
- Pagination/filtering/sorting
- Invalid inputs
- Missing coverage

---

# M. Database and Migration Readiness

Include:

- Database setup result
- Migration result
- Seed data result
- Rollback result
- Clean-state result
- Data integrity risks
- Backup/recovery risks

---

# N. Authentication and Authorization Readiness

Include:

- Login
- Logout
- Registration if applicable
- Password reset if applicable
- Session handling
- Expired sessions
- Unauthorized access
- Role boundaries
- Admin access
- Normal user access
- Permission bypass attempts

---

# O. Security and Privacy Review

Classify findings as:

- Critical
- High
- Medium
- Low

Include:

- Evidence
- Impact
- Required fix
- Test needed after fix

---

# P. Deployment and Operations Readiness

Include:

- Production build status
- Production config status
- Environment variable documentation
- Secrets handling
- CI/CD
- Health checks
- Logging
- Monitoring
- Error tracking
- Backups
- Rollback
- Recovery
- Local-only assumptions

---

# Q. Test Coverage Assessment

Include:

- Existing tests
- Tests run
- Tests failed
- Weak tests
- Missing unit tests
- Missing integration tests
- Missing E2E tests
- Missing GUI/browser tests
- Missing security tests
- Missing regression tests

---

# R. Performance and Reliability Review

Include:

- Startup behavior
- Load concerns
- Slow queries
- Network failure behavior
- Retry behavior
- Timeout behavior
- Race condition risks
- Resource usage concerns
- Reliability gaps

---

# S. UX/UI and Accessibility Review

Include:

- Confusing flows
- Broken navigation
- Missing states
- Error clarity
- Form usability
- Accessibility basics
- Mobile/responsive behavior
- Visual polish risks

---

# T. Lab Environment, VM Inventory, Credentials, and Checkpoints

Include:

- Whether AutomatedLab was used
- If not used, why not
- Alternative lab approach used
- Lab purpose
- VM inventory
- Credential inventory
- Checkpoint inventory
- Clean-state tests performed
- Restore tests performed
- Rollback tests performed
- Evidence collected
- Lab limitations
- Items marked **Not Proven — Lab Validation Required**

---

# U. Documentation Gaps

Include missing or inaccurate:

- README instructions
- Developer setup
- Environment variables
- Secrets
- Deployment steps
- Rollback steps
- Troubleshooting steps
- API documentation
- User documentation
- Runbooks

---

# V. Gap-to-Ship Implementation Plan

Group by phase.

## Phase 1: Critical Ship Blockers

| Issue | Why It Matters | Risk If Not Fixed | Fix | Area | Test Required | Definition of Done | Priority | Effort |
|---|---|---|---|---|---|---|---|---|

## Phase 2: High-Risk Production Issues

Use the same table.

## Phase 3: Required Proof and Testing Gaps

Use the same table.

## Phase 4: Security and Deployment Hardening

Use the same table.

## Phase 5: UX, Documentation, and Operational Readiness

Use the same table.

---

# W. Fixes Completed

For each fix:

- What changed
- Why it changed
- Files changed
- Tests rerun
- Result
- Remaining risk

---

# X. Tests Added or Updated

For each test:

- Test name
- Type
- What it proves
- Result
- Remaining coverage gap

---

# Y. Remaining Risks

List known remaining risks and whether they are acceptable.

---

# Z. Final Go/No-Go Checklist

| Item | Status | Evidence / Notes |
|---|---|---|
| App installs from a clean state |  |  |
| App runs locally |  |  |
| Production build succeeds |  |  |
| Existing tests pass |  |  |
| Lint passes |  |  |
| Type checks pass |  |  |
| Database migrations work |  |  |
| Critical user flows are proven |  |  |
| Auth flows are proven |  |  |
| Permission boundaries are proven |  |  |
| APIs are validated |  |  |
| GUI flows are tested |  |  |
| Error states are tested |  |  |
| Security issues are reviewed |  |  |
| No exposed secrets |  |  |
| Required env vars documented |  |  |
| Deployment path documented |  |  |
| Monitoring/logging strategy exists |  |  |
| Rollback strategy exists |  |  |
| Lab validation completed where required |  |  |
| VM checkpoints documented where required |  |  |
| Known risks documented |  |  |
| Critical blockers resolved |  |  |
| High-risk issues resolved or explicitly accepted |  |  |


---

# AA. Post-Report Remediation Plan

List each finding selected for remediation.

| Finding ID | Finding | Severity | Ship Impact | Root Cause | Proposed Fix | Test Required | Priority |
|---|---|---|---|---|---|---|---|

---

# AB. Remediation Work Completed

For each remediation completed or attempted, include:

- Finding ID
- What was changed
- Why it was changed
- Files changed
- Tests run before fix
- Tests run after fix
- Evidence collected
- Result
- Remaining risk
- Whether the finding still blocks ship

---

# AC. Remediation Tracking Table

| Finding ID | Finding | Severity | Ship Impact | Fix Applied | Tests/Evidence | Status | Remaining Risk | Blocks Ship? |
|---|---|---|---|---|---|---|---|---|

Allowed remediation statuses:

- Resolved and Proven
- Resolved but Partially Proven
- Not Resolved
- Failed Remediation
- Blocked
- Deferred

---

# AD. Post-Remediation Re-Assessment

Include:

- What changed since the initial report
- Findings resolved
- Findings partially resolved
- Findings still open
- New findings discovered
- Tests added
- Tests rerun
- Lab validation performed
- Clean-state validation performed
- Remaining blockers
- Remaining high-risk issues
- Updated readiness score
- Updated ship recommendation
- Whether the recommendation changed

---

# AE. Human Follow-Up Required

List only items that require human action.

For each item include:

- Required action
- Why AI could not safely complete it
- Credential, access, approval, or infrastructure needed
- Exact next step
- Whether it blocks shipping
