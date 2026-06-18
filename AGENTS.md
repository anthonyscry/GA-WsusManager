# Repository Guidelines

## Project Overview

GA-WsusManager is a Windows PowerShell 5.1 / WPF administration suite for WSUS servers, especially SQL Express-backed and air-gapped environments. It installs/configures WSUS, runs online maintenance, exports/imports update content, restores SUSDB backups, configures HTTPS and GPOs, and provides diagnostics/repair workflows through both GUI and CLI entry points.

## Architecture & Data Flow

- Main surfaces:
  - `Scripts/WsusManagementGui.ps1`: WPF GUI, compiled by PS2EXE into `GA-WsusManager.exe`.
  - `Scripts/Invoke-WsusManagement.ps1`: CLI/router for restore, import/export, health, repair, diagnostics, cleanup, and reset.
  - `Scripts/Invoke-WsusMonthlyMaintenance.ps1`: online sync, cleanup, SQL maintenance, backup, and export automation.
- Module spine:
  - `Modules/WsusUtilities.psm1` is foundational: logging, admin checks, SQL invocation, paths, credentials.
  - `Modules/WsusConfig.psm1` centralizes defaults/timeouts/health weights, though scripts still contain some deployment defaults.
  - Health/repair flows compose `WsusHealth`, `WsusServices`, `WsusFirewall`, `WsusPermissions`, and `WsusDatabase`.
  - GUI operation lifecycle is process-based; see `Modules/WsusOperationRunner.psm1` and GUI `Invoke-LogOperation` patterns.
- Operational flow:
  1. GUI/CLI validates admin/runtime paths and imports modules.
  2. Long operations launch child `powershell.exe -NoProfile -ExecutionPolicy Bypass ...` commands.
  3. SQL work uses `Invoke-Sqlcmd`/`SqlServer` when available, falling back to `sqlcmd.exe`.
  4. File transfer uses `robocopy`; exit codes `0..7` are success.
  5. WSUS repair/reset uses `C:\Program Files\Update Services\Tools\wsusutil.exe`.
- Persistent state/logs:
  - WSUS content: `C:\WSUS`; logs: `C:\WSUS\Logs`.
  - GUI settings/history/trends: `%APPDATA%\WsusManager\settings.json`, `history.json`, `trends.json`.
  - Default SQL instance/database: `.\SQLEXPRESS` / `SUSDB`; common ports: WSUS `8530/8531`, SQL `1433/1434`.

## Key Directories

- `Modules/`: reusable PowerShell modules; explicit exports only.
- `Scripts/`: GUI, installer, management CLI, monthly maintenance, HTTPS, and client check-in scripts.
- `Tests/`: Pester v5 unit/integration/GUI/startup suites.
- `DomainController/`: GPO deployment script and backed-up WSUS GPOs.
- `docs/`: SOP, CI/CD, quick start, GUI testing, release notes, UI review.
- `wiki/`: user/developer/install/troubleshooting/module/air-gap guides.
- `installers/`: documented offline location for SQL/SSMS installers; binaries are gitignored.
- `build/`: local validation tooling.
- `.github/workflows/gui-tests.yml`: self-hosted Windows GUI/unit test workflow.

## Development Commands

Run commands in Windows PowerShell 5.1 unless a file says otherwise.

```powershell
# Build/package; -NoPush avoids build.ps1 committing dist artifacts
.\build.ps1 -NoPush
.\build.ps1 -SkipTests -NoPush
.\build.ps1 -SkipCodeReview -NoPush
.\build.ps1 -TestOnly

# Local validation documented as CI source of truth
.\build\Invoke-LocalValidation.ps1
.\build\Invoke-LocalValidation.ps1 -SkipTests

# Tests
Invoke-Pester -Path .\Tests -Output Detailed
Invoke-Pester -Path .\Tests\WsusDatabase.Tests.ps1 -Output Detailed
.\Tests\Invoke-Tests.ps1 -TestName "WsusConfig"
.\Tests\Invoke-Tests.ps1 -CodeCoverage -OutputFile "TestResults.xml"

# Analyzer examples
Invoke-ScriptAnalyzer -Path .\Scripts\WsusManagementGui.ps1 -Severity Error,Warning
Invoke-ScriptAnalyzer -Path .\Scripts\Invoke-WsusManagement.ps1 -Severity Error,Warning

# GUI automation wrapper used by CI/self-hosted desktop sessions
.\Tests\Run-GuiTests.ps1 -ResultsPath ".\Tests\flaui-test-results.txt" -TimeoutSeconds 300
```

Operational examples:

```powershell
.\Scripts\Invoke-WsusManagement.ps1 -Health
.\Scripts\Invoke-WsusManagement.ps1 -Repair
.\Scripts\Invoke-WsusManagement.ps1 -Cleanup -Force
.\Scripts\Invoke-WsusManagement.ps1 -Export -SourcePath "C:\WSUS" -DestinationPath "E:\WsusExport"
.\Scripts\Invoke-WsusManagement.ps1 -Import -SourcePath "E:\WsusExport" -DestinationPath "C:\WSUS"
.\Scripts\Invoke-WsusMonthlyMaintenance.ps1 -MaintenanceProfile Full -Unattended
.\Scripts\Set-WsusHttps.ps1 -CertificateThumbprint "<thumbprint>"
.\DomainController\Set-WsusGroupPolicy.ps1 -WsusServerUrl "http://WSUS01:8530"
```

## Code Conventions & Common Patterns

