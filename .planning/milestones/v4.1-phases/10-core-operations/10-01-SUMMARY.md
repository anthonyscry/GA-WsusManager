---
phase: 10-core-operations
plan: "01"
subsystem: core-services
tags: [bug-fix, deep-cleanup, health-check, sync, wsus-api]
dependency_graph:
  requires: []
  provides: [correct-deep-cleanup, correct-health-check, correct-sync-progress, correct-update-approval, correct-update-decline]
  affects: [OPS-01, OPS-02, OPS-03, OPS-04]
tech_stack:
  added: []
  patterns: [two-level-reflection, Convert.ToInt32-for-boxed-values, full-exe-path]
key_files:
  created: []
  modified:
    - src/WsusManager.Core/Services/DeepCleanupService.cs
    - src/WsusManager.Core/Services/WsusServerService.cs
    - src/WsusManager.Core/Services/HealthService.cs
    - src/WsusManager.Tests/Services/DeepCleanupServiceTests.cs
    - src/WsusManager.Tests/Services/WsusServerServiceTests.cs
    - src/WsusManager.Tests/Services/HealthServiceTests.cs
decisions:
  - "BUG-08: SELECT r.LocalUpdateID (INT identity) not u.UpdateID (GUID) — spDeleteUpdate expects INT"
  - "BUG-04: Two-level reflection UpdateClassification->Title matches actual WSUS API object model"
  - "BUG-03: Remove age-based decline — only expired/superseded matches PowerShell implementation"
  - "BUG-01: Full path C:\\Windows\\System32\\inetsrv\\appcmd.exe — not on PATH by default"
  - "BUG-05: Convert.ToInt32 handles boxed long/uint without InvalidCastException"
metrics:
  duration: "15 minutes"
  completed: "2026-02-20"
  tasks_completed: 3
  files_modified: 6
---

# Phase 10 Plan 01: Core Operations Bug Fixes Summary

**One-liner:** Five silent failures in WSUS operations patched — spDeleteUpdate int/GUID type mismatch, missing two-level reflection for UpdateClassification.Title, age-based update decline removed, appcmd.exe full path enforced, and Convert.ToInt32 for boxed sync progress values.

## Bugs Fixed

### 1. BUG-08 — DeepCleanupService Step 4: GUID passed to spDeleteUpdate (expects INT)

**File:** `src/WsusManager.Core/Services/DeepCleanupService.cs`

**Problem:** `RunStep4DeleteDeclinedUpdatesAsync` selected `u.UpdateID` (a GUID/uniqueidentifier column) and stored IDs in `List<Guid>`, then passed each GUID via `reader.GetGuid(0)` to `spDeleteUpdate @localUpdateID`. The stored procedure declares `@localUpdateID INT`, so SQL Server silently rejected every call or threw a type mismatch error that was swallowed by the `catch (SqlException)` block. Result: zero declined updates ever actually deleted.

**Fix:**
- Changed SELECT to `r.LocalUpdateID` (INT identity column)
- Changed `List<Guid>` to `List<int>`
- Changed `reader.GetGuid(0)` to `reader.GetInt32(0)`
- Changed `foreach (var updateId in batch)` to `foreach (int updateId in batch)`

### 2. BUG-04 — WsusServerService.ApproveUpdatesAsync: Flat property does not exist

**File:** `src/WsusManager.Core/Services/WsusServerService.cs`

**Problem:** `ApproveUpdatesAsync` called `update.GetType().GetProperty("UpdateClassificationTitle")` — this flat string property does not exist on `IUpdate`. The WSUS API model has `IUpdate.UpdateClassification` (returns `IUpdateClassification`) with a `.Title` property. The reflection returned `null`, so `classification` was always `""`, meaning no update ever matched `ApprovedClassifications`, and zero updates were ever approved.

**Fix:** Two-level reflection — `GetProperty("UpdateClassification")` on the update, then `GetProperty("Title")` on the classification object.

### 3. BUG-03 — WsusServerService.DeclineUpdatesAsync: Age-based declination removes valid patches

**File:** `src/WsusManager.Core/Services/WsusServerService.cs`

**Problem:** `DeclineUpdatesAsync` included a block that declined any update older than 6 months, regardless of whether it was expired or superseded. This incorrectly declined valid patches (e.g., a 7-month-old security update that is still needed). The PowerShell implementation only declines expired or superseded updates.

**Fix:** Removed the `sixMonthsAgo` variable and the entire age-based decline block. Method now declines only when `PublicationState == "Expired"` or `IsSuperseded == true`.

### 4. BUG-01 — HealthService.CheckWsusAppPoolAsync: appcmd not on PATH

**File:** `src/WsusManager.Core/Services/HealthService.cs`

