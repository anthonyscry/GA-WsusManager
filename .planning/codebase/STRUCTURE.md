# Codebase Structure

**Analysis Date:** 2026-02-19

## Directory Layout

```
GA-WsusManager/
├── Scripts/                     # CLI scripts and GUI application
│   ├── WsusManagementGui.ps1    # Main GUI application (3000+ LOC, WPF/XAML)
│   ├── Invoke-WsusManagement.ps1     # CLI orchestration for health, cleanup, restore, reset
│   ├── Invoke-WsusMonthlyMaintenance.ps1  # Scheduled maintenance automation (Full/Quick/SyncOnly profiles)
│   ├── Install-WsusWithSqlExpress.ps1    # WSUS + SQL Express installation
│   ├── Invoke-WsusClientCheckIn.ps1      # Client synchronization
│   └── Set-WsusHttps.ps1               # HTTPS/SSL configuration
│
├── Modules/                     # Reusable PowerShell module library (11 modules, ~180KB)
│   ├── WsusUtilities.psm1       # Foundation: logging, colors, SQL wrapper, path validation
│   ├── WsusServices.psm1        # Service control: SQL, WSUS, IIS startup/stop/status
│   ├── WsusHealth.psm1          # Diagnostics: connectivity, service, firewall, permissions checks + auto-repair
│   ├── WsusDatabase.psm1        # Database: cleanup, index optimization, size monitoring
│   ├── WsusFirewall.psm1        # Firewall: WSUS port rules (8530, 8531)
│   ├── WsusPermissions.psm1     # Permissions: directory ACL and SQL login checks
│   ├── WsusExport.psm1          # Export/Import: media transfer for air-gapped networks
│   ├── WsusScheduledTask.psm1   # Scheduled tasks: create, delete, status
│   ├── WsusConfig.psm1          # Configuration: centralized constants and settings
│   ├── WsusAutoDetection.psm1   # Auto-detection: service status, DB monitoring, health aggregation
│   ├── AsyncHelpers.psm1        # Async/WPF: background operations, runspace pools, UI dispatch
│   └── README.md                # Module documentation
│
├── Tests/                       # Pester unit tests (323 tests across 10 files)
│   ├── WsusUtilities.Tests.ps1          # Utilities module tests
│   ├── WsusServices.Tests.ps1           # Service control tests
│   ├── WsusHealth.Tests.ps1             # Health check tests
│   ├── WsusDatabase.Tests.ps1           # Database operation tests
│   ├── WsusFirewall.Tests.ps1           # Firewall rule tests
│   ├── WsusPermissions.Tests.ps1        # Permission tests
│   ├── WsusExport.Tests.ps1             # Export/import tests
│   ├── WsusScheduledTask.Tests.ps1      # Scheduled task tests
│   ├── WsusAutoDetection.Tests.ps1      # Auto-detection tests
│   ├── WsusConfig.Tests.ps1             # Config tests
│   ├── CliIntegration.Tests.ps1         # CLI parameter and operation tests
│   ├── ExeValidation.Tests.ps1          # Compiled EXE validation (PE header, version, architecture)
│   ├── FlaUI.Tests.ps1                  # GUI automation tests (requires FlaUI library)
│   ├── Integration.Tests.ps1            # End-to-end integration tests
│   ├── TestSetup.ps1                    # Test environment setup helpers
│   └── Invoke-Tests.ps1                 # Test runner entry point
│
├── DomainController/            # GPO deployment and domain configuration
│   ├── Set-WsusGroupPolicy.ps1  # GPO creation and application script
│   └── WSUS GPOs/               # GPO backup files (GUID-based folders)
│
├── docs/                        # Documentation
├── build/                       # Build scripts
│   ├── Invoke-LocalValidation.ps1  # Pre-build validation
│   └── build.ps1                   # Main build script (PS2EXE compilation)
│
├── dist/                        # Build output (gitignored)
│   ├── WsusManager.exe          # Compiled GUI executable
│   └── WsusManager-vX.X.X.zip   # Distribution package with Scripts/Modules
│
├── .github/                     # GitHub configuration
│   ├── workflows/               # GitHub Actions CI/CD
│   │   └── build.yml            # Builds EXE, runs tests, publishes releases
│   └── ISSUE_TEMPLATE/          # Issue templates
│
├── .planning/
│   └── codebase/                # AI codebase analysis documents
│       ├── ARCHITECTURE.md      # Architecture and data flow
│       ├── STRUCTURE.md         # Directory layout and naming conventions
│       ├── CONVENTIONS.md       # Code style and patterns
│       ├── TESTING.md           # Testing patterns and test locations
│       ├── STACK.md             # Technology stack and runtime
│       ├── INTEGRATIONS.md      # External APIs and services
│       └── CONCERNS.md          # Technical debt and known issues
│
└── build.ps1                    # Build orchestration script
```

