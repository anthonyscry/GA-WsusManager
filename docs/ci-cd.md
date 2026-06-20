# Validation and Release Automation

This repository currently uses local validation scripts instead of committed GitHub Actions workflows.

| Gate | Runner | Purpose |
|------|--------|---------|
| `build/Invoke-LocalValidation.ps1` | dev workstation | syntax, PSScriptAnalyzer, embedded XAML, Pester |
| `build/Invoke-ShipReadiness.ps1` | dev workstation | aggregate release-readiness checks |
| `build.ps1 -SkipTests -SkipCodeReview -NoPush` | dev workstation | package `GA-WsusManager.exe` and `GA-WsusManager-v*.zip` |

GitHub workflow scaffolding was intentionally removed during v4.1.0 cleanup. Treat the local scripts under `build/` as the source of truth for validation.

## Local validation

```powershell
.\build\Invoke-LocalValidation.ps1
.\build\Invoke-LocalValidation.ps1 -SkipTests
```

Run targeted tests for changed areas:

```powershell
Invoke-Pester -Path .\Tests\Integration.Tests.ps1 -Output Detailed
Invoke-Pester -Path .\Tests\WsusHealth.Tests.ps1 -Output Detailed
```

Run analyzer checks directly:

```powershell
Invoke-ScriptAnalyzer -Path .\Scripts\WsusManagementGui.ps1 -Severity Error,Warning
Invoke-ScriptAnalyzer -Path .\Scripts\Invoke-WsusManagement.ps1 -Severity Error,Warning
```

## GUI automation

GUI automation still requires a Windows desktop session with Administrator rights and FlaUI dependencies. Use:

```powershell
.\Tests\Run-GuiTests.ps1 -ResultsPath ".\Tests\flaui-test-results.txt" -TimeoutSeconds 300
```

GitHub-hosted runners run in a non-interactive Session 0 and cannot reliably drive WPF windows through UI Automation.

## Build package

```powershell
.\build.ps1 -SkipTests -SkipCodeReview -NoPush
```

Expected outputs:

```text
dist\GA-WsusManager.exe
dist\GA-WsusManager-v4.1.0.zip
```

GitHub releases attach only the zip. The standalone EXE remains inside the zip.

## When to run deeper tests

Use the deeper gates before a release or after changes touching GUI startup, packaging, diagnostics, database, or GPO behavior:

```powershell
# Aggregate release-readiness gate
.\build\Invoke-ShipReadiness.ps1

# Local validation, including embedded XAML loading
.\build\Invoke-LocalValidation.ps1

# Full build pipeline; git publishing is opt-in via -Push
.\build.ps1
```

`build/Invoke-LocalValidation.ps1` also validates the embedded XAML in `Scripts/WsusManagementGui.ps1` by loading it as a WPF Window. Run it on a Windows desktop/dev workstation.

## Build Artifacts

Primary build artifacts are:
- `dist\GA-WsusManager.exe`
- `dist\GA-WsusManager-vX.X.X.zip`

GitHub releases should attach only `dist\GA-WsusManager-vX.X.X.zip`; the standalone EXE is included inside the zip and should not be uploaded as a separate release asset.

The distribution zip is expected to include companion folders required by the EXE runtime:
- `GA-WsusManager.exe`
- `Scripts/`
- `Modules/`
- optional `DomainController/`
- `icons/`
- `README.md` copied by `build.ps1`
- generated `QUICK-START.txt`

Release artifacts are generated locally by `build.ps1` and attached manually to GitHub Releases.

## Release Process

Recommended path:

1. Run targeted tests for changed areas.
2. Run `.\build\Invoke-LocalValidation.ps1`.
3. Run `.\build.ps1 -SkipTests -SkipCodeReview -NoPush` after tests pass.
4. Confirm `dist\GA-WsusManager-vX.X.X.zip` contains EXE, Scripts, Modules, DomainController, icons, metadata, README, and QUICK-START.txt.
5. Attach only the zip to the GitHub release.
6. Bump version: edit `metadata.json` (single source of truth via `Get-WsusAppVersion`).
7. Add a section to `CHANGELOG.md`.
8. Delete the release branch when no longer needed.

## Troubleshooting

- **Local lint failure:** check that PowerShell files are saved with UTF-8 BOM when they contain non-ASCII chars. Run `.\build\Invoke-SyntaxCheck.ps1` to confirm syntax.
- **GUI automation cannot see controls:** FlaUI requires an interactive Windows desktop session. GitHub-hosted runners are not enough.
- **PS2EXE missing:** install the `ps2exe` module before running the packaging path.
- **EXE works in repo but not after deployment:** confirm `Scripts/` and `Modules/` are alongside `GA-WsusManager.exe`.
- **Version mismatch between GUI and CLI:** both call `Get-WsusAppVersion` which reads `metadata.json`. Update `metadata.json` and rebuild.
- **Emoji/special chars render as `?` in GUI:** v4.1.0+ has UTF-8 BOM applied to `Scripts/WsusManagementGui.ps1` and all menu symbols replaced with Segoe-UI-safe BMP alternatives.
