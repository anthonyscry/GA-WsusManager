# Release Process

This document describes the release process for the PowerShell WSUS Manager (v3.x).

## Version Source of Truth

Keep version aligned in both files:
- `build.ps1` (`$Version = "x.y.z"`)
- `Scripts/WsusManagementGui.ps1` (`$script:AppVersion = "x.y.z"`)

Current release line: **3.8.x**

## Pre-Release Checklist

- [ ] Update version in `build.ps1`
- [ ] Update version in `Scripts/WsusManagementGui.ps1`
- [ ] Update `CHANGELOG.md`
- [ ] Run tests: `Invoke-Pester -Path .\Tests -Output Detailed`
- [ ] Run full build: `.\build.ps1`
- [ ] Validate output package from `dist/`

## Build Output

`build.ps1` creates:
- `dist/WsusManager.exe`
- `dist/WsusManager-vX.X.X.zip`

Distribution zip must include:
- `WsusManager.exe`
- `Scripts/`
- `Modules/`
- optional `DomainController/`

## GitHub Release Steps

1. Ensure CI build passes on target commit
2. Create/update tag for version
3. Publish release and attach distribution zip artifact
4. Verify release notes match `CHANGELOG.md`

## Post-Release Validation

- [ ] Download release asset
- [ ] Extract to clean folder
- [ ] Confirm `WsusManager.exe`, `Scripts/`, and `Modules/` are present
- [ ] Launch as Administrator on test host
- [ ] Run Diagnostics and one WSUS operation
