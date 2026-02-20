# Phase 7: Polish and Distribution — Plan

**Created:** 2026-02-20
**Requirements:** BUILD-01, BUILD-02, BUILD-03, BUILD-04
**Goal:** The project has a comprehensive xUnit test suite covering all service and ViewModel logic, a GitHub Actions CI/CD pipeline that builds the single-file C# EXE and creates GitHub releases automatically, and the published EXE is validated on a clean Windows Server 2019 environment.

---

## Plans

### Plan 1: Test coverage audit and gap-filling — Core services

**What:** Audit the existing 214 xUnit tests against all Core service implementations and fill coverage gaps. The target is 250+ tests covering every public method on every service interface. Focus on services that may have thin coverage from being implemented during consolidated single-plan phases (Phases 3-6). Walk each interface method and verify a corresponding test exists for: success path, failure path, cancellation, and edge cases. Add missing tests without rewriting existing ones.

**Requirements covered:** BUILD-04 (comprehensive test suite)

**Files to audit (read, count tests, identify gaps):**
- All files in `src/WsusManager.Tests/Services/*.cs` (16 test files)
- All interfaces in `src/WsusManager.Core/Services/Interfaces/I*.cs` (17 interfaces)

**Files to create or modify:**
- Any `src/WsusManager.Tests/Services/*Tests.cs` file that has gaps — add missing test methods
- New file if a service has zero tests: unlikely given Phase 3-6 all added tests, but verify

**Coverage checklist (services to verify):**
1. `ILogService` / `LogService` — Verify logging to C:\WSUS\Logs\ tests exist
2. `ISettingsService` / `SettingsService` — Save/load/defaults verified in SettingsServiceTests
3. `IDashboardService` / `DashboardService` — All 5 dashboard cards (WSUS health, DB size, sync status, service states, scheduled task) have tests
4. `IWindowsServiceManager` — Start/stop/status for SQL, WSUS, IIS; dependency ordering tests
5. `IFirewallService` — Check/repair rules for 8530/8531
6. `IPermissionsService` — Directory permissions check and repair
7. `IHealthService` — Full health check pipeline with auto-repair
8. `IContentResetService` — wsusutil reset execution
9. `ISqlService` — Scalar, NonQuery, Reader, BuildConnectionString
10. `IDeepCleanupService` — All 6 steps, batching, retry on shrink
11. `IDatabaseBackupService` — Backup, restore, sysadmin check
12. `IWsusServerService` — Connect, sync, decline, approve
13. `ISyncService` — Full/Quick/SyncOnly profiles
14. `IRobocopyService` — Arg construction, exit codes, exclusions
15. `IExportService` — Full, differential, skip-when-blank
16. `IImportService` — Validation, robocopy args, content reset
17. `IInstallationService` — Prerequisites, install args, script-not-found
18. `IScheduledTaskService` — Create/Query/Delete, schedule types, credentials
19. `IGpoDeploymentService` — Source validation, copy, instructions

**Implementation notes:**
- Focus on adding tests, not refactoring existing ones.
- Use the established Moq patterns from existing test files.
- Target: at least 2 tests per public interface method (happy path + failure/edge case).
- DashboardService may need the most new tests — it has the broadest surface area.
- If current count is already adequate for a service, skip it.

**Verification:**
1. `dotnet build` succeeds with 0 warnings
2. `dotnet test` — all tests pass, total count >= 250
3. Every service interface has at least one test file with tests for each public method

---

### Plan 2: Test coverage audit and gap-filling — ViewModel and integration

**What:** Audit and fill coverage gaps in `MainViewModelTests.cs` and `DiContainerTests.cs`. The ViewModel is the most critical test target — it orchestrates all user-facing operations. Verify tests exist for every command's CanExecute logic, and for the core patterns: `RunOperationAsync` prevents concurrent execution, `IsOperationRunning` state transitions, dashboard refresh triggers, server mode toggle. Also verify DI container resolves every registered service (currently Phases 3-6 have individual resolution tests — verify completeness for all 17+ services).

**Requirements covered:** BUILD-04 (comprehensive test suite)