- Use approved PowerShell verbs and `Wsus`-prefixed nouns for public functions, e.g. `Get-WsusHealthScore`.
- Public module functions should have comment help and be listed in explicit `Export-ModuleMember -Function ...` declarations.
- Prefer `[CmdletBinding()]`, typed parameters, `[ValidateSet()]`, `[ValidateRange()]`, `Test-Path`, and explicit path/user validation.
- Import local modules by path with `Import-Module ... -Force -DisableNameChecking`; tests usually remove imported modules in `AfterAll`.
- Error handling pattern:
  - Optional probes: `-ErrorAction SilentlyContinue` and safe default return values.
  - Required operations: `-ErrorAction Stop` inside `try/catch`, `Write-Warning`, and structured result hashtables.
  - GUI-facing code favors non-throwing status objects with `Success`, `Message`, `Errors`, etc.
- Long-running GUI operations should not block the UI thread. Existing patterns use child processes, redirected streams, object events, `DispatcherTimer`, and dispatcher marshaling.
- Do not pass secrets on command lines. Existing GUI paths pass sensitive values through environment variables such as `WSUS_INSTALL_SA_PASSWORD` and `WSUS_TASK_PASSWORD`.
- Treat hard-coded operational defaults carefully: `C:\WSUS`, `.\SQLEXPRESS`, `SUSDB`, `8530/8531`, and SQL Express 10GB limits are domain assumptions.
- PSScriptAnalyzer settings live in `.PSScriptAnalyzerSettings.psd1`; notable exclusions include `PSAvoidUsingWriteHost`, `PSUseShouldProcessForStateChangingFunctions`, and `PSUseSingularNouns`.

## Important Files

- `README.md`: project overview, requirements, standard paths, common commands.
- `build.ps1`: primary build/package script; can install Pester, PSScriptAnalyzer, and ps2exe; default build may commit/push unless `-NoPush` is used.
- `build/Invoke-LocalValidation.ps1`: analyzer, embedded XAML validation, and Pester validation.
- `.PSScriptAnalyzerSettings.psd1`: lint/security/style rules.
- `metadata.json`: package metadata; check version consistency with `build.ps1` and GUI version before releases.
- `Scripts/WsusManagementGui.ps1`: main GUI and compiled EXE source.
- `Scripts/Invoke-WsusManagement.ps1`: core CLI operation router.
- `Scripts/Install-WsusWithSqlExpress.ps1`: SQL Express + WSUS installer.
- `Scripts/Invoke-WsusMonthlyMaintenance.ps1`: scheduled/online maintenance automation.
- `Scripts/Set-WsusHttps.ps1`: HTTPS/IIS/certificate configuration.
- `DomainController/Set-WsusGroupPolicy.ps1`: GPO import/link/update flow.
- `docs/WSUS-Manager-SOP.md`: most complete operator workflow reference.
- `docs/ci-cd.md` and `docs/releases.md`: validation/release expectations.
- `Tests/Invoke-Tests.ps1` and `Tests/TestSetup.ps1`: test runner/shared setup.

## Runtime/Tooling Preferences

- Runtime: Windows PowerShell 5.1 (`powershell.exe`), not PowerShell 7 by default.
- Platform: Windows desktop/server; real WSUS operations require Administrator. GUI/WPF requires desktop assemblies and STA behavior.
- External dependencies: WSUS role, IIS/W3SVC, SQL Server Express 2022, `sqlcmd.exe`, `robocopy.exe`, `wsusutil.exe`; DC/GPO flows need GroupPolicy/GPMC and often ActiveDirectory modules.
- Build tooling: PowerShellGet modules `Pester` v5+, `PSScriptAnalyzer`, and `ps2exe`; no Node/Bun/npm package workflow is used.
- Packaging output: `dist/GA-WsusManager.exe` and `dist/WsusManager-vX.X.X.zip`; packages must keep `Scripts/` and `Modules/` beside the executable.
- Offline installers expected under `C:\WSUS\SQLDB\` or documented `installers/`: `SQLEXPRADV_x64_ENU.exe` preferred, `SSMS-Setup-ENU.exe` optional.
- Actual CI is self-hosted Windows (`.github/workflows/gui-tests.yml`); docs say local validation scripts are the source of truth.

## Testing & QA

- Test framework: Pester v5+. Test files are named `Tests/<Subject>.Tests.ps1` and usually import modules directly from `..\Modules`.
- Common mocking pattern: `Mock ... -ModuleName <Module>` plus `Should -Invoke` for service, SQL, scheduled task, firewall, file-system, and repair functions.
- Common isolation patterns:
  - `$TestDrive` for file-system tests.
  - Temporary directories from `$env:TEMP` or `[System.IO.Path]::GetTempPath()`.
  - Redirect and restore `$env:APPDATA` for settings/history/trend tests.
  - Restore mutated config in `AfterEach`.
- Coverage support exists via `Tests/Invoke-Tests.ps1 -CodeCoverage` and `Invoke-Pester -Path .\Tests -CodeCoverage .\Modules\*.psm1`; no threshold gate was found.
- GUI tests (`Tests/FlaUI.Tests.ps1`, `Tests/Run-GuiTests.ps1`) require Windows, admin, an interactive desktop/session, compiled EXE or GUI script, and the FlaUI harness. Use tags/exclusions for non-GUI unit runs.
- Startup/popup QA references `Invoke-Pester -Path .\Tests\StartupE2E.Tests.ps1 -Output Detailed` and manual smoke checks in `docs/POPUP-SMOKE-CHECKLIST.md`.
- Some tests intentionally interact with real Windows concepts (`Spooler`, `W32Time`, WPF object construction, EXE presence). Prefer targeted tests for changed modules and avoid broad GUI/e2e runs unless the change affects GUI startup or automation.
