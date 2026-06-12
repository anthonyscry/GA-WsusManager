# Release Process

This document describes the release process for the PowerShell WSUS Manager (v4.x).

## Version Source of Truth

`metadata.json` (`"version"`) is the release version source of truth. `build.ps1`, the GUI, CLI, and maintenance scripts read it through `Get-WsusAppVersion`; fallback literals in scripts should only change when intentionally changing missing-metadata behavior.

Current release line: **4.1.x**

## Pre-Release Checklist

- [ ] Update `metadata.json`
- [ ] Update `CHANGELOG.md`
- [ ] Run local validation: `.\build\Invoke-LocalValidation.ps1`
- [ ] Run tests: `Invoke-Pester -Path .\Tests -Output Detailed`
- [ ] Run full build: `.\build.ps1`
- [ ] Publish dist artifacts only after validation: `.\build.ps1 -SkipTests -SkipCodeReview -Push`
- [ ] Validate output package from `dist/`

## Build Output

`build.ps1` creates:
- `dist/GA-WsusManager.exe`
- `dist/WsusManager-vX.X.X.zip`

Distribution zip must include:
- `GA-WsusManager.exe`
- `Scripts/`
- `Modules/`
- optional `DomainController/`

## GitHub Release Steps

1. Ensure local validation and build pass on the target commit
2. Create/update tag for version
3. Publish release and attach distribution zip artifact
4. Verify release notes match `CHANGELOG.md`

## Post-Release Validation

- [ ] Download release asset
- [ ] Extract to clean folder
- [ ] Confirm `GA-WsusManager.exe`, `Scripts/`, and `Modules/` are present
- [ ] Launch as Administrator on test host
- [ ] Run Diagnostics and one WSUS operation
