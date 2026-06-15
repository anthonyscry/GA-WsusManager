# GA-WsusManager — Implementation & Remediation TODO

> Generated from architecture review, simplification pass, and ship-readiness audit.
> **Status:** Architecture improvements complete. Remediation gaps documented below.

---

## ✅ DONE — Architecture (6 of 6 recommendations)

| # | Recommendation | Status | Files Changed |
|---|---|---|---|
| 1 | **Close WsusServices export gap** — narrowed from 16 to 9 exports | ✅ Done | `Modules/WsusServices.psm1`, `Tests/WsusServices.Tests.ps1` |
| 2 | **Consolidate service definitions** — `Get-WsusServiceDefinitions` as single source of truth | ✅ Done | `Modules/WsusServices.psm1`, `Modules/WsusHealth.psm1`, `Modules/WsusAutoDetection.psm1` |
| 3 | **Deduplicate DB size query** — WsusHealth calls `Get-WsusDatabaseSize` | ✅ Done | `Modules/WsusHealth.psm1` |
| 4 | **Move domain config out of WsusConfig** — 4 functions to domain modules | ✅ Done | `Modules/WsusConfig.psm1`, `Modules/WsusHealth.psm1`, `Modules/WsusOperationRunner.psm1`, `Modules/WsusUtilities.psm1` |
| 5 | **Extract dashboard view-model** — new `WsusDashboardViewModel.psm1` | ✅ Done | `Modules/WsusDashboardViewModel.psm1` (new), `Modules/WsusGuiShell.psm1` |
| 6 | **Separate diagnostic output from data** — `-Quiet` mode + `Write-DiagnosticOutput` helper | ✅ Done | `Modules/WsusHealth.psm1` |

## ✅ DONE — Simplification (7 issues fixed)

| # | Issue | Status | Fix |
|---|---|---|---|
| 1 | **Duplicate service name in `Get-WsusHealthScore`** (scoring bug — all-running yielded 0/30) | ✅ Fixed | Replaced concatenation with `-replace` |
| 2 | **`$script:WsusDiagnosticQuiet` leaks across calls** (state not restored) | ✅ Fixed | `try/finally` save/restore |
| 3 | **Dead `New-WsusDashboardViewModel` body in `WsusGuiShell.psm1`** | ✅ Fixed | Removed old 65-line function |
| 4 | **Dead `OfficeC2R` config data in `WsusConfig.psm1`** | ✅ Fixed | Removed dead config block |
| 5 | **`Write-CheckResult` redundant quiet guard** | ✅ Fixed | Delegates to `Write-DiagnosticOutput` |
| 6 | **try/catch fallback in `WsusAutoDetection`** | ✅ Fixed | `Get-Command` guard |
| 7 | **`$fixableCount` redundant recomputation** | ✅ Fixed | Reuse existing variable |

## ✅ DONE — Ship-Readiness Remediation (1 of 5 open findings fixed)

| # | Finding | Status | Fix |
|---|---|---|---|
| SEC-01 | **Hardcoded credential file path** (`C:\WSUS\sql_credential.xml`) | ✅ Fixed | `Get-WsusSqlCredentialPath` now resolves via `Get-WsusContentPath` from WsusConfig |

---

## ✅ DONE — Phase 1: Test Coverage (Pre-Ship Critical)

### [x] P1-01: Add WsusHostEnvironment.Tests.ps1
- **Why:** Adapter seam module — zero tests for the interface that makes diagnostics testable
- **Files:** `Tests/WsusHostEnvironment.Tests.ps1` (new)
- **Tests needed:** `Get-WsusHostServiceState`, `Invoke-WsusHostSqlQuery`, `Get-WsusHostSqlNetworkingState`, `Get-WsusHostIisContentPath`
- **Effort:** Medium (~150 lines)
- **Blocks:** No

### [x] P1-02: Add WsusRepairPlan.Tests.ps1
- **Why:** Dispatch table for all repair actions has no tests
- **Files:** `Tests/WsusRepairPlan.Tests.ps1` (new)
- **Tests needed:** Each action in `Invoke-WsusRepairAction` dispatches correctly; error handling
- **Effort:** Medium (~120 lines)
- **Blocks:** No

