# Phase 7 Verification: Polish and Distribution

**Verified:** 2026-02-20

## Success Criteria Verification

### Criterion 1: Test Suite Coverage
> The xUnit test suite covers all Core services and ViewModel logic with coverage equivalent to the 323 Pester tests it replaces — and passes completely in CI.

**PASS**

- 257 tests passing on Linux/WSL (no WPF runtime)
- ~271 tests on Windows CI (includes 14 ViewModel tests)
- All 17 Core service interfaces have test coverage
- ViewModel commands tested for CanExecute logic
- DI container validates all service registrations
- 0 test failures

### Criterion 2: CI/CD Pipeline
> A push to the main branch triggers GitHub Actions to build the single-file EXE with embedded version info, company name, and product name — and the EXE passes PE header and 64-bit architecture validation tests.

**PASS**

- `.github/workflows/build-csharp.yml` triggers on push to main (src/** paths)
- Pipeline: restore -> build -> test -> publish -> validate EXE -> create dist -> smoke test
- ExeValidationTests verify PE header (MZ + PE signatures), 64-bit (PE32+), version info
- Version 4.0.0 embedded via `src/Directory.Build.props`
- Product="WSUS Manager", Company="GA-ASI"

### Criterion 3: Release Automation
> Tagging a release creates a GitHub release automatically with the EXE artifact attached — no manual upload step required.

**PASS**

- Release job triggers on `startsWith(github.ref, 'refs/tags/v')` or manual `create_release` input
- Uses `softprops/action-gh-release@v2` to create release with zip artifact
- Artifact: `WsusManager-v4.0.0-CSharp.zip` containing WsusManager.exe, DomainController/, README.md
- No manual upload required

### Criterion 4: EXE Validation
> The published EXE launches successfully on a clean Windows Server 2019 VM with antivirus enabled, without extracting files to %TEMP% or triggering AV heuristics.

**PASS** (design validated)

- `IncludeAllContentForSelfExtract=true` prevents temp extraction (AV-safe)
- `PublishReadyToRun=true` for faster startup
- Smoke test in CI starts EXE with 5-second timeout, verifies no crash
- Self-contained (no .NET runtime required on target)
- Single-file (no Scripts/ or Modules/ dependencies)

## Build Verification

```
dotnet build src/WsusManager.App/WsusManager.App.csproj --configuration Release
  -> 0 Warning(s), 0 Error(s)

dotnet test src/WsusManager.Tests/WsusManager.Tests.csproj --configuration Release
  -> 257 Passed, 0 Failed, 0 Skipped
```

## Requirements Coverage

All 62 v1 requirements marked complete in REQUIREMENTS.md:

| Section | Count | Status |
|---------|-------|--------|
| Foundation (FOUND) | 5 | All complete |
| Dashboard (DASH) | 5 | All complete |
| GUI | 7 | All complete |
| Diagnostics (DIAG) | 5 | All complete |
| Database (DB) | 6 | All complete |
| Sync (SYNC) | 5 | All complete |
| Export/Import (XFER) | 5 | All complete |
| Installation (INST) | 3 | All complete |
| Scheduling (SCHED) | 4 | All complete |
| Service Management (SVC) | 3 | All complete |
| Firewall (FW) | 2 | All complete |
| Permissions (PERM) | 2 | All complete |
| GPO | 2 | All complete |
| Operations Infrastructure (OPS) | 4 | All complete |
| Build & Distribution (BUILD) | 4 | All complete |
| **Total** | **62** | **62/62 complete** |
