# Phase 3: Diagnostics and Service Management - Context

**Gathered:** 2026-02-19
**Status:** Ready for planning

<domain>
## Phase Boundary

Administrators can run a comprehensive health check that detects and auto-repairs service failures, firewall rule problems, content directory permission issues, and SQL connectivity failures — and can start/stop individual services directly from the UI. Also includes sysadmin permission enforcement and content reset (wsusutil reset).

Requirements: DIAG-01 through DIAG-05, SVC-01 through SVC-03, FW-01, FW-02, PERM-01, PERM-02.

</domain>

<decisions>
## Implementation Decisions

### Health Check Result Presentation
- Sequential check execution with real-time streaming to the log panel — each check logs as it runs, not batched at the end
- Each check line shows a clear PASS/FAIL marker (e.g., `[PASS] SQL Server Express — Running` or `[FAIL] WSUS Service — Stopped`)
- Use colored markers: green for pass, red for fail, yellow for warning (e.g., service was stopped but auto-repaired)
- Summary line at the end: "Diagnostics complete: X/Y checks passed, Z auto-repaired"
- Match the PowerShell v3.8 check list: SQL Server Express, SQL Browser, TCP/IP protocol, Named Pipes protocol, SQL firewall rules, WSUS service, IIS service, WSUS Application Pool, WSUS firewall rules (8530/8531), SUSDB existence, NETWORK SERVICE SQL login, content directory permissions

### Auto-Repair Behavior
- AutoFix is always ON when run from the GUI — no confirmation dialog before each repair (matches PowerShell v3.8.10+ unified Diagnostics behavior)
- Repair attempts are logged inline: `[FAIL] WSUS Service — Stopped → Restarting... [FIXED]` or `→ Repair failed: <reason>`
- Service restarts follow dependency order: SQL Server first, then IIS, then WSUS (matching `Start-WsusAutoRecovery` pattern)
- Retry logic: 3 attempts with 5-second delays for service start failures
- Firewall rule creation uses `netsh advfirewall` commands for ports 8530 and 8531
- Permission repair applies NETWORK SERVICE and IIS_IUSRS ACLs to the content directory

### Service Control Integration
- "Start Services" remains a dashboard quick action button (already wired in Phase 2 UI)
- Individual service start/stop is available through the Diagnostics navigation panel — not a separate panel
- Service dependency ordering enforced: SQL must be running before WSUS can start; stopping WSUS before stopping SQL
- After any service state change, dashboard auto-refreshes immediately (don't wait for the 30-second timer)
- Service operations use the existing `RunOperationAsync` pattern with log panel output

### Content Reset (wsusutil reset)
- Accessed via a "Reset Content" button in the Diagnostics panel
- Confirmation dialog before running: "This will re-verify all content files against the database. This can take several minutes. Continue?"
- Runs `wsusutil.exe reset` via Process.Start with output captured to log panel
- No timeout — wsusutil reset can take 10+ minutes on large content stores
- Reports success/failure in log panel when complete

### Sysadmin Permission Check
- `Test-SqlSysadmin` equivalent runs before any database operation (Deep Cleanup, Backup, Restore in Phase 4)
- In Phase 3: implement the sysadmin check as a reusable Core service method
- Clear error message if user lacks permissions: "Current user does not have sysadmin permissions on SQL Server. Database operations require sysadmin access."
- Check is also included as one of the health check items (informational — no auto-fix possible for this)

### Claude's Discretion
- Exact C# service interfaces (IHealthService, IWindowsServiceManager, IFirewallService) — naming and method signatures
- Internal architecture of the health check pipeline (sequential awaits vs. parallel where independent)
- SQL protocol checks (TCP/IP, Named Pipes) — whether to include these or simplify since they're rarely misconfigured
- Exact WPF layout of the Diagnostics panel within the existing content area

</decisions>

<specifics>
## Specific Ideas

- The PowerShell version's `Invoke-WsusDiagnostics` in `WsusHealth.psm1` runs 12 checks with auto-fix — replicate this exact check list in C#
- Service dependency order from `Start-WsusAutoRecovery`: SQL Server Express (order 1), IIS/W3SVC (order 2), WSUS/WsusService (order 3)
- The PowerShell version uses `Get-Service` and `Start-Service`/`Stop-Service` — C# should use `System.ServiceProcess.ServiceController`
- Firewall rules use `netsh advfirewall firewall` — wrap in Process.Start, not a managed API
- Content reset uses `wsusutil.exe` from the WSUS install directory (typically `C:\Program Files\Update Services\Tools\`)
- The sysadmin check queries: `SELECT IS_SRVROLEMEMBER('sysadmin')` via SQL

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 03-diagnostics-and-service-management*
*Context gathered: 2026-02-19*