## Directory Purposes

**Scripts/:**
- Purpose: Entry points for all user-facing operations (GUI and CLI)
- Contains: PowerShell scripts (.ps1 files only, no modules)
- Key files: See "Key File Locations" section below
- Deployment: Included in distribution zip with Modules/ folder

**Modules/:**
- Purpose: Reusable library of domain-specific functions
- Contains: PowerShell modules (.psm1 files with explicit Export-ModuleMember)
- Key files: 11 modules providing services, health, database, firewall, permissions, export, tasks, config, auto-detection, async helpers, utilities
- Deployment: Required alongside Scripts/ in distribution
- Module Size Breakdown:
  - WsusHealth.psm1 - 34KB (largest, comprehensive diagnostics)
  - WsusAutoDetection.psm1 - 24KB (service status, health aggregation)
  - WsusUtilities.psm1 - 24KB (logging, SQL wrapper, path validation)
  - WsusDatabase.psm1 - 26KB (database maintenance, cleanup, optimization)
  - Others range 8-16KB each

**Tests/:**
- Purpose: Pester unit tests for all modules and scripts
- Contains: .Tests.ps1 files (one per module/feature)
- Run Command: `Invoke-Pester -Path .\Tests -Output Detailed`
- Not deployed: Excluded from distribution zip
- Test Count: 323 tests across 10 module test files + 4 integration/validation test files

**DomainController/:**
- Purpose: GPO deployment for WSUS client configuration
- Contains: PowerShell script and GPO backup files (GUID-based folders)
- Audience: Domain Controller admins
- Deployment: Included in distribution zip for reference

**build/:**
- Purpose: Build and validation scripts
- Contains: PS2EXE compilation scripts and validation logic
- Main Script: `build.ps1` (handles compilation, testing, code review)

**dist/:**
- Purpose: Build artifacts (EXE and distribution package)
- Status: Gitignored (artifacts not committed)
- Contents: WsusManager.exe and WsusManager-vX.X.X.zip with Scripts/Modules/DomainController

**.planning/codebase/:**
- Purpose: AI-generated codebase analysis documents
- Contents: ARCHITECTURE.md, STRUCTURE.md, CONVENTIONS.md, TESTING.md, STACK.md, INTEGRATIONS.md, CONCERNS.md

## Key File Locations

**Entry Points:**
- `Scripts/WsusManagementGui.ps1`: Main GUI application (starts on EXE execution)
- `Scripts/Invoke-WsusManagement.ps1`: CLI operations (health, cleanup, restore, reset, export, import, diagnostics)
- `Scripts/Invoke-WsusMonthlyMaintenance.ps1`: Scheduled maintenance automation (sync, approve, cleanup, export)
- `Scripts/Install-WsusWithSqlExpress.ps1`: WSUS + SQL installation
- `Scripts/Invoke-WsusClientCheckIn.ps1`: Client sync operations
- `Scripts/Set-WsusHttps.ps1`: HTTPS configuration

