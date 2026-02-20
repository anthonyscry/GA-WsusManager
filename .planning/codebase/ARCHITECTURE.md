# Architecture

**Analysis Date:** 2026-02-19

## Pattern Overview

**Overall:** Layered modular architecture with a WPF GUI presentation layer, CLI script orchestration layer, and reusable PowerShell module library layer.

**Key Characteristics:**
- **Separation of concerns:** GUI, CLI scripts, and modules each have distinct responsibilities
- **Module-based code reuse:** 11 PowerShell modules provide shared functionality across GUI and CLI
- **Dynamic path resolution:** Scripts auto-detect module locations to support multiple deployment layouts
- **Process-based interop:** GUI invokes CLI scripts as child processes for isolation and logging
- **Backward compatibility:** Supports both standard deployment (root/Scripts/Modules) and flat layouts

## Layers

**Presentation Layer (WPF GUI):**
- Purpose: Interactive dashboard, operation dialogs, status monitoring, and user-friendly interfaces
- Location: `Scripts/WsusManagementGui.ps1`
- Contains: XAML UI definitions, event handlers, dialog windows, real-time dashboard refresh
- Depends on: None directly (invokes CLI scripts via process)
- Used by: End users through GUI or compiled EXE

**Orchestration Layer (CLI Scripts):**
- Purpose: Command-line entry points that coordinate modules to perform operations
- Location: `Scripts/` directory
  - `Invoke-WsusManagement.ps1` - Main CLI for health, cleanup, restore, diagnostics, reset
  - `Invoke-WsusMonthlyMaintenance.ps1` - Maintenance automation with profiles and export
  - `Install-WsusWithSqlExpress.ps1` - WSUS + SQL installation
  - `Invoke-WsusClientCheckIn.ps1` - Client synchronization
  - `Set-WsusHttps.ps1` - HTTPS configuration
- Contains: Parameter handling, operation logic coordination, logging setup, error handling
- Depends on: Modules (WsusUtilities, WsusHealth, WsusDatabase, WsusExport, etc.)
- Used by: GUI (via Start-Process), scheduled tasks, administrators via PowerShell

**Module Layer (Core Logic):**
- Purpose: Reusable functions for specific domains (services, database, health, firewall, etc.)
- Location: `Modules/` directory (11 modules, ~180KB total)
- Contains: Domain-specific implementations, no orchestration logic
- Depends on: Other modules and Windows APIs
- Used by: CLI scripts and other modules

## Layers (Detail)