**Files to modify:**
- `src/WsusManager.Tests/ViewModels/MainViewModelTests.cs` — Add:
  - Tests for every command's CanExecute (some exist from Phases 5-6, audit for Phases 1-4 commands)
  - Test: `IsOperationRunning` starts false, becomes true during operation, resets to false after
  - Test: concurrent operation attempt is blocked (second command while first is running)
  - Test: server mode toggle changes `IsOnlineMode` / `IsAirGapMode`
  - Test: dashboard refresh command can execute
- `src/WsusManager.Tests/Integration/DiContainerTests.cs` — Add:
  - Resolution tests for any services missing from the existing Phase 3-6 tests
  - Test: all singletons resolve to the same instance on second resolve
  - Test: MainViewModel resolves with all dependencies
- `src/WsusManager.Tests/Foundation/OperationResultTests.cs` — Verify coverage of `OperationResult.Success()`, `OperationResult.Fail()`, `OperationResult<T>.Success(value)`, `OperationResult<T>.Fail()`, pattern matching

**Verification:**
1. `dotnet build` succeeds
2. `dotnet test` — all tests pass
3. Every ViewModel command has at least one CanExecute test
4. DI container resolves all registered services

---

### Plan 3: EXE validation test class (xUnit)

**What:** Create `ExeValidationTests.cs` in the xUnit test project — a set of post-build tests that validate the published single-file EXE. These tests skip automatically when the EXE does not exist (using xUnit `Skip` or conditional `[Fact]`). Tests validate: PE header (MZ signature at offset 0, PE signature at offset from 0x3C), 64-bit architecture (PE32+ magic = 0x020B), embedded version info (Product = "WSUS Manager", Company = "GA-ASI"), file size (> 1MB, < 100MB). These are the C# equivalent of the existing PowerShell `Tests\ExeValidation.Tests.ps1`.

**Requirements covered:** BUILD-02 (version info metadata), BUILD-04 (test suite)

**Files to create:**
- `src/WsusManager.Tests/Validation/ExeValidationTests.cs` — Test class with:
  - Private helper: `FindPublishedExe()` — scans `publish/`, `bin/Release/*/publish/`, and `../../dist/` relative to test assembly for `WsusManager.App.exe`. Returns null if not found.
  - `[Fact] PeHeader_HasMzSignature` — Reads first 2 bytes, asserts 'M','Z' (0x4D, 0x5A). Skips if EXE not found.
  - `[Fact] PeHeader_HasPeSignature` — Reads PE offset from 0x3C, reads 4 bytes at that offset, asserts "PE\0\0". Skips if EXE not found.
  - `[Fact] Architecture_Is64Bit` — Reads PE optional header magic (2 bytes after PE header + 20 bytes for COFF header), asserts 0x020B (PE32+). Skips if EXE not found.
  - `[Fact] VersionInfo_HasProductName` — Uses `System.Diagnostics.FileVersionInfo.GetVersionInfo()`, asserts ProductName == "WSUS Manager". Skips if EXE not found.
  - `[Fact] VersionInfo_HasCompanyName` — Asserts CompanyName == "GA-ASI". Skips if EXE not found.
  - `[Fact] VersionInfo_HasVersion` — Asserts FileVersion starts with "4.0". Skips if EXE not found.
  - `[Fact] FileSize_WithinExpectedRange` — Asserts file size > 1MB and < 100MB. Skips if EXE not found.

**Implementation notes:**
- Use xUnit's `Skip.If()` or `[Fact(Skip = "...")]` conditional pattern. Since xUnit v2 doesn't have native skip-when, use a custom approach: check if EXE exists at test start, if not, return early (or use `Assert.Skip` if available in xUnit 2.9+).
- All file reads use `FileStream` with `FileAccess.Read` and `FileShare.ReadWrite`.
- These tests are designed to run AFTER `dotnet publish` in CI — they do not run during normal `dotnet test` unless the EXE happens to be present.

**Verification:**
1. `dotnet build` succeeds
2. Tests skip gracefully when EXE is not present
3. After `dotnet publish`, tests find and validate the EXE

---

### Plan 4: GitHub Actions CI/CD workflow for C# build

