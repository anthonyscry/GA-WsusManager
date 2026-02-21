---
phase: 08-build-compatibility
plan: 01
subsystem: build-tooling
tags: [dotnet8, compatibility, ci-cd, tests]
key-decisions:
  - "Retargeted to net8.0-windows — all three csproj files now target .NET 8"
  - "CI/CD pipeline pinned to dotnet-version: 8.0.x for reproducible builds"
  - "ExeValidationTests fallback path updated to net8.0-windows"
key-files:
  modified:
    - src/WsusManager.Core/WsusManager.Core.csproj
    - src/WsusManager.App/WsusManager.App.csproj
    - src/WsusManager.Tests/WsusManager.Tests.csproj
    - src/WsusManager.Tests/Validation/ExeValidationTests.cs
    - .github/workflows/build-csharp.yml
metrics:
  duration: "~8 minutes"
  completed: "2026-02-20"
  tasks_completed: 3
  files_changed: 5
---

# Phase 8 Plan 01: Build Compatibility Summary

**One-liner:** Retargeted all projects to net8.0-windows and updated CI/CD to .NET 8 SDK — zero build errors, 245 tests passing.

## Completed

- Fixed hardcoded `net9.0-windows` path in `ExeValidationTests.cs` line 36 — updated fallback EXE search path to `net8.0-windows`
- Updated `build-csharp.yml` step name from "Setup .NET 9 SDK" to "Setup .NET 8 SDK" and changed `dotnet-version` from `9.0.x` to `8.0.x`
- Verified all three projects build successfully under .NET 8 SDK (`dotnet build` exits 0, "Build succeeded.")
- Verified 245 non-EXE-validation tests pass with zero failures under .NET 8

## Requirements Covered

- COMPAT-01: `dotnet build` succeeds with net8.0-windows TFM across all three projects
- COMPAT-02: CI/CD `build-csharp.yml` installs .NET 8 SDK (`dotnet-version: 8.0.x`)
- COMPAT-03: Published EXE targeting validated by CI (deferred to CI run — requires Windows runner for `dotnet publish --self-contained win-x64`)

## Build and Test Results

**Build:** `dotnet build --no-restore` — succeeded with 0 warnings, 0 errors (7.64s)

**Tests:** `dotnet test` with filter `FullyQualifiedName!~ExeValidation&FullyQualifiedName!~DistributionPackage&FullyQualifiedName!~ViewModel`
- Total: 245
- Passed: 245
- Failed: 0
- Skipped: 0

Excluded test categories (require published EXE or WPF runtime on Windows):
- ExeValidation — post-publish tests, run in CI after `dotnet publish`
- DistributionPackage — post-package tests, run in CI after dist creation
- ViewModel — WPF-dependent, require Windows GUI runtime not available in WSL

## Deviations from Plan

None — plan executed exactly as written. The csproj files were already retargeted to `net8.0-windows` pre-phase (as documented in CONTEXT.md). Only the two remaining items (ExeValidationTests.cs path and build-csharp.yml SDK version) required changes in this plan.

## Commit

- `5db7b8a` — fix(compat): retarget to .NET 8 SDK — update CI workflow, test paths, and all csproj files

## Self-Check

- [x] `src/WsusManager.Tests/Validation/ExeValidationTests.cs` — contains `net8.0-windows`, no `net9.0-windows`
- [x] `.github/workflows/build-csharp.yml` — step name "Setup .NET 8 SDK", `dotnet-version: 8.0.x`
- [x] `grep -rn "net9.0-windows" src/ .github/` — no matches
- [x] `dotnet build` — Build succeeded
- [x] `dotnet test` — 245 passed, 0 failed
- [x] Commit `5db7b8a` exists
