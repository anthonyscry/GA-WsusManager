# CI/CD Pipeline Documentation

WSUS Manager uses GitHub Actions for continuous integration (CI) and continuous deployment (CD). This document explains the workflows, when they run, and what they produce.

## Workflow Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     GitHub Actions Workflows                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  Push/PR to main                                                  │
│  ┌──────────────────────────────────────┐                       │
│  │   Build C# WSUS Manager               │                       │
│  │   - Restore, build, test              │                       │
│  │   - Code coverage                     │                       │
│  │   - Publish single-file EXE           │                       │
│  └──────────────────────────────────────┘                       │
│                     │                                            │
│                     ▼                                            │
│              Artifacts Produced                                   │
│              - test-results (TRX)                                │
│              - coverage-report (HTML)                            │
│              - wsusmanager-exe (ZIP)                             │
│                                                                   │
│  Push/PR to main (PowerShell paths)                               │
│  ┌──────────────────────────────────────┐                       │
│  │   Build PowerShell GUI (Legacy)       │                       │
│  │   - Code review                       │                       │
│  │   - Pester tests                      │                       │
│  │   - Compile to EXE                    │                       │
│  └──────────────────────────────────────┘                       │
│                     │                                            │
│                     ▼                                            │
│              Artifacts Produced                                   │
│              - test-results (NUnit)                              │
│              - WsusManager-vX.X.X (ZIP)                          │
│                                                                   │
│  Git Tag Push (e.g., v4.4.0)                                      │
│  ┌──────────────────────────────────────┐                       │
│  │   Create Release                      │                       │
│  │   - Download EXE artifact             │                       │
│  │   - Create GitHub release            │                       │
│  │   - Upload EXE as asset              │                       │
│  └──────────────────────────────────────┘                       │
│                     │                                            │
│                     ▼                                            │
│              GitHub Release Created                               │
│                                                                   │
│  Scheduled (Daily 2AM UTC) + Manual                               │
│  ┌──────────────────────────────────────┐                       │
│  │   Repository Hygiene                  │                       │
│  │   - Close stale PRs                   │                       │
│  │   - Delete old branches               │                       │
│  │   - Delete long-running workflow runs │                       │
│  └──────────────────────────────────────┘                       │
│                                                                   │
│  Dependabot PR Opened                                             │
│  ┌──────────────────────────────────────┐                       │
│  │   Dependabot Auto-Merge               │                       │
│  │   - Auto-approve minor/patch updates │                       │
│  │   - Auto-merge dependency updates    │                       │
│  └──────────────────────────────────────┘                       │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

## Workflows

### Build C# WSUS Manager

**File:** `.github/workflows/build-csharp.yml`

**Purpose:** Build, test, and package the C# application on every push and pull request to main branch.

**Triggers:**
- Push to `main` branch (paths: `src/**`, `.github/workflows/build-csharp.yml`)
- Pull request to `main` branch (paths: `src/**`)
- Manual trigger (`workflow_dispatch`) with optional version and release parameters

**Jobs:**

#### build-and-test
Main CI job that builds and tests the C# application.

**Steps:**
1. **Checkout** - Clone repository
2. **Setup .NET 8 SDK** - Install .NET 8 SDK
3. **Restore dependencies** - Restore NuGet packages for all projects
4. **Build** - Build solution in Release configuration
5. **Static Analysis Gate** - Enforce zero compiler warnings (Phase 19 quality gate)
6. **Run tests** - Run xUnit tests with code coverage (excludes ExeValidation and DistributionPackage tests)
7. **Upload test results** - Save xUnit test results (TRX format)
8. **Generate coverage report** - Create HTML coverage report using ReportGenerator
9. **Upload coverage report** - Save HTML coverage report
10. **Publish single-file EXE** - Publish self-contained EXE (win-x64, single-file)
11. **Validate published EXE** - Run ExeValidation tests against published EXE
12. **Get version** - Extract version from Directory.Build.props or App csproj
13. **Create distribution package** - Package EXE into ZIP archive
14. **Validate distribution package** - Run DistributionPackage tests
15. **Smoke test EXE** - Start EXE briefly to verify no crash on startup
16. **Upload distribution artifact** - Save EXE ZIP as workflow artifact

**Artifacts:**
- `test-results` - xUnit test results (TRX format)
- `code-coverage-report` - HTML coverage report from ReportGenerator
- `WsusManager-v{version}-CSharp` - Distribution ZIP containing EXE

