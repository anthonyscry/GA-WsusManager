# Contributing to WSUS Manager

Thanks for contributing to WSUS Manager. This repository is a PowerShell WPF project and uses Pester + PSScriptAnalyzer for quality gates.

## Prerequisites

- Windows 10/11 or Windows Server 2019/2022
- PowerShell 5.1+
- Administrator privileges for operation testing
- Modules:
  - Pester (v5+)
  - PSScriptAnalyzer
  - PS2EXE (for full build)

## Project Layout

- `Scripts/` - GUI and CLI operation scripts
- `Modules/` - reusable WSUS modules
- `Tests/` - Pester test suites
- `DomainController/` - GPO deployment assets
- `Assets/Branding/` - source icon and logo assets used during build/package
- `build.ps1` - build/test/review entry point

## Build

```powershell
# Local validation helper (recommended before a PR)
.\build\Invoke-LocalValidation.ps1

# Full build (recommended)
.\build.ps1 -NoPush

# Build without tests
.\build.ps1 -SkipTests -NoPush

# Build without code review
.\build.ps1 -SkipCodeReview -NoPush

# Tests only
.\build.ps1 -TestOnly
```

## Test and Analysis

```powershell
# Run all tests
Invoke-Pester -Path .\Tests -Output Detailed

# Run one test file
Invoke-Pester -Path .\Tests\WsusAutoDetection.Tests.ps1

# Analyze scripts
Invoke-ScriptAnalyzer -Path .\Scripts\WsusManagementGui.ps1 -Severity Error,Warning
Invoke-ScriptAnalyzer -Path .\Scripts\Invoke-WsusManagement.ps1 -Severity Error,Warning
```

## Code Style Guidelines

- Use approved PowerShell verbs (`Get-`, `Set-`, `Invoke-`, `Test-`, etc.)
- Prefix WSUS-specific functions with `Wsus` where appropriate
- Add comment-based help for public functions
- Export public module functions explicitly with `Export-ModuleMember`
- Keep error handling explicit and user-facing in GUI paths

## GUI Change Checklist

Before opening a PR with GUI changes, verify:

1. Dialogs open before panel switching (no blank window transitions)
2. Return values that should not print are suppressed (`$null =` / `Out-Null`)
3. Background UI updates are dispatched to UI thread
4. Event handlers pass required data explicitly
5. New CLI parameters are added in both GUI caller and CLI script
6. Concurrent operation blocking works
7. Cancel path stops running operations
8. ESC closes dialogs
9. Script paths are validated before invocation
10. Buttons are disabled/re-enabled correctly during operations
11. Build passes (`.\build.ps1 -NoPush`)
12. Manual validation performed for changed operations

## Commit Messages

Use conventional commits:

```
type(scope): description
```

Examples:

- `feat(gui): add reset content quick action`
- `fix(health): handle missing sql instance gracefully`
- `test(modules): add coverage for wsus autodetection fallback`
- `docs(readme): clarify distribution folder requirements`

## Pull Request Process

1. Create a branch from `main`
2. Make focused changes
3. Run build/tests locally
4. Update docs when behavior changes
5. Open PR with clear summary and verification notes

### PR Checklist

- [ ] `build.ps1` completed successfully (or failures are explained)
- [ ] Pester tests pass for affected areas
- [ ] PSScriptAnalyzer errors resolved
- [ ] Docs updated for user-visible changes
- [ ] No build artifacts committed (`dist/`, exe/zip outputs)

## Notes

- Distribution artifacts are generated in `dist/` and should not be committed.
- `GA-WsusManager.exe` distribution requires `Scripts/` and `Modules/` alongside the EXE.
