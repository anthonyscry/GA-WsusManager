# Milestones

## v4.0 C# Rewrite (Shipped: 2026-02-20)

**Phases completed:** 7 phases, 7 plans
**Timeline:** 2026-02-19 → 2026-02-20 (2 days)
**Codebase:** 12,674 LOC C# across 88 .cs files + 8 .xaml files
**Tests:** 257 xUnit tests (replaces 323 Pester tests)
**Git range:** 1e16e32..5bb3336 (104 files changed, 14,386 insertions)

**Key accomplishments:**
1. Complete C#/.NET 9 WPF rewrite of GA-WsusManager with single-file EXE distribution
2. Dark-themed dashboard with auto-refresh, server mode toggle, and WSUS installation detection
3. Comprehensive diagnostics with auto-repair (services, firewall, permissions, SQL connectivity)
4. Full database operations: 6-step deep cleanup pipeline, backup/restore with sysadmin enforcement
5. WSUS operations: online sync with 3 profiles, air-gap export/import via robocopy, content reset
6. Installation wizard (PowerShell orchestration), scheduled task management, GPO deployment
7. GitHub Actions CI/CD pipeline with automated build, test, publish, and release

---

## v4.1 Bug Fixes & Polish (Shipped: 2026-02-20)

**Phases completed:** 4 phases (8-11), 4 plans
**Timeline:** 2026-02-20 (same day)
**Codebase:** ~13,000 LOC C# across 88 .cs files + 8 .xaml files
**Tests:** 263 xUnit tests (up from 257)
**Git range:** cf54ed5..HEAD (26 files changed, +1,925 / -109)

**Key accomplishments:**
1. Retargeted entire solution from .NET 9 to .NET 8 LTS (csproj, CI/CD, test paths)
2. Fixed duplicate "WSUS not installed" startup message, added active nav button highlighting
3. Fixed 5 critical operation bugs: DeepCleanup Step 4 GUID→INT, sync classification reflection, age-based decline removal, appcmd full path, boxed int cast
4. Added proper button CanExecute refresh for visual disabling during operations

---


## v4.2 UX & Client Management (Shipped: 2026-02-21)

**Phases completed:** 4 phases (12-15), 9 plans
**Timeline:** 2026-02-20 → 2026-02-21 (1 day)
**Codebase:** ~21,000 LOC C# across 97 .cs files + 8 .xaml files
**Tests:** 336 xUnit tests (up from 263)
**Git range:** 39bfbd6..5c59046 (47 files changed, +7,571 / -57)

**Key accomplishments:**
1. Editable Settings dialog with JSON persistence and immediate effect — no app restart needed
2. Dashboard mode toggle with manual Online/Air-Gap override that survives auto-refresh
3. Operation progress feedback — indeterminate progress bar, [Step N/M] text, success/failure/cancel banners
4. Real-time dialog validation for Install, Transfer, and Schedule dialogs with inline feedback
5. Full WinRM client management toolset — cancel stuck jobs, force check-in, test connectivity, run diagnostics, error code lookup (20 codes)
6. Mass GPUpdate across multiple hosts with per-host progress reporting and partial-success handling
7. Script Generator producing 5 self-contained PowerShell scripts as WinRM fallback for air-gapped hosts

---


## v4.3 Themes (Shipped: 2026-02-21)

**Phases completed:** 2 phases, 2 plans, 4 tasks

**Key accomplishments:**
- (none recorded)

---