### [x] P1-03: Add WsusDashboardViewModel.Tests.ps1
- **Why:** Newly extracted module — trivial to test, no coverage yet
- **Files:** `Tests/WsusDashboardViewModel.Tests.ps1` (new)
- **Tests needed:** Card construction for online/offline/not-installed states; threshold boundaries
- **Effort:** Small (~80 lines)
- **Blocks:** No

### [x] P1-04: Add WsusDiagnosticResult.Tests.ps1
- **Why:** Typed diagnostic model objects — core data type used across health pipeline
- **Files:** `Tests/WsusDiagnosticResult.Tests.ps1` (new)
- **Tests needed:** `ConvertTo-WsusDiagnosticIssue`, `New-WsusDiagnosticReport`, aliases, type names
- **Effort:** Small (~60 lines)
- **Blocks:** No

---

## ✅ DONE — Phase 2: Security & Reliability (Pre-Ship High)

### [x] P2-01: Add input validation for config JSON loading
- **Why:** `Initialize-WsusConfigFromFile` loads `C:\WSUS\wsus-config.json` without schema validation; a malformed file can corrupt in-memory config
- **Files:** `Modules/WsusConfig.psm1`
- **Fix:** Validate JSON keys against expected schema before merging
- **Test:** Load malformed JSON, verify graceful failure with fallback to defaults
- **Effort:** Small
- **Blocks:** No

### [x] P2-02: Add logging to diagnostic catch blocks
- **Why:** `} catch { $failedSources++ }` silently discards exception context — admin cannot tell what failed
- **Files:** `Modules/WsusHealth.psm1`
- **Fix:** Replace bare counter increment with `Write-Verbose` or `Write-Warning` containing `$_.Exception.Message`
- **Test:** Mock a failure, verify log message
- **Effort:** Small
- **Blocks:** No

### [x] P2-03: Add CI/CD GitHub Actions workflow
- **Why:** No automated build/test gate — changes can break without detection
- **Files:** `.github/workflows/ci.yml` (new)
- **Workflow:** `build.ps1 -SkipCodeReview -SkipTests` → Pester tests → PSScriptAnalyzer
- **Effort:** Medium
- **Blocks:** No (manual testing adequate for small team)

---

## ✅ DONE — Phase 3: Testing Infrastructure (Post-Ship Medium)

### [x] P3-01: Provision clean lab VM with WSUS
- **Why:** Clean-state install/deployment validation requires a Windows VM with WSUS role
- **Tool:** Deploy-Lab (`C:\projects\Deploy-Lab\New-DeployLab.ps1`) or AutomatedLab
- **Checkpoints:** `Clean-OS-Install`, `WSUS-Installed`, `App-Deployed`, `KnownGood`
- **Effort:** Large
- **Blocks:** E2E testing