**Status:** Required for merge - PR checks must pass before merge.

#### benchmark
Performance regression detection (manual trigger only).

**Steps:**
1. **Checkout** - Clone repository
2. **Setup .NET 8 SDK** - Install .NET 8 SDK
3. **Restore benchmarks** - Restore BenchmarkDotNet project
4. **Build benchmarks** - Build benchmark project
5. **Run all benchmarks** - Execute BenchmarkDotNet benchmarks
6. **Upload benchmark results** - Save HTML and CSV results
7. **Detect regressions** - Compare current results to baselines (10% threshold)

**Artifacts:**
- `benchmark-results` - BenchmarkDotNet HTML reports and CSV data

**Status:** Optional - runs only on manual workflow_dispatch.

#### release
Create GitHub release when version tag is pushed.

**Triggers:**
- Git tag push matching `v*.*.*` pattern (e.g., `v4.4.0`)
- Manual trigger with `create_release: true`

**Steps:**
1. **Download artifact** - Download distribution ZIP from build-and-test job
2. **Create GitHub Release** - Create release with tag, notes, and asset

**Output:**
- GitHub release published at https://github.com/anthonyscry/GA-WsusManager/releases
- Release notes auto-generated from template
- EXE asset attached to release

**Status:** Automatic - runs immediately after tag push or manual trigger.

### Build PowerShell GUI (Legacy)

**File:** `.github/workflows/build.yml`