**Problem:** Both the check call and the repair call used `"appcmd"` as the executable name. On Windows servers, `C:\Windows\System32\inetsrv\` is not in the system PATH, so `Process.Start("appcmd", ...)` would throw `Win32Exception: The system cannot find the file specified`, caught as a generic exception that returns a vague "IIS may not be installed" error even when IIS is correctly installed.

**Fix:** Defined `const string appcmdPath = @"C:\Windows\System32\inetsrv\appcmd.exe"` inside `CheckWsusAppPoolAsync` and used it for both the list/check call and the repair call.

### 5. BUG-05 — WsusServerService.StartSynchronizationAsync: Direct (int) cast on boxed long

**File:** `src/WsusManager.Core/Services/WsusServerService.cs`

**Problem:** `var processed = (int)(processedProperty?.GetValue(syncProgress) ?? 0)` — the WSUS API may return `ProcessedItems` and `TotalItems` as boxed `long` or `uint` values. A direct `(int)` unbox on a `long` throws `InvalidCastException` at runtime. This was swallowed by the `catch { /* Progress reporting is best-effort */ }` block, silently killing all sync progress reporting.

**Fix:** Changed to `Convert.ToInt32(...)` for both `processed` and `total`. `Convert.ToInt32` handles `int`, `long`, `uint`, `double`, and all other numeric types without throwing.

## Tests Added (6 new)

| Test | Class | Bug |
|------|-------|-----|
| `Step4_SelectQuery_Uses_LocalUpdateID_Not_UpdateID` | DeepCleanupServiceTests | BUG-08 |
| `Step4_UpdateIds_List_Is_Int_Not_Guid` | DeepCleanupServiceTests | BUG-08 |
| `ApproveUpdatesAsync_Classification_Uses_Two_Level_Reflection` | WsusServerServiceTests | BUG-04 |
| `DeclineUpdatesAsync_Does_Not_Decline_By_Age` | WsusServerServiceTests | BUG-03 |
| `StartSynchronizationAsync_SyncProgress_Uses_Convert_Not_DirectCast` | WsusServerServiceTests | BUG-05 |
| `CheckWsusAppPool_Uses_Full_Appcmd_Path` | HealthServiceTests | BUG-01 |

Also updated `SetupAllHealthy()` in `HealthServiceTests` to mock against the full appcmd path pattern rather than the bare `"appcmd"` string.

## Test Results

| Metric | Before | After |
|--------|--------|-------|
| Total tests | 257 | 263 |
| Passing | 257 | 263 |
| Failing | 0 | 0 |

## Requirements Covered

- OPS-01: Health check (appcmd path fixed)
- OPS-02: Auto-repair (appcmd path fixed)
- OPS-03: Online sync (classification fix, decline fix, progress fix)
- OPS-04: Deep cleanup (Step 4 LocalUpdateID fix)
- OPS-05: Database backup (already correct — no changes)
- OPS-06: Database restore (already correct — no changes)

## Files Changed

- `src/WsusManager.Core/Services/DeepCleanupService.cs` — BUG-08 (Step 4 int/GUID)
- `src/WsusManager.Core/Services/WsusServerService.cs` — BUG-04, BUG-03, BUG-05
- `src/WsusManager.Core/Services/HealthService.cs` — BUG-01 (appcmd path)
- `src/WsusManager.Tests/Services/DeepCleanupServiceTests.cs` — 2 new tests
- `src/WsusManager.Tests/Services/WsusServerServiceTests.cs` — 3 new tests
- `src/WsusManager.Tests/Services/HealthServiceTests.cs` — 1 new test + mock update

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Test assertion logic in ApproveUpdatesAsync_Classification_Uses_Two_Level_Reflection**
- **Found during:** Task 3 test run
- **Issue:** The initial test asserted `Assert.NotEqual(wrongProperty, correctFirstLevel + correctSecondLevel)` which fails because `"UpdateClassification" + "Title" != "UpdateClassificationTitle"` is false — the strings ARE equal (concatenated they match the wrong property name)
- **Fix:** Replaced with a proper mock object graph that demonstrates the flat property returns null while two-level reflection returns the correct title
- **Files modified:** `src/WsusManager.Tests/Services/WsusServerServiceTests.cs`

None other — plan executed as written for all other tasks.

## Self-Check: PASSED

- [x] `src/WsusManager.Core/Services/DeepCleanupService.cs` — exists, contains `r.LocalUpdateID` and `reader.GetInt32(0)`
- [x] `src/WsusManager.Core/Services/WsusServerService.cs` — exists, contains `UpdateClassification`/`Title`, no `sixMonthsAgo`, uses `Convert.ToInt32`
- [x] `src/WsusManager.Core/Services/HealthService.cs` — exists, contains `inetsrv\appcmd.exe`
- [x] Commit `9e3786e` — fix(ops): fix 5 bugs in health check, sync, and cleanup services
- [x] 263 tests passing, 0 failures