### [x] P3-02: Restore FlaUI GUI test harness
- **Why:** GUI is 3774-line monolith with no automated testing; FlaUI tests exist but harness is unavailable
- **Requires:** In-repo `Tests\FlaUITestHarness\`; packages installed by `Install-FlaUI.ps1`
- **Test:** `Tests\FlaUI.Tests.ps1` is opt-in via `FlaUI` tag; CI excludes it from unit gates
- **Effort:** Medium
- **Blocks:** GUI validation

### [x] P3-03: Write integration tests against live WSUS
- **Why:** Unit tests mock WSUS API calls; real behavior (DB responses, service interactions, IIS config) is untested
- **Approach:** Pester integration tests that target a lab WSUS server
- **Coverage:** Database operations, service lifecycle, firewall rules, permission enforcement
- **Effort:** Large
- **Blocks:** No

---

## ✅ DONE — Phase 4: GUI Decomposition (Post-Ship Medium)

### [x] P4-01: Extract startup probe logic from WsusManagementGui.ps1
- **Why:** New-WsusGuiStartupProbeResult, Write-WsusGuiStartupProbeResult, Get-WsusGuiProbePopupResult extraction
- **Files:** `Modules/WsusStartupProbe.psm1` (new), `Scripts/WsusManagementGui.ps1`
- **Effort:** Medium

### [x] P4-02: Extract operation completion handlers
- **Why:** `New-WsusGuiOperationCompletion`, `Invoke-WsusGuiOperationCompletion` are testable independently
- **Files:** `Modules/WsusOperationCompletion.psm1` (new), `Scripts/WsusManagementGui.ps1`
- **Effort:** Small

### [x] P4-03: Extract secret management helpers
- **Why:** `New-WsusSecretEnvironment`, `Clear-WsusSecretEnvironment`, `ConvertTo-WsusSecureString` are generic utilities
- **Files:** Move to `WsusUtilities.psm1`, remove from `WsusGuiShell.psm1`
- **Effort:** Small

---

## ✅ DONE — Phase 5: Operations & Documentation (Post-Ship Low)

### [x] P5-01: Create production deployment runbook
- **Why:** No step-by-step guide for deploying WSUS + application to production
- **Content:** Prerequisites, install steps, config, first-run, troubleshooting
- **Files:** `docs/DEPLOYMENT.md` (new)
- **Effort:** Small

### [x] P5-02: Fix wiki docs referencing old hardcoded paths
- **Why:** Various docs still reference `\\FILESERVER\Software\OfficeC2R` and other stale paths
- **Scope:** Review wiki/, docs/, README.md for stale references
- **Effort:** Small

### [x] P5-03: Add rollback strategy documentation
- **Why:** No documented procedure for rolling back a failed deployment/update
- **Content:** PS2EXE backup, config backup, SQL restore points
- **Files:** `docs/ROLLBACK.md` (new)
- **Effort:** Small

---

## 📋 Deferred / Accepted Risks

| Item | Reason for Deferral | Revisit Trigger |
|---|---|---|
| AsyncHelpers.Tests.ps1 | Low usage; simple utility | If new async patterns added |
| WsusNotification.Tests.ps1 | Simple email/notification module | If notification logic grows |
| WsusTrending.Tests.ps1 | Data trending — requires historical data | If trending logic changes |
| WsusProcessHost.Tests.ps1 | Stub module (1 line) — slated for removal | Cleanup pass |
| WsusRepairHarness.Tests.ps1 | Stub module (22 lines) — slated for removal | Cleanup pass |
| WsusOperationPlan.Tests.ps1 | Interface tests exist in architecture tests | If operation plan logic changes |
| Performance/load testing | WSUS server bound — not app bound | If app becomes bottleneck |
| Security penetration testing | Internal admin tool — limited attack surface | If exposed to internet |

---

## Legend

| Status | Meaning |
|---|---|
| ✅ Done | Implemented and verified |
| [ ] Pending | Not started |
| 🚧 In Progress | Active work |
| ❌ Blocked | External dependency required |
| ➡️ Deferred | Intentional deferral with rationale |

---

## Quick Reference: Files Changed During Architecture Work

```
Modified (15):
  Modules/WsusServices.psm1           — narrowed exports, Get-WsusServiceDefinitions
  Modules/WsusConfig.psm1             — removed 4 domain config functions
  Modules/WsusHealth.psm1             — Quiet mode, canonical defs, deduplicated query
  Modules/WsusAutoDetection.psm1      — canonical service defs, simplified init
  Modules/WsusGuiShell.psm1           — removed dashboard VM (dead code)
  Modules/WsusOperationRunner.psm1    — added Get-WsusOperationTimeout
  Modules/WsusUtilities.psm1          — added Get-WsusAppDataPath, configurable credential path
  Scripts/Invoke-WsusMonthlyMaintenance.ps1 — uses generic service functions
  Scripts/WsusManagementGui.ps1       — imports dashboard VM module
  Tests/WsusServices.Tests.ps1        — removed shallow-wrapper tests, added defs tests
  Tests/WsusConfig.Tests.ps1          — removed 18 moved-function tests
  Tests/WsusHealth.Tests.ps1          — added WsusDatabase import
  Tests/WsusArchitectureInterfaces.Tests.ps1 — added VM module import
  Tests/TestSetup.ps1                 — added VM module

New (1):
  Modules/WsusDashboardViewModel.psm1 — extracted dashboard VM
```