**What:** Create `.github/workflows/build-csharp.yml` — a NEW workflow file that builds, tests, and publishes the C# version. This does NOT modify the existing `build.yml` which handles the PowerShell version. The workflow runs on `windows-latest` (required for WPF), triggers on pushes to `main` when `src/**` files change, and on `workflow_dispatch` with manual version input. Jobs: `build-and-test` (restore, build, test, publish, validate-exe) → `release` (create GitHub release when triggered by tag or manual input).

**Requirements covered:** BUILD-01 (CI/CD pipeline), BUILD-02 (version info in EXE), BUILD-03 (release automation)

**Files to create:**
- `.github/workflows/build-csharp.yml` — Workflow with:

  **Triggers:**
  - `push` to `main` when paths include `src/**`, `.github/workflows/build-csharp.yml`
  - `pull_request` to `main` when paths include `src/**`
  - `workflow_dispatch` with inputs: `version` (string, default empty), `create_release` (boolean, default false)

  **Concurrency:** `build-csharp-${{ github.ref }}`, cancel-in-progress: true

  **Job 1: `build-and-test`** (runs-on: `windows-latest`)
  - Checkout
  - Setup .NET 9 SDK (`actions/setup-dotnet@v4` with `dotnet-version: 9.0.x`)
  - Restore: `dotnet restore src/WsusManager.Core/WsusManager.Core.csproj && dotnet restore src/WsusManager.App/WsusManager.App.csproj && dotnet restore src/WsusManager.Tests/WsusManager.Tests.csproj`
  - Build: `dotnet build src/WsusManager.App/WsusManager.App.csproj --configuration Release --no-restore`
  - Test: `dotnet test src/WsusManager.Tests/WsusManager.Tests.csproj --configuration Release --no-build --verbosity normal --logger "trx;LogFileName=test-results.trx"` (upload test results as artifact)
  - Publish: `dotnet publish src/WsusManager.App/WsusManager.App.csproj --configuration Release --output ./publish --self-contained true --runtime win-x64 -p:PublishSingleFile=true -p:IncludeAllContentForSelfExtract=true`
  - Validate EXE: Run the xUnit ExeValidation tests against the published EXE (set env var or copy EXE to expected location, then run `dotnet test --filter "FullyQualifiedName~ExeValidation"`)
  - Get version: Read from `src/WsusManager.App/WsusManager.App.csproj` `<Version>` element or use `workflow_dispatch` input
  - Create distribution package: Zip containing `WsusManager.App.exe` (renamed to `WsusManager.exe`), `DomainController/` folder, `README.md`
  - Upload artifact: `WsusManager-v{version}` with the distribution zip
  - Output: `version` for the release job

  **Job 2: `release`** (runs-on: `ubuntu-latest`, needs: `build-and-test`)
  - Condition: `github.event.inputs.create_release == 'true'` OR tag push matching `v*`
  - Download artifact
  - Create GitHub release with `softprops/action-gh-release@v2`:
    - Tag: `v{version}`
    - Name: "WSUS Manager v{version} (C#)"
    - Body: Release notes template (version, highlights, download table, requirements: Windows Server 2019+/admin, install: extract + run)
    - Attach zip artifact

