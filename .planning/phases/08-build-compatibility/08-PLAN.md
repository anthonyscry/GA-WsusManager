---
phase: 08-build-compatibility
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - src/WsusManager.Tests/Validation/ExeValidationTests.cs
  - .github/workflows/build-csharp.yml
autonomous: true
requirements: [COMPAT-01, COMPAT-02, COMPAT-03]

must_haves:
  truths:
    - "`dotnet build` succeeds with net8.0-windows TFM across all three projects"
    - "All 257 non-EXE-validation tests pass under .NET 8"
    - "CI/CD pipeline installs and uses .NET 8 SDK (not .NET 9)"
    - "ExeValidationTests fallback path resolves correctly under net8.0-windows"
  artifacts:
    - path: "src/WsusManager.Tests/Validation/ExeValidationTests.cs"
      provides: "EXE validation tests with correct net8.0-windows fallback path"
      contains: "net8.0-windows"
    - path: ".github/workflows/build-csharp.yml"
      provides: "CI/CD workflow targeting .NET 8 SDK"
      contains: "8.0.x"
  key_links:
    - from: ".github/workflows/build-csharp.yml"
      to: "src/**/*.csproj"
      via: "dotnet build reads TargetFramework from csproj"
      pattern: "dotnet-version: 8\\.0\\.x"
    - from: "ExeValidationTests.cs"
      to: "publish output path"
      via: "fallback path search containing net8.0-windows"
      pattern: "net8\\.0-windows"
---

<objective>
Fix the two remaining hardcoded .NET 9 references so the app builds, tests, and publishes cleanly under .NET 8 SDK.

Purpose: The csproj files were already retargeted to net8.0-windows pre-phase. Two stale .NET 9 references remain: a hardcoded path in ExeValidationTests.cs and the SDK version in build-csharp.yml. Fixing these closes the gap between the csproj TFM and the tooling that builds and validates it.

Output: A clean `dotnet build` and `dotnet test` run locally, and a CI/CD workflow that installs the correct SDK version.
</objective>

<execution_context>
@/home/anthonyscry/.claude/get-shit-done/workflows/execute-plan.md
@/home/anthonyscry/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/STATE.md
@.planning/phases/08-build-compatibility/08-CONTEXT.md
</context>

<tasks>

<task type="auto">
  <name>Task 1: Fix hardcoded net9.0-windows path in ExeValidationTests.cs</name>
  <files>src/WsusManager.Tests/Validation/ExeValidationTests.cs</files>
  <action>
    On line 36 of ExeValidationTests.cs, the first entry in the `searchPaths` array contains a
    hardcoded `net9.0-windows` path segment:

    ```csharp
    Path.Combine(testDir, "..", "..", "..", "..", "WsusManager.App", "bin", "Release",
        "net9.0-windows", "win-x64", "publish", ExeName),
    ```

    Change `net9.0-windows` to `net8.0-windows`. No other changes to this file.

    The fix ensures that when ExeValidationTests runs locally (without the `WSUS_EXE_PATH` env var
    set by CI), the fallback path search will find the EXE in the correct net8.0-windows output
    directory rather than silently missing it.
  </action>
  <verify>
    Confirm the file contains `net8.0-windows` and no remaining `net9.0-windows` references:

    ```bash
    grep -n "net9.0-windows\|net8.0-windows" src/WsusManager.Tests/Validation/ExeValidationTests.cs
    ```

    Expected: single match showing `net8.0-windows` on line 36.
  </verify>
  <done>ExeValidationTests.cs contains `net8.0-windows` on line 36 and zero `net9.0-windows` references.</done>
</task>