**Utilities Layer (`WsusUtilities.psm1`):**
- Purpose: Foundation functions used by all modules and scripts
- Location: `Modules/WsusUtilities.psm1`
- Exports: Color output, logging, SQL operations, path validation, admin checks
- Key Functions:
  - `Write-Success`, `Write-Failure`, `Write-Info`, `Write-WsusWarning` - Color-coded output
  - `Start-WsusLogging`, `Stop-WsusLogging`, `Write-Log` - File-based logging to `C:\WSUS\Logs\`
  - `Invoke-WsusSqlcmd` - SQL wrapper that auto-detects SqlServer module version for TrustServerCertificate compatibility
  - `Test-AdminPrivileges`, `Test-SafePath`, `Get-EscapedPath` - Security functions
- Used by: All other modules and CLI scripts

**Service Management Layer (`WsusServices.psm1`):**
- Purpose: Windows service control and monitoring
- Location: `Modules/WsusServices.psm1`
- Exports: Functions to start/stop/check SQL Server, WSUS, IIS services
- Key Functions:
  - `Get-WsusServiceStatus` - Get status of all critical services
  - `Start-WsusServices`, `Stop-WsusServices` - Service control with retries
  - `Test-ServiceRunning` - Check if service is running
- Used by: WsusHealth, Invoke-WsusManagement

**Health & Diagnostics Layer (`WsusHealth.psm1`):**
- Purpose: Comprehensive diagnostics and automatic repair
- Location: `Modules/WsusHealth.psm1`
- Exports: Health checks, auto-repair functions, SSL status
- Key Functions:
  - `Invoke-WsusFullDiagnostics` - Run all checks and optional repairs
  - `Test-WsusSqlConnectivity` - Verify database connectivity
  - `Test-WsusServiceHealth` - Check service status
  - `Get-WsusSSLStatus` - Check HTTPS configuration
  - Various repair functions (Fix-WsusServices, Fix-Firewall, etc.)
- Dependencies: WsusServices, WsusFirewall, WsusPermissions
- Used by: Invoke-WsusManagement.ps1 (-Health, -Repair, -Diagnostics)

**Database Layer (`WsusDatabase.psm1`):**
- Purpose: Database maintenance, cleanup, and size monitoring
- Location: `Modules/WsusDatabase.psm1`
- Exports: Database cleanup, index optimization, size monitoring
- Key Functions:
  - `Get-WsusDatabaseSize` - Query SUSDB size in GB
  - `Get-WsusDatabaseStats` - Get comprehensive stats (obsolete updates, file counts, etc.)
  - `Remove-DeclinedSupersessionRecords` - Remove records for declined updates
  - `Remove-SupersededSupersessionRecords` - Remove records for superseded updates
  - `Invoke-WsusDatabaseShrink` - Shrink database after cleanup (with retry logic)
  - `Optimize-WsusIndexes` - Rebuild/reorganize fragmented indexes
- Used by: Invoke-WsusManagement.ps1 (-Cleanup), Invoke-WsusMonthlyMaintenance.ps1

**Firewall Layer (`WsusFirewall.psm1`):**
- Purpose: Firewall rule management for WSUS ports
- Location: `Modules/WsusFirewall.psm1`
- Exports: Firewall rule creation, verification
- Key Functions:
  - `Test-WsusFirewallRules` - Verify inbound rules exist
  - `Add-WsusFirewallRules` - Create rules for WSUS ports (8530, 8531)
- Used by: WsusHealth for auto-repair

**Permissions Layer (`WsusPermissions.psm1`):**
- Purpose: WSUS directory and SQL permissions management
- Location: `Modules/WsusPermissions.psm1`
- Exports: Permission verification and repair
- Key Functions:
  - `Test-WsusDirectoryPermissions` - Check WSUS folder permissions
  - `Test-WsusSqlPermissions` - Check SQL login and permissions
  - `Repair-WsusDirectoryPermissions` - Fix directory ownership/permissions
- Used by: WsusHealth for auto-repair

**Export/Import Layer (`WsusExport.psm1`):**
- Purpose: WSUS content and database export/import for air-gapped networks
- Location: `Modules/WsusExport.psm1`
- Exports: Export/import functions for media transfer
- Key Functions:
  - `Invoke-ExportToMedia` - Export content and database backup to removable media
  - `Invoke-ImportFromMedia` - Import content and database from media
- Used by: Invoke-WsusManagement.ps1 (-Export, -Import)

**Scheduled Task Layer (`WsusScheduledTask.psm1`):**
- Purpose: Scheduled task creation and management
- Location: `Modules/WsusScheduledTask.psm1`
- Exports: Task creation, deletion, status
- Key Functions:
  - `New-WsusScheduledTask` - Create maintenance task with cron schedule
  - `Remove-WsusScheduledTask` - Delete existing task
  - `Get-WsusScheduledTaskStatus` - Get task execution status
- Used by: GUI for "Schedule Task" dialog

**Configuration Layer (`WsusConfig.psm1`):**
- Purpose: Centralized configuration constants and settings
- Location: `Modules/WsusConfig.psm1`
- Exports: Configuration getter functions
- Key Values:
  - SQL configuration (instance, database name, timeouts)
  - WSUS paths (C:\WSUS, C:\WSUS\Logs)
  - Service names and port numbers
  - GUI dialog sizes and timer intervals
  - Retry configuration (DB shrink, service start, sync)
  - Maintenance settings (backup retention, update cutoff age, batch sizes)
- Usage Pattern: `Get-WsusGuiSetting`, `Get-WsusRetrySetting`, `Get-WsusDialogSize`, `Get-WsusTimerInterval`
- Used by: All scripts and modules for consistent configuration

**Auto-Detection Layer (`WsusAutoDetection.psm1`):**
- Purpose: Enhanced detection and monitoring for dashboard
- Location: `Modules/WsusAutoDetection.psm1`
- Exports: Service status detection, database monitoring, health aggregation
- Key Functions:
  - `Get-DetailedServiceStatus` - Batch-query all services in single RPC call
  - `Get-DatabaseSizeStatus` - Monitor SUSDB size with thresholds
  - `Get-WsusScheduledTaskStatus` - Get task status and last execution
  - `Get-WsusHealthSummary` - Overall health status aggregation
- Used by: GUI dashboard for real-time status display

**Async Helpers Layer (`AsyncHelpers.psm1`):**
- Purpose: Background operations and async execution for WPF GUI
- Location: `Modules/AsyncHelpers.psm1`
- Exports: Async execution, runspace pool management, UI thread dispatch
- Key Functions:
  - `Initialize-AsyncRunspacePool`, `Close-AsyncRunspacePool` - Pool lifecycle
  - `Invoke-Async`, `Wait-Async`, `Test-AsyncComplete` - Async execution
  - `Invoke-UIThread` - Safe UI thread marshalling
  - `Start-BackgroundOperation` - Complete async workflow with callbacks
- Used by: WsusManagementGui.ps1 for background operations

## Data Flow

**GUI Operation Flow:**
```
User clicks button in GUI
  ↓