**Purpose:** Build legacy PowerShell GUI (maintained but superseded by C# version).

**Triggers:**
- Push to `main`, `master`, or `develop` branches (paths: `Scripts/**`, `Modules/**`, `Tests/**`, `*.ps1`, `.github/workflows/build.yml`)
- Pull request to `main`, `master`, or `develop` branches
- Manual trigger with version, create_release, and skip_tests options

**Jobs:**

#### code-review
PowerShell code review using PSScriptAnalyzer.

**Steps:**
1. **Checkout** - Clone repository
2. **Install PSScriptAnalyzer** - Install PSScriptAnalyzer module
3. **Run PSScriptAnalyzer** - Analyze all PowerShell files for errors and warnings
4. **Security Scan** - Run security-focused rules (password handling, invoke-expression, etc.)

**Outputs:**
- `WARNINGS` - Number of warnings found
- `ERRORS` - Number of errors found (fails job if > 0)
- `SECURITY_ISSUES` - Number of security issues found

#### test
Run Pester unit tests.

**Steps:**
1. **Checkout** - Clone repository
2. **Install Pester** - Install Pester module (v5.0+)
3. **Run Pester Tests** - Run all tests except ExeValidation.Tests.ps1
4. **Upload test results** - Save NUnit XML test results

**Artifacts:**
- `test-results` - Pester test results (NUnit XML format)

#### build
Build PowerShell GUI to EXE using PS2EXE.

**Dependencies:** code-review, test (must succeed or be skipped)

**Steps:**
1. **Checkout** - Clone repository
2. **Get version** - Extract version from build.ps1 or use DEFAULT_VERSION
3. **Install PS2EXE** - Install PS2EXE module
4. **Build executable** - Compile WsusManagementGui.ps1 to EXE
5. **Run EXE Validation Tests** - Run ExeValidation.Tests.ps1 against built EXE
6. **Create distribution package** - Package EXE, Scripts/, Modules/, and optional files into ZIP
7. **Prepare artifact for direct download** - Extract ZIP to prevent "zip within zip" issue
8. **Upload build artifact** - Save extracted distribution package
9. **Upload release artifact** - Save ZIP for GitHub releases

**Artifacts:**
- `WsusManager-v{version}` - Extracted distribution (for direct download)
- `WsusManager-v{version}-release` - ZIP archive (for GitHub releases)

#### release
Create GitHub release (manual trigger only).

**Trigger:** `create_release: true` input on manual workflow_dispatch

**Steps:**
1. **Download release artifact** - Download ZIP from build job
2. **Create Release** - Create GitHub release with hardcoded release notes

**Output:**
- GitHub release with hardcoded release notes (v3.8.6 content)

**Status:** Manual only - does not run on tag pushes (unlike C# workflow).

### Repository Hygiene

**File:** `.github/workflows/repo-hygiene.yml`

**Purpose:** Clean up stale pull requests, branches, and workflow runs.

**Triggers:**
- Scheduled: Daily at 2AM UTC (`cron: "0 2 * * *"`)
- Manual: `workflow_dispatch`

**Jobs:**

#### cleanup
Single job that performs all cleanup operations.

**Configuration:**
- `PR_INACTIVITY_HOURS: 24` - Close PRs with no activity for 24+ hours
- `BRANCH_AGE_DAYS: 7` - Delete branches with last commit 7+ days ago
- `WORKFLOW_MAX_RUNTIME_MINUTES: 45` - Delete workflow runs that exceeded 45 minutes
- `SAFE_MODE: true` - Log only mode (no destructive actions)

**Protected items:**
- PR labels: `keep`, `do-not-close`, `wip`
- Branch names: `main`, `master`, `develop`
- Branch prefixes: `release/`, `hotfix/`, `keep/`
- Branches with open PRs
- Release event workflow runs

**Steps:**
1. **Pull Request Cleanup** - Close stale PRs authored by trigger actor with comment
2. **Branch Cleanup** - Delete old branches not in protected list
3. **Workflow Runtime Cleanup** - Delete workflow runs that exceeded runtime threshold

**Status:** Currently in SAFE_MODE - logs actions only, no deletions performed.

### Dependabot Auto-Merge

**File:** `.github/workflows/dependabot-auto-merge.yml`

**Purpose:** Automatically approve and merge Dependabot dependency updates.

**Triggers:**
- Pull request opened, synchronized, or reopened by `dependabot[bot]`

**Jobs:**

#### auto-merge
Single job that auto-approves and auto-merges Dependabot PRs.

**Conditions:**
- PR author is `dependabot[bot]`
- Update type is `version-update:semver-minor` or `version-update:semver-patch`
- Major version updates require manual review

**Steps:**
1. **Dependabot metadata** - Fetch PR metadata using dependabot/fetch-metadata action
2. **Auto-approve** - Approve PR using gh CLI
3. **Auto-merge** - Enable auto-merge with squash using gh CLI

**Status:** Automatic - runs immediately when Dependabot opens a PR for minor/patch updates.

## CI/CD Pipeline Stages

### Stage 1: Build

**C# Build:**
```bash
dotnet build src/WsusManager.App/WsusManager.App.csproj --configuration Release --no-restore
```

**PowerShell Build:**
```powershell
Invoke-PS2EXE -InputFile ".\Scripts\WsusManagementGui.ps1" -OutputFile ".\WsusManager.exe" -NoConsole -RequireAdmin -x64
```

**Purpose:** Compile source code into assemblies.

**Success criteria:** Zero compiler warnings (enforced by TreatWarningsAsErrors).

**Common failures:**
- CA2007 (ConfigureAwait) - Missing ConfigureAwait(false) in library code
- CS0169 (Unused field) - Private field never used
- CS0067 (Unused event) - Event never raised

### Stage 2: Test

**C# Tests:**
```bash
dotnet test src/WsusManager.Tests/WsusManager.Tests.csproj \
  --configuration Release \
  --no-build \
  --logger "trx;LogFileName=test-results.trx" \
  --collect:"XPlat Code Coverage"
```

**PowerShell Tests:**
```powershell
$config = New-PesterConfiguration
$config.Run.Path = "./Tests/*.Tests.ps1"
$config.TestResult.Enabled = $true
$config.TestResult.OutputFormat = 'NUnitXml'
Invoke-Pester -Configuration $config
```

**Purpose:** Run unit tests and collect code coverage.

**Success criteria:** All tests pass, no test failures.

**Common failures:**
- SQL not available - Database tests require SQL Express
- WinRM not enabled - Client management tests require WinRM
- Assert failures - Code changes broke existing tests

### Stage 3: Publish

**C# Publish:**
```bash
dotnet publish src/WsusManager.App/WsusManager.App.csproj \
  --configuration Release \
  --runtime win-x64 \
  --self-contained true \
  -p:PublishSingleFile=true \
  -p:IncludeAllContentForSelfExtract=true
```

**PowerShell Publish:**
```powershell
# Compiled via PS2EXE during build stage
```

**Purpose:** Create single-file EXE distribution.

**Output:**
- C#: `WsusManager.exe` (~15-20 MB) with embedded .NET runtime
- PowerShell: `WsusManager.exe` (~280 KB) requires Scripts/ and Modules/ folders

**Common failures:**
- Missing runtime - .NET 8 SDK not installed
- Platform mismatch - Trying to publish for wrong platform
- Dependency issues - NuGet package restore failed

### Stage 4: Release

**C# Release:**
- Triggered by git tag push (`v*.*.*`)
- Downloads artifact from build job
- Creates GitHub release with auto-generated notes
- Attaches EXE ZIP as release asset

**PowerShell Release:**
- Manual trigger only (`create_release: true`)
- Downloads artifact from build job
- Creates GitHub release with hardcoded notes (v3.8.6)
- Attaches EXE ZIP as release asset

## Artifacts

### Test Results (`test-results`)

**C# Format:** xUnit TRX (Visual Studio Test Results)

**PowerShell Format:** NUnit XML

**Contents:** All test results with pass/fail status and error messages.

**Use:** View test results in GitHub Actions UI or download for detailed analysis.

**Download:** Actions → Workflow run → Artifacts → `test-results` or `WsusManager-v{version}`

### Coverage Report (`code-coverage-report`)

**Format:** HTML report generated by ReportGenerator

**Contents:** Line coverage, branch coverage, coverage by assembly/class/method.

**Use:** Identify untested code, track coverage trends.

**Download:** Actions → Workflow run → Artifacts → `code-coverage-report`

**View:** Open `index.html` in browser after extracting.

### WsusManager EXE (`WsusManager-v{version}-CSharp`)

**Format:** ZIP archive containing `WsusManager.exe`

**Contents:** Single-file EXE with embedded .NET runtime, ready to run.

**Use:** Distribute to users, deploy to servers.

**Download:** Actions → Workflow run → Artifacts → `WsusManager-v{version}-CSharp`

**PowerShell artifact:** `WsusManager-v{version}` (extracted) or `WsusManager-v{version}-release` (ZIP)

### Benchmark Results (`benchmark-results`)

**Format:** HTML reports and CSV data from BenchmarkDotNet

**Contents:** Performance metrics for startup, database operations, and WinRM calls.

**Use:** Track performance over time, detect regressions.

**Download:** Actions → Workflow run → Artifacts → `benchmark-results`

## Running Workflows Locally

Before pushing, run the same commands CI executes:

### C# Project

```bash
# From repository root
cd src

# Build (Release configuration)
dotnet restore
dotnet build --configuration Release

# Run tests
dotnet test --no-build --configuration Release

# Run tests with coverage
dotnet test --no-build --configuration Release --collect:"XPlat Code Coverage"

# Publish single-file EXE
dotnet publish src/WsusManager.App/WsusManager.App.csproj \
  --configuration Release \
  --runtime win-x64 \
  --self-contained true \
  --output publish \
  -p:PublishSingleFile=true

# Run benchmarks (optional)
dotnet run --project src/WsusManager.Benchmarks/WsusManager.Benchmarks.csproj --configuration Release
```

### PowerShell Project

```powershell
# Run Pester tests
Invoke-Pester -Path .\Tests -Output Detailed

# Run code analysis
Invoke-ScriptAnalyzer -Path .\Scripts\WsusManagementGui.ps1 -Severity Error,Warning

# Build executable
.\build.ps1

# Build without tests
.\build.ps1 -SkipTests
```

## Troubleshooting

### "Build failed with warnings"

**Cause:** Compiler warnings treated as errors (TreatWarningsAsErrors).

**Solution:**
1. Check build log for specific warning
2. Fix warning in code (or add justification to suppress)
3. Rebuild to verify fix

**Common warnings:**
- `CA2007` - Add `.ConfigureAwait(false)` to async call
- `CS0169` - Remove unused field or mark with `#pragma warning disable`
- `CS0067` - Remove unused event

### "Tests failed"

**Cause:** One or more unit tests failed.

**Solution:**
1. Download `test-results` artifact
2. Open in Visual Studio (TRX) or text editor (NUnit XML)
3. Find failed test and error message
4. Fix code or test (test may be wrong)

**Common test failures:**
- SQL connection failed - Ensure SQL Express running
- Assert.AreEqual failed - Code behavior changed
- Null reference exception - Missing null check

### "Coverage not generated"

**Cause:** Coverlet not collecting coverage or ReportGenerator not running.

**Solution:**
1. Verify `--collect:"XPlat Code Coverage"` in test command
2. Verify `coverage.cobertura.xml` exists after test run
3. Run ReportGenerator manually to generate HTML:
   ```bash
   dotnet tool install -g dotnet-reportgenerator-globaltool
   reportgenerator -reports:**/coverage.cobertura.xml -targetdir:./CoverageReport -reporttypes:HtmlInline
   ```

### "EXE not created"

**Cause:** Publish step failed or wrong output path.

**Solution:**
1. Check publish command for syntax errors
2. Verify `win-x64` runtime is valid
3. Check output path (should be `publish/` directory for C#, root for PowerShell)

### "Release not created"

**Cause:** Tag format wrong or release workflow failed.

**Solution:**
1. Verify tag format: `v*.*.*` (e.g., `v4.4.0`)
2. Check release workflow logs for errors
3. Manually create release if workflow fails (upload EXE from artifacts)

### "Workflow timeout"

**Cause:** Workflow exceeded maximum runtime (usually for PowerShell build).

**Solution:**
1. Check if PS2EXE compilation is hanging
2. Verify build.ps1 completes locally
3. Check for infinite loops or long-running operations

### "Artifact not found"

**Cause:** Artifact upload failed or job didn't complete.

**Solution:**
1. Check if upstream jobs completed successfully
2. Verify artifact name matches download step
3. Check retention period (artifacts expire after 30 days)

## Best Practices

### Before Pushing

1. **Build locally:** `dotnet build --configuration Release`
2. **Run tests:** `dotnet test --configuration Release`
3. **Check warnings:** Fix all compiler warnings
4. **Format code:** `dotnet format` (optional, auto-formats)

### After Merge

1. **Check artifacts:** Download and verify EXE works
2. **Review coverage:** Check coverage report for gaps
3. **Tag release:** Create git tag when ready to release

### Release Process

**C# Release:**
1. Update version in `src/Directory.Build.props`
2. Update `CHANGELOG.md` with release notes
3. Commit and push to main
4. Create tag: `git tag v4.4.0 && git push origin v4.4.0`
5. Release workflow creates GitHub release automatically

**PowerShell Release:**
1. Update version in `build.ps1`
2. Manually trigger workflow with `create_release: true`
3. Release workflow creates GitHub release

### Fork Contributing

For contributors from forks:
1. Fork the repository
2. Create a feature branch
3. Make changes and push to fork
4. Create pull request from fork
5. CI runs automatically on PR
6. Wait for maintainer approval

## Permissions

**Required for CI/CD:**
- `actions:read` - View workflow runs (all users)
- `actions:write` - Cancel/workflows (administrators only)
- `contents:read` - Checkout repository (all users)
- `contents:write` - Create releases (administrators only)
- `pull-requests:write` - Manage PRs (Dependabot auto-merge)

**Secrets:**
- `GITHUB_TOKEN` - Automatically provided by GitHub Actions
- No external service secrets currently required

## Concurrency Control

Most workflows use concurrency groups to prevent redundant runs:

```yaml
concurrency:
  group: build-csharp-${{ github.ref }}
  cancel-in-progress: true
```

**Behavior:** When new commit arrives, cancel in-progress run for same branch.

**Exceptions:**
- Release workflows (never canceled)
- Repository hygiene (scheduled, no concurrency)

## Workflow Matrix

Some workflows support matrix builds (not currently used, but planned):

```yaml
strategy:
  matrix:
    os: [windows-latest, ubuntu-latest]
    dotnet: ['8.0.x', '9.0.x']
```

**Current status:** Single configuration (windows-latest, .NET 8.0).

## Future Enhancements

- [ ] Automated deployment to internal server
- [ ] Slack/email notifications on release
- [ ] Scheduled nightly builds
- [ ] Performance regression detection (baseline comparison)
- [ ] Dependency scanning (Dependabot alerts)
- [ ] Code coverage badges in README
- [ ] Multi-platform builds (Linux Docker support)
- [ ] Automated changelog generation from commits

## Related Documentation

- **[CONTRIBUTING.md](../CONTRIBUTING.md)** - Contribution guidelines and local development
- **[README.md](../README.md)** - Build instructions and project overview
- **[docs/CODE-REVIEW-2026-01-13.md](CODE-REVIEW-2026-01-13.md)** - Code review guidelines
- **[.github/workflows/](../.github/workflows/)** - Actual workflow YAML files

---

*Last updated: 2026-02-21*
*For questions, open a GitHub Discussion or Issue.*
