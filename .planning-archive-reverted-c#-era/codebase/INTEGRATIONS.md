# External Integrations

**Analysis Date:** 2026-02-19

## APIs & External Services

**WSUS Server Administration API:**
- Service: Microsoft Update Services
- What it's used for: WSUS server operations (cleanup, synchronization, update management)
  - DLL: `Microsoft.UpdateServices.Administration.dll` (installed with WSUS role)
  - Location: `$env:ProgramFiles\Update Services\Api\`
  - Loaded by: `Invoke-WsusMonthlyMaintenance.ps1` (line 267), `Invoke-WsusManagement.ps1`
  - Operations: `Invoke-WsusServerCleanup()`, server state queries, update classification management

**Windows Update Agent API:**
- Service: Windows Update
- What it's used for: Force WSUS client detection and reporting
  - CLI tool: `wuauclt.exe` (Windows Update Agent)
  - Used by: `Invoke-WsusClientCheckIn.ps1`
  - Commands: `/detectnow` (force update detection), `/reportnow` (force reporting to WSUS)

**WSUS/IIS Web Service:**
- Service: Internet Information Services (IIS)
- What it's used for: WSUS web interface and API endpoint
  - Module: `WebAdministration` (PowerShell built-in)
  - Used in: `Install-WsusWithSqlExpress.ps1`, `Set-WsusHttps.ps1`, `WsusAutoDetection.psm1`
  - Operations: App pool verification, site binding configuration, HTTPS setup

## Data Storage

**SQL Server Express:**
- Provider: Microsoft SQL Server Express 2022
- Connection: `.\SQLEXPRESS` (named instance, localhost)
  - Client: SqlServer PowerShell Module (via `Invoke-Sqlcmd`)
  - Authentication: SQL authentication (sa user account)
  - Query wrapper: `Invoke-WsusSqlcmd` in `WsusUtilities.psm1` (handles TrustServerCertificate detection)

- Database: SUSDB (Windows Internal Database for WSUS)
  - Size: 10GB limit (monitored in GUI `Update-Dashboard` function, alerts near capacity)
  - Operations: Update metadata, approval history, client status, file tracking
  - Used by: `WsusDatabase.psm1` for maintenance (cleanup, indexing, statistics)

**Backup/Restore:**
- Backup location: `C:\WSUS\Backup\` (optional, created during export operations)
- Restore path: User-selected via folder browser dialog
- Backup format: SQL Server backup files (`.bak`), optionally copied to export media

**File Storage:**
- WSUS Content Path: `C:\WSUS\` (local filesystem, can be configured)
  - Subdirectories: `WSUS\WsusContent\` (update files), `WSUS\Logs\`, `WSUS\SQLDB\`
  - Read/write operations: Via `robocopy.exe` for export, file system APIs for configuration
  - Size monitoring: Dashboard shows total size and available space
  - Permissions: Managed by `WsusPermissions.psm1` (ACLs via `icacls.exe`)

- Export destination: User-specified path (local or UNC path via folder browser)
  - Export modes: Full copy (all files), Differential (last N days)
  - Tool: `robocopy.exe` with multi-threading (16 threads default)
  - Used by: `Invoke-WsusMonthlyMaintenance.ps1`, GUI export operations

**Caching:**
- None - No external caching service used
- In-memory dashboard refresh: 30-second interval with deduplication tracking

## Authentication & Identity

**Auth Provider:**
- Custom - No external auth service
- Implementation:
  - Admin privilege check: `[Security.Principal.WindowsIdentity]::GetCurrent()` via `WindowsPrincipal`
  - SQL authentication: sa account (hardcoded username, prompted for password in install)
  - Service account: NETWORK SERVICE (for WSUS service), IIS_IUSRS (for IIS app pool)
  - Scheduled task credentials: User-provided domain credentials (prompted in task dialog)

**Registry-based Configuration:**
- WSUS settings: `HKLM:\SOFTWARE\Microsoft\Update Services\Server\Setup\`
- Content path: Registry lookup in `Get-WsusContentPath` function in `WsusUtilities.psm1`
- SQL configuration: Registry lookup for SQL Server port configuration (set to static 1433)

## Monitoring & Observability

**Error Tracking:**
- None - No external error tracking service
- Implementation: File-based logging to `C:\WSUS\Logs\WsusOperations_YYYY-MM-DD.log`

**Logs:**
- Approach: Local file logging via `Write-Log` function in `WsusUtilities.psm1`
- Path: `C:\WSUS\Logs\WsusOperations_YYYY-MM-DD.log` (daily rotation)
- Format: Timestamped entries `[HH:mm:ss] Message`
- GUI log panel: Real-time capture from background process output (async readers with `Dispatcher.Invoke`)
- Operations logged:
  - Startup/shutdown with duration
  - Database operations (size, cleanup, index optimization)
  - Service state changes
  - Health check results
  - Sync progress (10% increments logged)

**Dashboard Metrics:**
- Collected in memory from:
  - SQL database stats (update counts, revision states, file status)
  - File system (WSUS content size, available disk space)
  - Service states (SQL, WSUS, IIS status)
  - Network connectivity (ping test with 500ms timeout)
- Refreshed every 30 seconds (configurable, set in `WsusConfig.psm1`)

## CI/CD & Deployment

**Hosting:**
- GitHub - Source code and artifact repository
- GitHub Actions - CI pipeline (`.github/workflows/build.yml`)

**Build Pipeline:**
- Trigger: Push to main/master/develop, or manual via workflow_dispatch
- Runner: `windows-latest` (Windows Server with PowerShell)
- Concurrency: Single build per branch (`cancel-in-progress: true`)

**Build Steps (build.yml):**
1. Checkout repository (actions/checkout@v4)
2. Install PSScriptAnalyzer 1.21.0+
3. Run PSScriptAnalyzer on all `.ps1` and `.psm1` files
4. Run Pester tests (323 unit tests)
5. Run PS2EXE compilation to `.exe`
6. Run EXE validation tests (PE header, 64-bit, version info)
7. Create distribution zip (`Scripts/`, `Modules/`, `DomainController/`, branding assets)
8. Upload artifacts to GitHub Actions
9. Auto-publish release with version tag

**Manual Build Locally:**
- Command: `.\build.ps1` (with optional flags)
- Outputs: `dist/WsusManager.exe` and `dist/WsusManager-vX.X.X.zip`

**GitHub Automation:**
- Dependabot: Auto-merge minor/patch version updates (`.github/workflows/dependabot-auto-merge.yml`)
- Repository hygiene: Nightly cleanup of stale PRs and branches (`.github/workflows/repo-hygiene.yml`)

## Environment Configuration

**Required Environment Variables:**
- None required for GUI execution
- Optional for automation:
  - `WSUS_TASK_PASSWORD` - Scheduled task password (set dynamically by GUI, cleared after use)

**Secrets Location:**
- None stored in `.env` files
- SQL sa password: Prompted at installation (not stored on disk)
- Scheduled task credentials: Prompted in UI dialog, passed via environment variable (cleaned up)
- Settings file: `%APPDATA%\WsusManager\settings.json` (contains paths and server mode, no secrets)

**Configuration Files:**
- `.PSScriptAnalyzerSettings.psd1` - Code quality rules
- `build.ps1` - Build process automation (version: line 52)
- `metadata.json` - Package metadata (version reference)

## Webhooks & Callbacks

**Incoming:**
- None - Application does not expose web endpoints

**Outgoing:**
- None - Application does not call external webhooks
- Exception: HTTP/HTTPS requests to WSUS server (8530/8531) are internal network calls, not webhooks

## Windows Services & System Integration

**Windows Services Managed:**
- SQL Server Express (`MSSQL$SQLEXPRESS` service)
  - Start/Stop operations: `Start-SqlServerExpress`, `Stop-SqlServerExpress` in `WsusServices.psm1`
  - Health check: `Test-ServiceRunning` verifies status
  - Monitoring: Service status tracked in GUI dashboard

- WSUS Service (`WsusService`)
  - Status monitoring: Checked before operations execute
  - Auto-start logic: Attempted on operation failures via `WsusAutoDetection.psm1`
  - Health repair: Restart operations via `Repair-WsusServices`

- IIS Web Service (`W3SVC`, `WAS`)
  - Start/Stop operations: Via `WebAdministration` module
  - Health check: Verifies app pool health
  - Configuration: HTTPS binding setup via `Set-WsusHttps.ps1`

**Firewall Integration:**
- Windows Firewall rules created via `New-NetFirewallRule` (PowerShell Netsh wrapper)
- Rules defined in `WsusFirewall.psm1`:
  - `WSUS HTTP Traffic (Port 8530)` - Inbound TCP, all profiles
  - `WSUS HTTPS Traffic (Port 8531)` - Inbound TCP, all profiles
  - `SQL Server (TCP 1433)` - Inbound TCP, Domain/Private profiles
  - `SQL Browser (UDP 1434)` - Inbound UDP, Domain/Private profiles

**Scheduled Tasks:**
- Created via `Register-ScheduledTask` with custom credentials
- Task name: `WSUS Manager Monthly Maintenance`
- User account: Prompted at task creation (default: `.\dod_admin`)
- Trigger: User-defined (day of month, time)
- Action: Runs `Invoke-WsusMonthlyMaintenance.ps1` with specified profile

**Registry Operations:**
- Read: WSUS content path lookup (install detection)
- Write: WSUS configuration (content path, protocol settings, port numbers)
- Affected keys: `HKLM:\SOFTWARE\Microsoft\Update Services\Server\Setup\`

**File System Security:**
- ACL management via `icacls.exe`:
  - SYSTEM: Full (OI)(CI)F
  - Administrators: Full (OI)(CI)F
  - NETWORK SERVICE: Full (OI)(CI)F (for SQL/WSUS service)
  - NT AUTHORITY\LOCAL SERVICE: Full (OI)(CI)F
  - IIS_IUSRS: Read (OI)(CI)R
  - IIS APPPOOL\WsusPool: Full (OI)(CI)F (for IIS app pool)

## Data Export/Import (Air-Gap Support)

**Export Operations:**
- Source: Local WSUS content (`C:\WSUS\`) and SUSDB
- Destination: USB drive or network share (air-gap network)
- Tool: `robocopy.exe` for file copy, SQL backup for database
- Modes:
  - Full copy: All WSUS content files
  - Differential copy: Files modified within N days (default 30)
- Exclusions: `.bak`, `.log` files; Logs, SQLDB, Backup directories
- Used by: `Invoke-WsusMonthlyMaintenance.ps1`, `WsusExport.psm1`

**Import Operations:**
- Source: USB drive or network share (from air-gap network)
- Destination: `C:\WSUS\` or user-specified path
- Process: Robocopy + database restore
- Used by: GUI Transfer dialog, `Invoke-WsusManagement.ps1`
- Air-gap scenario: Initial sync via disconnected media, subsequent differential updates

---

*Integration audit: 2026-02-19*
