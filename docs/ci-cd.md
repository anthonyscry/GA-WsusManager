# Validation and Release Automation

This repository uses a **two-tier CI model** plus a local validation harness:

| Pipeline | Trigger | Runner | Purpose |
|----------|---------|--------|---------|
| `.github/workflows/ci.yml` | every push, every PR | `windows-latest` (GitHub-hosted) | syntax, lint, unit tests, Office C2R tests, EXE build |
| `.github/workflows/gui-tests.yml` | manual dispatch + daily schedule | `self-hosted, windows, triton-ajt` | Pester subset plus FlaUI GUI automation through interactive session |
| `build/Invoke-ShipReadiness.ps1` | local | dev workstation | aggregate verification gate |

The GitHub workflow files are the source of truth for CI. The local scripts under `build/` provide overlapping gates for developer workstations and release readiness.

## Tier 1: `ci.yml` (Standard CI)

Runs on every push and PR to `main` or `release/*`. Uses GitHub-hosted `windows-latest`. **No self-hosted runner required.** Designed to be fast and produce actionable feedback within ~10 minutes.

### Jobs

1. **Syntax Check** — runs `build/Invoke-SyntaxCheck.ps1` against the entire repo. Fails if any `.ps1`, `.psm1`, or `.psd1` has a parse error.
2. **PSScriptAnalyzer** — installs PSScriptAnalyzer, runs the analyzer across all PS files at Error severity using `.PSScriptAnalyzerSettings.psd1`. Fails on any Error.
3. **Pester Unit Tests** — installs Pester 5, runs `./Tests` excluding tags `E2E`, `GUI`, `Integration`, `FlaUI` (those need a real WSUS / SQL / IIS stack or interactive desktop). Writes NUnit3 XML to `TestResults/unit-tests.xml`. Fails on any failed test.
4. **Office C2R Module Tests** — runs `build/Invoke-OfficeC2R-Tests.ps1` for fast feedback on the new feature.
5. **Build EXE** — depends on all of the above. Runs `build.ps1 -SkipTests -NoPush` to produce `dist/GA-WsusManager.exe` and `dist/WsusManager-v*.zip`. Uploads the artifacts for download.

### Concurrency

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

Cancels in-progress runs on the same branch when a new push lands. This means PR re-pushes don't pile up runs.

### Triggering Locally

You can reproduce the standard CI gate locally with the same commands:

```powershell
# Syntax
./build/Invoke-SyntaxCheck.ps1

# Unit tests (same tag exclusions as ci.yml)
Invoke-Pester -Path ./Tests -Output Detailed -ExcludeTag 'E2E','GUI','Integration','FlaUI'

# Office C2R focused tests
./build/Invoke-OfficeC2R-Tests.ps1

# Build artifact generation
./build.ps1 -SkipTests -NoPush
```

## Tier 2: `gui-tests.yml` (Self-Hosted GUI Tests)

Runs a Pester subset plus FlaUI GUI automation. Requires the `triton-ajt` self-hosted runner, which is a Windows desktop with an interactive session — the only environment where FlaUI can drive WPF windows.

### Triggers

- **Manual dispatch** with two checkboxes: include unit tests, include GUI tests
- **Daily schedule**: 14:00 UTC on weekdays (6 AM Pacific)

### Why it can't run on `windows-latest`

GitHub-hosted runners run in a non-interactive Session 0 with no desktop. WPF window creation works but UI Automation (UIA) cannot reach controls because there is no logon session, no cursor, no active window. FlaUI needs UIA to find buttons by AutomationId.

### Adding a new self-hosted runner

The runner must:

1. Be Windows 10/11 or Server 2019+ with admin rights
2. Have a logged-on interactive session (Session 1+)
3. Have Pester 5+, PSScriptAnalyzer, and FlaUI assemblies installed
4. Be registered with the label `self-hosted, windows, triton-ajt`

GitHub docs: <https://docs.github.com/en/actions/hosting-your-own-runners/adding-self-hosted-runners>

### When to extend this

Add a new self-hosted runner label (e.g. `windows, sql-express`) if you need tests that require:

- A real SQL Server Express instance (most `WsusDatabase.Tests.ps1` paths)
- IIS with the WsusPool app pool (most `WsusFirewall.Tests.ps1` paths)
- A real WSUS install with the WsusContent folder (most `WsusHealth.Tests.ps1` paths)
- A real Active Directory / GPMC (most `WsusGroupPolicy.Tests.ps1` paths)
- An interactive desktop session (all of `FlaUI.Tests.ps1`)

## Tier 3: Local Validation

The local scripts overlap with CI but are not a byte-for-byte workflow mirror. Use them as developer and release-readiness gates:
```powershell
# Aggregate release-readiness gate
.\build\Invoke-ShipReadiness.ps1


# What local validation covers (additional XAML validation)
.\build\Invoke-LocalValidation.ps1

# Full build pipeline (git publish is opt-in via -Push)
.\build.ps1
```

`build/Invoke-LocalValidation.ps1` does one extra check that CI skips: it validates the embedded XAML in `Scripts/WsusManagementGui.ps1` is well-formed (it tries to load it as a WPF Window). On a headless CI runner this would fail, so it stays local.

## Build Artifacts

Primary build artifacts are:
- `dist\GA-WsusManager.exe`
- `dist\WsusManager-vX.X.X.zip`

The distribution zip is expected to include companion folders required by the EXE runtime:
- `GA-WsusManager.exe`
- `Scripts/`
- `Modules/`
- optional `DomainController/`
- `README.md` copied by `build.ps1`
- generated `QUICK-START.txt`

CI uploads the artifacts from the build job and retains them for 14 days.

## Release Process

Recommended path:

1. PR from feature branch → `main`. CI must be green. Self-hosted GUI test job runs daily and posts status.
2. Reviewer approves.
3. Merge to `main`.
4. Cut a release branch: `release/v4.x.x`.
5. Trigger the self-hosted workflow manually with `run_gui_tests=true` to confirm GUI on a real Windows desktop.
6. Download the artifact from the build job, sign it (out of band), attach to a GitHub release.
7. Bump version: edit `metadata.json` (single source of truth via `Get-WsusAppVersion`).
8. Add a section to `CHANGELOG.md`.
9. Delete the release branch.

## Troubleshooting

- **CI lint failure but local passes:** check that the file was saved with UTF-8 BOM (PowerShell 5.1 needs the BOM for files with non-ASCII chars). Run `./build/Invoke-SyntaxCheck.ps1` to confirm syntax.
- **Self-hosted runner not picking up jobs:** the runner must be online, have the correct labels, and have an active interactive session. Check the runner's `_diag` log under `%RUNNER_HOME%\_diag`.
- **PS2EXE missing in CI:** the `build.ps1 -SkipTests` path requires `ps2exe` installed. The CI build job installs Pester and PSScriptAnalyzer; add ps2exe to the install step if you need EXE build in CI.
- **EXE works in repo but not after deployment:** confirm `Scripts/` and `Modules/` are alongside `GA-WsusManager.exe`.
- **Version mismatch between GUI and CLI:** both call `Get-WsusAppVersion` which reads `metadata.json`. Update `metadata.json` and rebuild.
- **Emoji/special chars render as `?` in GUI:** v4.1.0+ has UTF-8 BOM applied to `Scripts/WsusManagementGui.ps1` and all menu symbols replaced with Segoe-UI-safe BMP alternatives.