**Configuration:**
- `Modules/WsusConfig.psm1`: Centralized configuration constants (paths, timeouts, batch sizes, dialog sizes)
- `%APPDATA%\WsusManager\settings.json`: GUI runtime settings (ContentPath, SqlInstance, ExportRoot, ServerMode)
- `C:\WSUS\Logs\`: Daily log files (WsusManagement_YYYY-MM-DD.log, WsusOperations_YYYY-MM-DD.log)

**Core Business Logic:**
- `Modules/WsusUtilities.psm1`: Logging, SQL wrapper, path validation (used by all)
- `Modules/WsusHealth.psm1`: Diagnostics and auto-repair (1000+ LOC)
- `Modules/WsusDatabase.psm1`: Database cleanup and optimization (600+ LOC)
- `Modules/WsusServices.psm1`: Service control and monitoring
- `Modules/WsusExport.psm1`: Air-gapped export/import operations

**Testing:**
- `Tests/Invoke-Tests.ps1`: Main test runner entry point
- `Tests/WsusHealth.Tests.ps1`: Health check and diagnostics tests
- `Tests/WsusDatabase.Tests.ps1`: Database operation tests (15KB)
- `Tests/CliIntegration.Tests.ps1`: CLI parameter validation and operation tests
- `Tests/ExeValidation.Tests.ps1`: Compiled EXE validation (PE header, version, architecture)

**Build System:**
- `build.ps1`: Main build script (compilation, testing, packaging)
- `build/Invoke-LocalValidation.ps1`: Pre-build validation

## Naming Conventions

**Files:**
- Scripts: `Invoke-WsusOperationName.ps1` or `Set-WsusFeature.ps1` (approved PowerShell verbs)
- Modules: `Wsus[Domain].psm1` where domain = Services, Health, Database, Firewall, Permissions, Export, ScheduledTask, Config, AutoDetection, AsyncHelpers, Utilities
- Tests: `Wsus[Domain].Tests.ps1` (matches module name)
- Example: `WsusHealth.psm1` → `WsusHealth.Tests.ps1`

**Functions:**
- Public functions in modules: `[Verb]-Wsus[Noun]` (camelCase for parameters)
  - Examples: `Invoke-WsusFullDiagnostics`, `Get-WsusDatabaseSize`, `Start-WsusServices`
- Private functions: Same pattern but not in `Export-ModuleMember` list
- Support functions: `[Verb]-[Description]` or helper name pattern
- Approved verbs: Get, Set, Start, Stop, Test, Invoke, New, Remove, Add, Update

**Variables:**
- Script scope: `$script:VariableName` (for state that persists across function calls)
- Module scope: `$script:WsusConfig`, `$script:LogPath` (module-level caching)
- Function scope: `$local` or `$myVar` (defaults to local)
- Constants: ALL_CAPS in configuration arrays
- GUI controls: `$controls[BtnName]`, accessed via hashtable populated from XAML

**Directories:**
- Standard layout: `Scripts/`, `Modules/`, `Tests/`, `DomainController/`
- Flat layout (some deployments): All under one root folder with `Scripts/`, `Modules/` subfolders
- Nested layout (some edge cases): Scripts in `Scripts/Scripts/` with Modules in `../../Modules/`

## Where to Add New Code

**New CLI Operation:**
1. Create new function in appropriate module (`Modules/Wsus[Domain].psm1`)
2. Add function to `Export-ModuleMember` list in that module
3. Call it from `Scripts/Invoke-WsusManagement.ps1` or `Scripts/Invoke-WsusMonthlyMaintenance.ps1`
4. Add parameter set to CLI script if user-configurable
5. Add button/menu item to `Scripts/WsusManagementGui.ps1` if GUI-accessible
6. Create test file `Tests/Wsus[Domain].Tests.ps1` if new module
7. Add tests to existing test file if function added to existing module

**New Module (Rare):**
1. Create `Modules/Wsus[Domain].psm1` following existing patterns
2. Import WsusUtilities at top (dependency)
3. Import other required modules (WsusServices, WsusFirewall, etc.)
4. Define all functions with comment-based help
5. Add `Export-ModuleMember -Function functionname1, functionname2` at end
6. Create corresponding `Tests/Wsus[Domain].Tests.ps1` with Pester tests
7. Document module purpose in module header comment

**New Feature in Existing Module:**
1. Add function to appropriate module file `Modules/Wsus[Domain].psm1`
2. Add to `Export-ModuleMember` list if public function
3. Add tests to `Tests/Wsus[Domain].Tests.ps1`
4. Run tests locally: `Invoke-Pester -Path .\Tests\Wsus[Domain].Tests.ps1`
5. Update CLAUDE.md if user-facing behavior changes

**GUI Dialog or Button:**
1. Add XAML control definition in `<Window>` or dialog XAML section
2. Create click handler in `Scripts/WsusManagementGui.ps1`
3. If new operation, add to `$script:OperationButtons` array for disable/enable during operations
4. If new dialog, add ESC key handler: `$dlg.Add_KeyDown({ param($s, $e); if ($e.Key -eq [System.Windows.Input.Key]::Escape) { $s.Close() } })`
5. Build and test: `.\build.ps1`
6. Manual testing on Windows 10/11 as non-admin and with admin

**New Test:**
1. Add to appropriate test file (e.g., `Tests/WsusHealth.Tests.ps1` for health tests)
2. Follow existing test pattern: `Describe` → `Context` → `It` → `Assert`
3. Mock external dependencies (SQL, services, filesystem)
4. Run test: `Invoke-Pester -Path .\Tests\Wsus[Domain].Tests.ps1`
5. Run all tests before commit: `.\build.ps1 -TestOnly`

## Special Directories

**dist/:**
- Purpose: Build artifacts directory
- Generated by: `build.ps1` script
- Contents: `WsusManager.exe`, `WsusManager-vX.X.X.zip` (with Scripts/, Modules/, DomainController/ folders included)
- Committed: No (gitignored)
- Distribution: Zip file used for manual deployment

**.github/workflows/:**
- Purpose: GitHub Actions CI/CD pipeline
- Main job: `build.yml` handles compilation, testing, packaging, release publication
- Runs on: Every push and pull request
- Artifacts: Exe and zip uploaded to GitHub Actions
- Releases: Auto-published to GitHub Releases tab

**Tests/ (Build Excludes):**
- ExeValidation.Tests.ps1 - Runs AFTER build (checks if exe exists)
- FlaUI.Tests.ps1 - Requires FlaUI library (optional for CI/CD)
- Integration.Tests.ps1 - Requires running WSUS services (optional for CI/CD)
- Standard unit tests - Run every build in pre-build test job

## Module Dependency Map

```
WsusUtilities (foundation - used by all)
    ↓
