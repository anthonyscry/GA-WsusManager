# CI/CD Pipeline Documentation

WSUS Manager uses GitHub Actions to validate and package the PowerShell GUI release.

## Active Workflows

### Build GA-WsusManager
- **File:** `.github/workflows/build.yml`
- **Purpose:** Code review, tests, EXE build, and packaging
- **Triggers:**
  - Push to `main`, `master`, `develop` on PowerShell paths
  - Manual trigger (`workflow_dispatch`)

#### Jobs

1. **PowerShell Code Review**
   - Installs `PSScriptAnalyzer`
   - Scans `.ps1`, `.psm1`, `.psd1` files
   - Fails on analyzer errors
   - Includes security-focused rules

2. **Pester Tests**
   - Installs `Pester` v5+
   - Runs test suites in `Tests/` (excluding EXE validation pre-build)
   - Uploads `test-results` artifact

3. **Build Executable**
   - Installs `PS2EXE`
   - Builds `Scripts/WsusManagementGui.ps1` into `WsusManager.exe`
   - Runs `Tests/ExeValidation.Tests.ps1`
   - Packages distribution zip with required folders:
     - `WsusManager.exe`
     - `Scripts/`
     - `Modules/`
     - optional `DomainController/`

4. **Create Release** (manual input)
   - Creates GitHub release from build artifact when requested

### Repository Hygiene
- **File:** `.github/workflows/repo-hygiene.yml`
- Scheduled maintenance for stale PRs/branches/runs

### Dependabot Auto-Merge
- **File:** `.github/workflows/dependabot-auto-merge.yml`
- Auto-merges minor/patch dependency updates

## Local Validation Commands

```powershell
# Analyzer
Invoke-ScriptAnalyzer -Path .\Scripts\WsusManagementGui.ps1 -Severity Error,Warning
Invoke-ScriptAnalyzer -Path .\Scripts\Invoke-WsusManagement.ps1 -Severity Error,Warning

# Tests
Invoke-Pester -Path .\Tests -Output Detailed

# Full build pipeline
.\build.ps1
```

## Artifacts

Primary build artifact is a distribution package:
- `WsusManager-vX.X.X.zip`

The package is expected to include companion folders required by the EXE runtime (`Scripts/`, `Modules/`).

## Troubleshooting

- **Analyzer failures:** fix reported script errors/warnings first
- **Pester failures:** run failing test file directly and reproduce locally
- **Build failures:** verify `PS2EXE` installed and script paths resolve
- **EXE works in repo but not after deployment:** confirm `Scripts/` and `Modules/` are alongside `WsusManager.exe`