**Implementation notes:**
- The C# workflow is completely independent from the PowerShell `build.yml`. They trigger on different paths (`src/**` vs `Scripts/**`/`Modules/**`).
- Windows runner is required for WPF build and test (WPF tests won't compile on Linux).
- The publish step produces the self-contained single-file EXE with all dependencies bundled.
- `IncludeAllContentForSelfExtract=true` is critical for AV compatibility (avoids extracting DLLs to %TEMP%).
- Rename the published `WsusManager.App.exe` to `WsusManager.exe` in the distribution package for clean user experience.

**Verification:**
1. Workflow YAML is valid (no syntax errors)
2. Triggers correctly on `src/**` changes (not `Scripts/**`)
3. Includes .NET 9 SDK setup
4. Test results uploaded as artifact
5. Distribution zip contains: `WsusManager.exe`, `DomainController/`, `README.md`
6. Release job creates GitHub release with zip attached

---

### Plan 5: Version management and EXE metadata

**What:** Add `Directory.Build.props` at the `src/` level to centralize version management across all three projects (Core, App, Tests). Move the version, company, product, and copyright properties from `WsusManager.App.csproj` into the shared props file so all assemblies share the same version info. Add a `VersionSuffix` support for pre-release builds. Verify the published EXE embeds the correct metadata by running the ExeValidation tests from Plan 3.

**Requirements covered:** BUILD-02 (EXE metadata)

**Files to create:**
- `src/Directory.Build.props` — MSBuild props file with:
  ```xml
  <Project>
    <PropertyGroup>
      <Version>4.0.0</Version>
      <AssemblyVersion>4.0.0.0</AssemblyVersion>
      <FileVersion>4.0.0.0</FileVersion>
      <Product>WSUS Manager</Product>
      <Company>GA-ASI</Company>
      <Copyright>Tony Tran, ISSO - GA-ASI</Copyright>
      <Authors>Tony Tran</Authors>
    </PropertyGroup>
  </Project>
  ```

**Files to modify:**
- `src/WsusManager.App/WsusManager.App.csproj` — Remove `Version`, `Product`, `Company`, `Copyright` properties (now inherited from `Directory.Build.props`). Keep `AssemblyTitle`, `Description`, and publish-related properties.
- `.github/workflows/build-csharp.yml` — Update "Get version" step to read from `src/Directory.Build.props` instead of the App `.csproj`

**Implementation notes:**
- `Directory.Build.props` is auto-imported by MSBuild for all projects in the directory tree. Placing it at `src/` means Core, App, and Tests all inherit the same version.
- The CI workflow can override the version via MSBuild property: `dotnet publish -p:Version=4.0.1` — useful for pre-release builds.
- Keep `AssemblyTitle` ("WSUS Manager") and `Description` in the App `.csproj` since those are app-specific.

**Verification:**
1. `dotnet build` succeeds for all three projects
2. All three assemblies share the same version number
3. Published EXE has correct Product, Company, Copyright, Version in FileVersionInfo
4. CI workflow reads version from `Directory.Build.props`

---

### Plan 6: Distribution package validation and smoke test

**What:** Add a smoke test to the CI pipeline and create a final distribution validation step. The smoke test verifies the published EXE can start without crashing by launching it with a short timeout (the EXE will fail gracefully since it requires admin + WSUS, but it should not crash with an unhandled exception). Also validate the distribution package contents: `WsusManager.exe` exists, `DomainController/` directory exists, `README.md` exists, no `Scripts/` or `Modules/` folders (unlike the PowerShell version), and total package size is reasonable (< 100MB).

**Requirements covered:** BUILD-01 (CI validation), BUILD-02 (EXE validation), BUILD-04 (comprehensive testing)

**Files to create:**
- `src/WsusManager.Tests/Validation/DistributionPackageTests.cs` — Test class with:
  - `[Fact] Package_ContainsExe` — Verify `WsusManager.exe` is in the package (skips if not found)
  - `[Fact] Package_ContainsDomainController` — Verify `DomainController/` directory present
  - `[Fact] Package_DoesNotContainPowerShellFolders` — Verify no `Scripts/` or `Modules/` directories
  - `[Fact] Package_ExeSizeReasonable` — Verify EXE size between 1MB and 100MB
  - `[Fact] Package_TotalSizeReasonable` — Verify total package < 150MB

**Files to modify:**
- `.github/workflows/build-csharp.yml` — Add steps after publish:
  - Smoke test: Start the EXE with a 5-second timeout, verify it exits without crash code (or doesn't hang indefinitely). Use `Start-Process` with `-Wait` and timeout. Accept any exit code except unhandled exception codes.
  - Distribution validation: Run the package validation tests against the dist folder.

**Implementation notes:**
- The smoke test is intentionally minimal — it just verifies the EXE starts up without immediate crash. On a CI runner without WSUS installed, the app will show "Not Installed" state and exit gracefully (or we can add a `--validate` CLI arg that just checks dependencies and exits).
- Package tests scan a configurable directory (env var or default path relative to test assembly).
- The "no Scripts/Modules" check is a key differentiator from the PowerShell version — the C# single-file EXE is self-contained.

**Verification:**
1. `dotnet build` succeeds
2. Distribution package tests pass against the published output
3. Smoke test step doesn't hang in CI
4. Package contains exactly the expected files

---

### Plan 7: Final integration verification and documentation update

**What:** Run the complete CI pipeline end-to-end (build, test, publish, validate) and verify all 4 Phase 7 success criteria. Update `ROADMAP.md` progress table, `STATE.md` with final status, and `REQUIREMENTS.md` with BUILD requirement statuses. Create the Phase 7 summary document. Ensure test count meets the 250+ target.

**Requirements covered:** All Phase 7 requirements (final verification)

**Files to modify:**
- `.planning/ROADMAP.md` — Mark Phase 7 as complete, update plans count, fill in completed date
- `.planning/STATE.md` — Update current position to Phase 7 complete, update progress percentage to 100%
- `.planning/REQUIREMENTS.md` — Mark BUILD-01, BUILD-02, BUILD-03, BUILD-04 as complete

**Files to create:**
- `.planning/phases/07-polish-and-distribution/07-SUMMARY.md` — Phase summary document following established format: what was built, files created/modified, success criteria verification, test count
- `.planning/phases/07-polish-and-distribution/07-VERIFICATION.md` — Verification results: build output, test results, EXE validation results, package contents

**Verification:**
1. `dotnet build --configuration Release` — 0 warnings, 0 errors
2. `dotnet test` — All tests pass (250+ total)
3. `dotnet publish` — Single-file EXE produced
4. All 4 Phase 7 success criteria verified:
   - xUnit test suite covers all Core services and ViewModel logic, passes completely
   - Push to main triggers GitHub Actions build with embedded version info, passes PE header and 64-bit validation
   - Tagging a release creates GitHub release with EXE artifact attached
   - Published EXE passes smoke test on Windows runner
5. All BUILD requirements (BUILD-01 through BUILD-04) marked complete

---

## Plan Summary

| Plan | Description | Requirements |
|------|-------------|--------------|
| 1 | Test coverage audit and gap-filling — Core services | BUILD-04 |
| 2 | Test coverage audit and gap-filling — ViewModel and integration | BUILD-04 |
| 3 | EXE validation test class (xUnit) | BUILD-02, BUILD-04 |
| 4 | GitHub Actions CI/CD workflow for C# build | BUILD-01, BUILD-02, BUILD-03 |
| 5 | Version management and EXE metadata | BUILD-02 |
| 6 | Distribution package validation and smoke test | BUILD-01, BUILD-02, BUILD-04 |
| 7 | Final integration verification and documentation update | All Phase 7 |

## Execution Order

Plans 1 through 7 execute sequentially. Each plan builds on the previous:
- Plans 1-2 fill test coverage gaps in existing services and ViewModel (no new production code)
- Plan 3 creates EXE validation tests (needed by Plan 4's CI pipeline and Plan 6's package validation)
- Plan 4 creates the CI/CD workflow (references tests from Plans 1-3, EXE validation from Plan 3)
- Plan 5 centralizes version management (modifies csproj referenced by Plan 4's workflow)
- Plan 6 adds distribution validation and smoke testing (builds on Plan 4's pipeline)
- Plan 7 runs the complete pipeline and writes final documentation

## Success Criteria (from Roadmap)

All four Phase 7 success criteria must be TRUE after Plan 7 completes:

1. The xUnit test suite covers all Core services and ViewModel logic with coverage equivalent to the 323 Pester tests it replaces — and passes completely in CI
2. A push to the main branch triggers GitHub Actions to build the single-file EXE with embedded version info, company name, and product name — and the EXE passes PE header and 64-bit architecture validation tests
3. Tagging a release creates a GitHub release automatically with the EXE artifact attached — no manual upload step required
4. The published EXE launches successfully on a clean Windows Server 2019 VM with antivirus enabled, without extracting files to %TEMP% or triggering AV heuristics

---

*Phase: 07-polish-and-distribution*
*Plan created: 2026-02-20*