WsusServices (service control)
    ↑
WsusHealth (depends on Services, Firewall, Permissions)
    ↑
[Other modules]
    ↓
CLI Scripts (Invoke-WsusManagement.ps1, Invoke-WsusMonthlyMaintenance.ps1)
    ↓
GUI (WsusManagementGui.ps1) [invokes CLI as child processes]
```

**Detailed Dependencies:**
- `WsusHealth.psm1` explicitly imports: WsusUtilities, WsusServices, WsusFirewall, WsusPermissions
- `WsusDatabase.psm1` depends on: WsusUtilities (for Invoke-WsusSqlcmd)
- `WsusServices.psm1` depends on: WsusUtilities (for Write-* logging functions)
- All others depend on: WsusUtilities
- `AsyncHelpers.psm1` is standalone (no dependencies on other WSUS modules)

## Code Paths for Common Operations

**Health Check (GUI):**
```
WsusManagementGui.ps1
  → BtnDiagnostics.Click event handler
  → Builds command: "& 'Invoke-WsusManagement.ps1' -Diagnostics"
  → Start-Process powershell.exe
Invoke-WsusManagement.ps1
  → Imports WsusHealth.psm1
  → Calls Invoke-WsusFullDiagnostics
WsusHealth.psm1
  → Calls Test-WsusSqlConnectivity
  → Calls Test-WsusServiceHealth
  → Calls Test-WsusFirewallRules
  → Calls Repair-* functions if -Repair flag set
  → Outputs results to console
```

**Deep Cleanup:**
```
WsusManagementGui.ps1 QBtnCleanup.Click
  → "& 'Invoke-WsusManagement.ps1' -Cleanup -Force"
Invoke-WsusManagement.ps1 -Cleanup parameter set
  → Imports WsusDatabase.psm1
  → Calls Invoke-WsusServerCleanup (built-in WSUS cleanup)
  → Calls Remove-DeclinedSupersessionRecords
  → Calls Remove-SupersededSupersessionRecords (batched 10k/batch)
  → Calls Delete-DeclinedUpdates (batched 100/batch)
  → Calls Optimize-WsusIndexes
  → Calls Invoke-WsusDatabaseShrink (with 3 retry attempts)
  → Outputs progress and timing
```

**Monthly Maintenance:**
```
Scheduled Task runs: Invoke-WsusMonthlyMaintenance.ps1 -MaintenanceProfile Full -Unattended
  → Detects modules via dynamic path search
  → Imports modules: WsusUtilities, WsusHealth, WsusDatabase, WsusExport
  → Based on profile (Full/Quick/SyncOnly):
    1. Sync with Microsoft (Invoke-WsusServerSync)
    2. Decline obsolete/expired updates
    3. Auto-approve Critical/Security updates
    4. Run deep cleanup (Remove-Supersession, Optimize-Indexes, Shrink-DB)
    5. Backup database
    6. Export full content + differential archive
  → Logs to C:\WSUS\Logs\
  → Sends completion summary to console (captured by Task Scheduler)
```

---

*Structure analysis: 2026-02-19*