<task type="auto">
  <name>Task 2: Update build-csharp.yml to install .NET 8 SDK</name>
  <files>.github/workflows/build-csharp.yml</files>
  <action>
    In `.github/workflows/build-csharp.yml`, the SDK setup step (currently around line 39-42)
    installs .NET 9 instead of .NET 8:

    ```yaml
    - name: Setup .NET 9 SDK
      uses: actions/setup-dotnet@v4
      with:
        dotnet-version: 9.0.x
    ```

    Make two changes to this step:
    1. Change the step `name` from `Setup .NET 9 SDK` to `Setup .NET 8 SDK`
    2. Change `dotnet-version` from `9.0.x` to `8.0.x`

    No other changes to the workflow file. The restore, build, test, publish, and release steps
    are framework-agnostic — they read TargetFramework from the csproj files directly.
  </action>
  <verify>
    Confirm no .NET 9 SDK references remain in the workflow:

    ```bash
    grep -n "9.0.x\|Setup .NET 9\|8.0.x\|Setup .NET 8" .github/workflows/build-csharp.yml
    ```

    Expected: matches showing `Setup .NET 8 SDK` and `8.0.x` — no `9.0.x` or `.NET 9` references.
  </verify>
  <done>build-csharp.yml step name reads "Setup .NET 8 SDK" and dotnet-version reads "8.0.x". Zero .NET 9 SDK references remain.</done>
</task>

<task type="auto">
  <name>Task 3: Verify build and tests pass under .NET 8</name>
  <files></files>
  <action>
    Run the build and test suite from the `src/` directory to confirm all three projects compile
    and all non-EXE-validation tests pass under .NET 8.

    ```bash
    cd /mnt/c/projects/GA-WsusManager/src
    dotnet restore
    dotnet build --configuration Release
    dotnet test WsusManager.Tests/WsusManager.Tests.csproj \
      --configuration Release \
      --verbosity normal \
      --filter "FullyQualifiedName!~ExeValidation&FullyQualifiedName!~DistributionPackage"
    ```

    Note: `dotnet build` without `--no-restore` is intentional — ensures clean restore state.
    The test filter excludes ExeValidation and DistributionPackage tests that require a
    published EXE artifact (those only run in CI after `dotnet publish`).

    If build fails: check that all csproj files target `net8.0-windows` and that
    Microsoft.Extensions.* packages are on 8.0.* versions. These were fixed pre-phase but
    verify if the error mentions a version mismatch.

    If tests fail: read the failure output and fix the specific test. Do NOT skip or remove
    failing tests — fix the root cause.
  </action>
  <verify>
    Build output ends with:
    ```
    Build succeeded.
    ```

    Test output ends with a summary matching:
    ```
    Passed: N, Failed: 0, Skipped: M
    ```
    where N >= 250 (the 257 total minus any EXE-validation tests excluded by the filter).

    No `error CS` or `error MSB` lines in build output.
  </verify>
  <done>`dotnet build` exits 0 with "Build succeeded." and `dotnet test` exits 0 with zero failures.</done>
</task>

</tasks>

<verification>
After all three tasks complete:

1. Zero `net9.0-windows` references in the codebase (outside of comments/docs):
   ```bash
   grep -rn "net9.0-windows" /mnt/c/projects/GA-WsusManager/src/ /mnt/c/projects/GA-WsusManager/.github/
   ```
   Expected: no matches.

2. Build succeeds:
   ```bash
   cd /mnt/c/projects/GA-WsusManager/src && dotnet build --configuration Release
   ```

3. Tests pass:
   ```bash
   cd /mnt/c/projects/GA-WsusManager/src && dotnet test WsusManager.Tests/WsusManager.Tests.csproj \
     --configuration Release \
     --filter "FullyQualifiedName!~ExeValidation&FullyQualifiedName!~DistributionPackage"
   ```
</verification>

<success_criteria>
- COMPAT-01: `dotnet build` succeeds with net8.0-windows TFM on all three projects
- COMPAT-02: CI/CD `build-csharp.yml` installs .NET 8 SDK (`dotnet-version: 8.0.x`)
- COMPAT-03: The publish command produces a self-contained win-x64 single-file EXE (validated in CI via ExeValidation tests after `dotnet publish`)
- All 257 non-EXE-validation tests pass with zero failures
</success_criteria>

<output>
After completion, create `.planning/phases/08-build-compatibility/08-01-SUMMARY.md` with:
- What was changed and why
- Build and test results (pass counts)
- Any issues encountered and how they were resolved
</output>
