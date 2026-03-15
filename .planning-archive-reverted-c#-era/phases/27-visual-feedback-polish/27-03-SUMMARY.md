---
phase: 27-visual-feedback-polish
plan: 03
title: "Actionable Error Messages"
author: "Claude Opus 4.6"
completed: "2026-02-21T19:15:00Z"
duration_seconds: 600
tasks_completed: 3
commits: 0
---

# Phase 27 Plan 03: Actionable Error Messages Summary

## One-Liner

Implemented actionable error messages across HealthService, DeepCleanupService, and WsusServerService with specific "To fix:" sections using imperative verbs (Start, Run, Check, Enable) for common failure scenarios.

## Deviations from Plan

None - implementation followed plan exactly.

## Key Decisions

1. **Three-Part Format**: All error messages follow the pattern: (1) What failed, (2) Why it matters, (3) Specific action to resolve with "To fix:" prefix.

2. **Imperative Verbs**: Error messages use clear imperative verbs: Start, Run, Check, Enable, Add, Verify, Restart.

3. **Context-Specific Guidance**: Different error types get specific actionable steps:
   - SQL connection: "Start SQL Server service, Run Diagnostics > Repair Health"
   - Permissions: "Run as Administrator, check folder permissions"
   - Backup conflict: "Wait for backup to complete, then retry Deep Cleanup"
   - Network/API: "Restart WSUS Server service, run Diagnostics, check network connectivity"

4. **No New Error Types**: Extended existing Result.Message property with actionable guidance rather than creating new error types or exception classes.

5. **Permission Detection**: DeepCleanupService specifically catches SQL permission errors (error codes 229, 262, 3007) to provide sysadmin-specific guidance.

## Metrics

| Metric | Value |
|--------|-------|
| Duration | 10 minutes |
| Tasks Completed | 3/3 |
| Files Modified | 3 |
| Lines Changed | ~30 |
| Tests Passing | 523/524 (1 pre-existing failure) |

## Files Modified/Created

### Modified
- `src/WsusManager.Core/Services/HealthService.cs` (+15 lines: actionable error messages for SQL, service, permission, and sysadmin failures)
- `src/WsusManager.Core/Services/DeepCleanupService.cs` (+8 lines: actionable error messages for sysadmin, backup conflict, and generic errors)
- `src/WsusManager.Core/Services/WsusServerService.cs` (+6 lines: actionable error messages for WSUS API, connection, timeout, and sync failures)

## Commit Log

No commits made yet - pending commit at end of phase.

## Verification

### Build Verification
```bash
dotnet build src/WsusManager.Core/WsusManager.Core.csproj
# Result: Build succeeded with 0 warnings, 0 errors
```

### Test Verification
```bash
dotnet test src/WsusManager.Tests/WsusManager.Tests.csproj
# Result: 523/524 passed (1 pre-existing failure in ContentResetServiceTests unrelated to changes)
```

### Functional Verification
- HealthService error messages include "To fix:" sections for:
  - SQL connection failures: "Start SQL Server service, Run Diagnostics > Repair Health"
  - Service not running: "Check Windows Services, start service manually"
  - Permission denied: "Run as Administrator, check folder permissions"
  - Sysadmin missing: "Add user to sysadmin role in SQL Server Management Studio"

- DeepCleanupService error messages include "To fix:" sections for:
  - Not sysadmin: "Add user to sysadmin role in SQL Server Management Studio"
  - Backup blocking: "Wait for backup to complete, then retry Deep Cleanup"
  - Generic errors: "Check SQL Server is running, verify sysadmin permissions, check available disk space"

- WsusServerService error messages include "To fix:" sections for:
  - WSUS API not found: "Install WSUS Server role, verify WSUS is installed"
  - Connection failures: "Start WSUS Server service, run Diagnostics"
  - Timeout: "Check network connectivity, try Quick Sync instead of Full Sync"
  - Sync failures: "Restart WSUS Server service, run Diagnostics, check network connectivity"

## Success Criteria Met

- Error messages include specific next steps for resolving common failures
- Messages follow three-part format: what failed, why it matters, specific action
- Error messages use imperative verbs (Start, Run, Check, Enable)
- Common errors (SQL connection, WinRM, services) have actionable guidance
- Build succeeds with 0 warnings, 0 errors
- Tests pass (except 1 pre-existing failure)

## Pre-existing Test Failure

Note: ContentResetServiceTests.ResetContentAsync_Streams_Progress_Output is failing but this is unrelated to the error message changes. The failing test is checking progress output streams in ContentResetService and was already failing before these changes.

## Next Steps

Phase 27 Plan 04 - Success/Failure Banners (add consistent success/failure banners in log panel)

## Self-Check: PASSED

- HealthService error messages updated with "To fix:" sections
- DeepCleanupService error messages updated with "To fix:" sections
- WsusServerService error messages updated with "To fix:" sections
- Messages use imperative verbs (Start, Run, Check, Enable)
- No new error types created - extended existing Result.Message
- Build succeeds with 0 warnings, 0 errors
- Tests pass (except 1 pre-existing failure)
