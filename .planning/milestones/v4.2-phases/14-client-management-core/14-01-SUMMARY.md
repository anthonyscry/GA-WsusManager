---
phase: 14-client-management-core
plan: 01
subsystem: api
tags: [winrm, powershell, remote-management, error-codes, csharp, dotnet8]

# Dependency graph
requires:
  - phase: 13-operation-feedback-and-dialog-polish
    provides: IProcessRunner and ProcessResult used by WinRmExecutor
provides:
  - IClientService interface defining the 5 client management operations
  - WinRmExecutor class for remote PowerShell command execution via Invoke-Command
  - ClientDiagnosticResult, ConnectivityTestResult, WsusErrorInfo record models
  - WsusErrorCodes static dictionary with 20 common WSUS/WU error codes and fixes
affects:
  - 14-02 (service implementation — consumes IClientService and WinRmExecutor)
  - 14-03 (GUI wiring — binds to IClientService via DI)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - WinRM remote execution: WinRmExecutor wraps IProcessRunner for powershell.exe Invoke-Command
    - Hostname injection prevention: regex validation (alphanumeric, hyphens, dots only)
    - Graceful WinRM failure: connectivity errors return failed ProcessResult with Script Generator guidance, never throw
    - Error code lookup: static dictionary keyed by uppercase hex (no 0x prefix), Lookup() handles all input formats

key-files:
  created:
    - src/WsusManager.Core/Services/Interfaces/IClientService.cs
    - src/WsusManager.Core/Services/WinRmExecutor.cs
    - src/WsusManager.Core/Models/ClientDiagnosticResult.cs
    - src/WsusManager.Core/Models/WsusErrorCodes.cs
  modified: []

key-decisions:
  - "LookupErrorCode is synchronous (no remote call) — local dictionary lookup only, consistent with CLI-06 requirement"
  - "WinRmExecutor returns failed ProcessResult on WinRM error, never throws — callers receive graceful error with Script Generator fallback message"
  - "Hostname validated by regex before any process spawn — prevents command injection via maliciously crafted hostnames"
  - "WsusErrorCodes keyed by uppercase hex without 0x prefix (e.g., 80244010) — Lookup() normalizes all input formats including 0x prefix and decimal values"

patterns-established:
  - "WinRM graceful failure: IsWinRmConnectivityError detects WinRM-specific error patterns, augments output with Script Generator guidance"
  - "Script summary logging: first 80 chars of script block logged at debug level — keeps logs readable without leaking full command strings"

requirements-completed: [CLI-06, CLI-07]

# Metrics
duration: 3min
completed: 2026-02-21
---

# Phase 14 Plan 01: Client Management — Interface, Models, and Infrastructure Summary

**IClientService interface (5 ops), WinRmExecutor with hostname injection prevention, ClientDiagnosticResult/ConnectivityTestResult/WsusErrorInfo records, and WsusErrorCodes dictionary with 20 WSUS error codes and recommended fixes**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-21T03:43:13Z
- **Completed:** 2026-02-21T03:46:30Z
- **Tasks:** 2
- **Files modified:** 4 (all created)

## Accomplishments

- IClientService interface defines all 5 client operations with consistent signatures matching the IHealthService pattern (OperationResult, IProgress, CancellationToken), plus synchronous LookupErrorCode for local error code lookup
- WinRmExecutor wraps IProcessRunner to run Invoke-Command on remote hosts via powershell.exe, with hostname regex validation, WinRM-specific error detection, and Script Generator fallback guidance in error messages
- ClientDiagnosticResult record captures all fields needed for remote WSUS diagnostics display: WSUS registry URLs, UseWUServer flag, service statuses, last check-in time, pending reboot, WUA version
- WsusErrorCodes static dictionary with exactly 20 common WSUS/Windows Update error codes; Lookup() normalizes hex with/without 0x prefix, signed decimal, and unsigned decimal formats

## Task Commits

Each task was committed atomically:

1. **Task 1: IClientService interface, result models, and error code dictionary** - `cbabebc` (feat)
2. **Task 2: WinRmExecutor for remote PowerShell command execution** - `73fe964` (feat)

**Plan metadata:** (this commit)

## Files Created/Modified

- `src/WsusManager.Core/Services/Interfaces/IClientService.cs` — Interface with 5 client management methods matching OperationResult/IProgress/CancellationToken pattern
- `src/WsusManager.Core/Models/ClientDiagnosticResult.cs` — ClientDiagnosticResult, ConnectivityTestResult, and WsusErrorInfo record models
- `src/WsusManager.Core/Models/WsusErrorCodes.cs` — Static dictionary of 20 WSUS error codes with descriptions and recommended fixes; Lookup() handles all input formats
- `src/WsusManager.Core/Services/WinRmExecutor.cs` — WinRM remote execution via Invoke-Command, hostname validation, graceful WinRM failure handling

## Decisions Made

- `LookupErrorCode` is synchronous — CLI-06 is a local lookup with no remote call needed; matches the interface description of "no remote call"
- WinRmExecutor returns failed `ProcessResult` on WinRM error rather than throwing — callers receive a graceful error with an actionable message referencing the Script Generator (Phase 15 fallback)
- Hostname validated by `^[A-Za-z0-9.\-]+$` regex before any `Process.Start` — prevents command injection via maliciously crafted hostnames passed to `-ComputerName`
- WsusErrorCodes keyed by uppercase hex without "0x" (e.g., "80244010"); `Lookup()` normalizes all common formats including "0x..." prefix and decimal representations

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None — all 4 files compiled cleanly on first attempt. Full solution build (Core + App + Tests) succeeded with 0 warnings, 0 errors. All 263 existing tests passed.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Plan 02 (service implementation) can now implement `IClientService` using `WinRmExecutor` to run remote PowerShell commands
- Plan 03 (GUI wiring) can register `IClientService` in DI and bind the view model to it
- WinRM availability design decision is baked in from the start: graceful failure messages always reference the Phase 15 Script Generator fallback

---
*Phase: 14-client-management-core*
*Completed: 2026-02-21*
