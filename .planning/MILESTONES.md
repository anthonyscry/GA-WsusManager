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

