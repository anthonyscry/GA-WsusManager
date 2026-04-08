# Validation and Release Automation

This repository currently relies on local validation scripts as the source of truth for build and quality checks. If GitHub Actions workflow files are added back later, they should mirror the commands below.

## Local Validation Commands

```powershell
# Full local validation (recommended)
.\build\Invoke-LocalValidation.ps1

# Analyzer
Invoke-ScriptAnalyzer -Path .\Scripts\WsusManagementGui.ps1 -Severity Error,Warning
Invoke-ScriptAnalyzer -Path .\Scripts\Invoke-WsusManagement.ps1 -Severity Error,Warning

# Tests
Invoke-Pester -Path .\Tests -Output Detailed

# Full build pipeline
.\build.ps1 -NoPush
```

## What the Local Validation Flow Covers

1. `build\Invoke-LocalValidation.ps1`
   - Runs PSScriptAnalyzer across repo PowerShell files
   - Validates embedded XAML in `Scripts/WsusManagementGui.ps1`
   - Runs Pester test suites unless `-SkipTests` is used

2. `build.ps1`
   - Runs PSScriptAnalyzer on the main entry scripts
   - Runs the Pester suite unless `-SkipTests` is used
   - Compiles `Scripts/WsusManagementGui.ps1` into `GA-WsusManager.exe`
   - Creates the `WsusManager-vX.X.X.zip` distribution package
   - Copies build outputs into `dist\`
   - Auto-commits and pushes `dist\` unless `-NoPush` is supplied

## Build Artifacts

Primary build artifacts are:
- `dist\GA-WsusManager.exe`
- `dist\WsusManager-vX.X.X.zip`

The distribution zip is expected to include companion folders required by the EXE runtime:
- `GA-WsusManager.exe`
- `Scripts/`
- `Modules/`
- optional `DomainController/`
- release documentation files copied by `build.ps1`

## Troubleshooting

- **Analyzer failures:** fix reported script errors/warnings first
- **Pester failures:** run failing test file directly and reproduce locally
- **Build failures:** verify `PS2EXE` installed and script paths resolve
- **EXE works in repo but not after deployment:** confirm `Scripts/` and `Modules/` are alongside `GA-WsusManager.exe`