Event handler shows dialog (if needed)
  ↓
User confirms operation
  ↓
GUI shows operation panel
  ↓
GUI builds command string with parameters
  ↓
GUI invokes CLI script as child process: Start-Process powershell.exe -ArgumentList "& 'script.ps1' -param value"
  ↓
CLI script loads required modules from dynamic search paths
  ↓
CLI script calls module functions: Import-Module module.psm1; Invoke-ModuleFunction
  ↓
Module function executes business logic
  ↓
Process writes output to stdout (captured by GUI)
  ↓
GUI displays output in log panel
  ↓
Process exits
  ↓
GUI re-enables buttons and updates dashboard
```

**Example: Health Check Flow:**
1. User clicks "Run Diagnostics" button in GUI
2. GUI event handler calls `Show-Panel "Operation" "Diagnostics" "BtnDiagnostics"`
3. GUI builds: `"& '$mgmt' -Diagnostics -ContentPath 'C:\WSUS' -SqlInstance '.\SQLEXPRESS'"`
4. GUI starts process: `Start-Process powershell.exe -RedirectStandardOutput ...`
5. CLI script (`Invoke-WsusManagement.ps1`) starts:
   - Parses `-Diagnostics` parameter
   - Imports `WsusHealth.psm1` module
   - Calls `Invoke-WsusFullDiagnostics -ContentPath C:\WSUS -Repair:$false`
6. `Invoke-WsusFullDiagnostics` runs all checks:
   - Calls `Test-WsusSqlConnectivity` (from WsusDatabase module)
   - Calls `Test-WsusServiceHealth` (from WsusServices module)
   - Calls `Test-WsusFirewallRules` (from WsusFirewall module)
   - Outputs results to stdout
7. GUI captures output in log panel
8. Process exits, GUI re-enables buttons

**Settings Persistence:**
- GUI settings stored in: `%APPDATA%\WsusManager\settings.json`
- Contains: ContentPath, SqlInstance, ExportRoot, ServerMode, LiveTerminalMode
- Loaded at startup via `Import-WsusSettings`
- Saved on change via `Save-Settings`

**Logging:**
- All operations log to: `C:\WSUS\Logs\WsusManagement_YYYY-MM-DD.log`
- Log entries prefixed with timestamp and operation marker
- GUI writes startup/shutdown markers for correlation
- CLI scripts append session start/end markers

## State Management

**GUI State Variables:**
- `$script:OperationRunning` - Flag to block concurrent operations
- `$script:CurrentProcess` - Handle to running child process
- `$script:ServerMode` - "Online" or "Air-Gap" based on internet connectivity
- `$script:RefreshInProgress` - Flag to prevent concurrent dashboard refreshes
- `$script:LiveTerminalMode` - Console window vs embedded log panel
- Event job references: `$script:OutputEventJob`, `$script:ErrorEventJob`, `$script:ExitEventJob`

**Module State:**
- `WsusUtilities` caches SqlServer module version at load time for TrustServerCertificate compatibility
- `WsusAutoDetection` caches service definitions for batch querying
- Most other modules are stateless (pure functions)

**Cross-Script State:**
- Shared log file (`C:\WSUS\Logs\WsusManagement_YYYY-MM-DD.log`) enables operation correlation
- Scheduled task stored in Windows Task Scheduler (WMI-based)
- Settings file in %APPDATA% for GUI persistence across sessions

## Key Abstractions

**Module Loading Pattern:**
- All CLI scripts use dynamic module path resolution
- Search paths checked in order: script folder, parent folder, grandparent folder, same folder as script
- Handles flat layouts (Modules alongside script) and standard layouts (Modules in parent)
- Example from `Invoke-WsusManagement.ps1`:
  ```powershell
  $moduleSearchPaths = @(
      (Join-Path $ScriptRoot "Modules"),
      (Join-Path (Split-Path $ScriptRoot -Parent) "Modules"),
      (Join-Path (Split-Path (Split-Path $ScriptRoot -Parent) -Parent) "Modules"),
      $ScriptsFolder
  )
  ```

**SQL Wrapper Pattern:**
- `Invoke-WsusSqlcmd` abstracts SqlServer module version compatibility
- Automatically detects if `-TrustServerCertificate` is supported (v21.1+)
- Used by all database functions to handle different SQL module versions gracefully

**Path Validation Pattern:**
- `Test-SafePath` validates paths to prevent command injection
- `Get-EscapedPath` escapes single quotes for safe embedding in command strings
- Used everywhere paths are passed to other scripts

**Service Status Pattern:**
- `Get-DetailedServiceStatus` in AutoDetection module batch-queries services in single RPC call
- Reduces performance impact compared to calling Get-Service 5 times individually
- Caches service definitions at module load for reuse

**Configuration Pattern:**
- `WsusConfig.psm1` is single source of truth for all configuration
- No hardcoded values scattered in code
- Functions like `Get-WsusGuiSetting`, `Get-WsusRetrySetting` provide type-safe access

**Process Isolation Pattern:**
- GUI invokes CLI scripts as separate processes for:
  - Error isolation (script crash doesn't crash GUI)
  - Clear logging (separate log entries per operation)
  - Admin privilege separation (can elevate script independently)
- Output captured via stdout redirection into GUI log panel

## Entry Points

**GUI Entry Point:**
- Location: `Scripts/WsusManagementGui.ps1`
- Triggers: User double-clicks compiled EXE or runs script directly
- Responsibilities:
  1. Load settings from %APPDATA%\WsusManager\settings.json
  2. Check admin privileges
  3. Create WPF window and load XAML
  4. Populate dashboard with current status
  5. Start 30-second auto-refresh timer
  6. Show window and wait for user interaction
  7. Handle button clicks and dialogs
  8. Invoke CLI scripts as child processes for operations
  9. Display operation output in log panel
  10. Save settings on exit

**CLI Entry Point:**
- Location: `Scripts/Invoke-WsusManagement.ps1` (or via GUI invocation)
- Triggers: Called from GUI, scheduled task, or manual PowerShell execution
- Parameters: `-Health`, `-Repair`, `-Cleanup`, `-Reset`, `-Restore`, `-Export`, `-Import`, `-Diagnostics`
- Responsibilities:
  1. Detect module locations via dynamic search
  2. Import required modules
  3. Parse operation parameter
  4. Load settings if available
  5. Execute requested operation
  6. Log results to shared daily log file

**Monthly Maintenance Entry Point:**
- Location: `Scripts/Invoke-WsusMonthlyMaintenance.ps1`
- Triggers: Scheduled task created by GUI or manual execution
- Parameters: `-MaintenanceProfile Full/Quick/SyncOnly`, `-Unattended`, `-ExportPath`
- Responsibilities:
  1. Detect module locations via dynamic search
  2. Import modules (WsusUtilities, WsusHealth, WsusDatabase, WsusExport)
  3. Prompt for profile if interactive
  4. Execute profile operations in sequence: Sync → Approve → Cleanup → Export
  5. Generate operation summary with timing

**Install Entry Point:**
- Location: `Scripts/Install-WsusWithSqlExpress.ps1`
- Triggers: GUI Install button or manual execution
- Parameters: `-InstallerPath`, `-SaUsername`, `-SaPassword`, `-NonInteractive`
- Responsibilities:
  1. Validate admin privileges
  2. Check for SQL Server installers
  3. Install SQL Server Express 2022
  4. Install WSUS server role
  5. Configure WSUS for first use

## Error Handling

**Strategy:** Trap errors at module level, log them, and return meaningful results. CLI scripts catch errors and display user-friendly messages. GUI catches all exceptions and shows dialogs.

**Patterns:**
- Modules use `try/catch` with `Write-Warning` for non-critical failures
- Database queries use `Invoke-WsusSqlcmd` which wraps SqlServer module errors
- CLI scripts catch operation errors and print structured error messages
- GUI catches all top-level exceptions in `try/finally` block, shows error dialog, logs to file
- Service operations have retry logic with exponential backoff (WsusConfig Retry settings)

**Examples:**
- Database connectivity failures logged but don't crash health check
- Service start failures retry 3 times with 5-second delays (WsusConfig)
- Database shrink operations retry 3 times with 30-second delays if blocked by backup
- All errors appended to `C:\WSUS\Logs\WsusManagement_YYYY-MM-DD.log` for debugging

## Cross-Cutting Concerns

**Logging:**
- Centralized in `Start-WsusLogging`/`Stop-WsusLogging` functions from WsusUtilities
- All output goes to `C:\WSUS\Logs\WsusManagement_YYYY-MM-DD.log` (single daily file)
- GUI writes startup/shutdown markers to correlate GUI and CLI logging
- Timestamps on every line for performance analysis
- All module functions use `Write-Success`, `Write-Failure`, `Write-Info` for color-coded console output

**Validation:**
- Path validation: `Test-SafePath` checks for command injection characters
- SQL parameters: Wrapped queries use parameterized format or escaped values
- Service names: Pulled from WsusConfig constants, not user input
- Dialog inputs: Validated before passing to CLI scripts

**Authentication:**
- Admin check on GUI startup with clear error message if not running as admin
- All CLI scripts require `-RunAsAdministrator` comment
- SQL operations support Windows auth (current user) or SQL auth (sa user)
- Scheduled tasks prompt for credentials and run with those credentials

**Performance Monitoring:**
- GUI logs startup time at launch
- Dashboard refresh guarded by `$script:RefreshInProgress` flag
- Service status queries batch together (single RPC call via AutoDetection module)
- Database queries cached in AutoDetection for 30-second TTL on dashboard
- Sync progress logging only on 10% increments to reduce log volume

---

*Architecture analysis: 2026-02-19*
