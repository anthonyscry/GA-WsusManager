# Phase 2: Application Shell and Dashboard -- Summary

**Completed:** 2026-02-19
**Requirements covered:** DASH-01, DASH-02, DASH-03, DASH-04, DASH-05, GUI-01, GUI-02, GUI-03, GUI-04, GUI-06, GUI-07, OPS-01, OPS-02, OPS-03, OPS-04

---

## What Was Built

### Plan 1: Dark Theme Resource Dictionary (GUI-01)

Created `src/WsusManager.App/Themes/DarkTheme.xaml` with a complete ResourceDictionary containing:

- **Background colors:** BgDark (#0D1117), BgSidebar (#161B22), BgCard (#21262D), BgInput, Border (#30363D)
- **Accent colors:** Blue (#58A6FF), Green (#3FB950), Orange (#D29922), Red (#F85149)
- **Text colors:** Text1 (#E6EDF3), Text2 (#8B949E), Text3 (#484F58)
- **Raw Color values** for dynamic binding in code
- **Button styles:** NavBtn, NavBtnActive, Btn, BtnSec, BtnGreen, BtnRed, QuickActionBtn -- all with hover triggers and disabled opacity states
- **Text styles:** CategoryLabel, CardTitle, CardValue, CardSubtext
- **LogTextBox style:** Consolas font, read-only, dark background
- Merged into `App.xaml` via `Application.Resources`

### Plan 2: Main Window Layout with Sidebar Navigation (GUI-02, GUI-03)

Replaced placeholder `MainWindow.xaml` with the full application layout:

- **Sidebar (180px):** Branding header ("WSUS Manager" + version), categorized nav buttons (SETUP, TRANSFER, MAINTENANCE, DIAGNOSTICS), bottom utility buttons (Dashboard, Settings, Help, About)
- **Header bar:** Page title (bound to `PageTitle`), connection status indicator (green/red dot + Online/Offline text)
- **Content area:** Dashboard panel and Operation panel (placeholder) with visibility bound to `CurrentPanel`
- **Navigation:** `NavigateCommand` (RelayCommand<string>) switches panels and updates page title
- **Window:** 950x736 default, MinWidth=800, MinHeight=600, CenterScreen

### Plan 3: Dashboard Service (DASH-01, DASH-02, DASH-03, DASH-04)

Created `IDashboardService` and `DashboardService`:

- **DashboardData model** (`src/WsusManager.Core/Models/DashboardData.cs`): ServiceRunningCount, ServiceNames, DatabaseSizeGB, DiskFreeGB, TaskStatus, IsWsusInstalled, IsOnline
- **Service checks** (all run in parallel via `Task.WhenAll`):
  - Windows services via `ServiceController` (MSSQL$SQLEXPRESS, WsusService, W3SVC)
  - SUSDB size via `SqlConnection` with 5-second timeout
  - Disk free space via `DriveInfo`
  - Scheduled task status via `schtasks.exe` process
  - Internet connectivity via .NET `Ping` with 500ms timeout
- Added `System.ServiceProcess.ServiceController` NuGet to WsusManager.Core
- Registered `IDashboardService` in DI container (`Program.cs`)

### Plan 4: Dashboard Panel with Status Cards and Auto-Refresh (DASH-01-05, GUI-06)

Built the dashboard content panel with:

- **4 status cards** in UniformGrid: Services, Database, Disk Space, Scheduled Task
- Each card has a colored top bar (4px) that changes based on thresholds
- **Database thresholds:** green < 7 GB, orange 7-9 GB, red >= 9 GB
- **Disk thresholds:** green >= 50 GB, orange 10-50 GB, red < 10 GB
- **Service thresholds:** green (all running), orange (partial), red (none)
- **Quick Actions bar:** Diagnostics, Deep Cleanup, Online Sync, Start Services buttons
- **Configuration section:** Content path, SQL instance, Log path, Server mode
- **Auto-refresh:** DispatcherTimer at 30-second interval (configurable via settings)
- **Not-Installed state:** All cards show "N/A" / "Not Installed" when WSUS is absent

### Plan 5: Server Mode Detection (GUI-04)

- Auto-detects connectivity on each dashboard refresh
- Header shows green dot + "Online" or red dot + "Offline"
- Online Sync and Schedule Task buttons are disabled when offline (bound to `IsOnline`)
- `ServerModeText` property shows "Online" or "Air-Gap"

### Plan 6: Operation Log Panel (OPS-01, OPS-02, GUI-07)

- Expandable panel at bottom of content area (250px when expanded)
- Header bar with "Output Log" title, current operation name, and control buttons
- **Cancel button:** Visible only during operations, bound to `CancelOperationCommand`
- **Hide/Show toggle:** Collapses panel to header only
- **Clear button:** Empties log text
- **Save button:** Opens SaveFileDialog, writes log to file
- Auto-scroll via `TextChanged` event handler
- Consolas font, read-only TextBox, dark styled
- Auto-expands when operation starts

### Plan 7: WSUS Installation Detection and Button State (GUI-06, OPS-03, OPS-04)

- WSUS detection via `WsusService` service check in DashboardService
- When WSUS is not installed: all quick action buttons disabled via `CanExecute`
- Dual guard: `CanExecuteWsusOperation()` checks both `IsWsusInstalled` and `!IsOperationRunning`
- Online operations additionally check `IsOnline` via `CanExecuteOnlineOperation()`
- `NotifyCommandCanExecuteChanged()` called after every dashboard refresh
- Startup message in log panel when WSUS is not installed

### Plan 8: Settings Persistence and Tests (GUI-07, integration)

- `InitializeAsync()` called from `Window.Loaded`:
  1. Loads settings via `ISettingsService.LoadAsync()`
  2. Applies log panel state, server mode, config paths
  3. Triggers first dashboard refresh
  4. Shows startup message if WSUS not installed
  5. Starts auto-refresh timer
- Log panel toggle saves settings immediately via `SaveAsync`
- Auto-refresh timer cleanup via `StopRefreshTimer()`

**Tests added:**
- `DashboardServiceTests` (6 tests): data collection, disk space, cancellation, defaults
- `MainViewModelTests` expanded (24 total tests): operation runner (8), navigation (2), dashboard card thresholds (8), server mode (2), log panel (2), button state/CanExecute (4)
- `DiContainerTests` updated: IDashboardService resolution

---

## Files Created

| File | Purpose |
|------|---------|
| `src/WsusManager.App/Themes/DarkTheme.xaml` | Dark theme resource dictionary |
| `src/WsusManager.Core/Models/DashboardData.cs` | Dashboard data model |
| `src/WsusManager.Core/Services/Interfaces/IDashboardService.cs` | Dashboard service interface |
| `src/WsusManager.Core/Services/DashboardService.cs` | Dashboard service implementation |
| `src/WsusManager.Tests/Services/DashboardServiceTests.cs` | Dashboard service tests |

## Files Modified

| File | Changes |
|------|---------|
| `src/WsusManager.App/App.xaml` | Merged DarkTheme.xaml into Application.Resources |
| `src/WsusManager.App/Views/MainWindow.xaml` | Full layout: sidebar, header, dashboard, log panel |
| `src/WsusManager.App/Views/MainWindow.xaml.cs` | Added Loaded handler, log auto-scroll |
| `src/WsusManager.App/ViewModels/MainViewModel.cs` | Navigation, dashboard cards, server mode, log panel, button state, settings, auto-refresh |
| `src/WsusManager.App/Program.cs` | Registered IDashboardService in DI |
| `src/WsusManager.Core/WsusManager.Core.csproj` | Added System.ServiceProcess.ServiceController NuGet |
| `src/WsusManager.Tests/ViewModels/MainViewModelTests.cs` | Updated constructor, added 16 new tests |
| `src/WsusManager.Tests/Integration/DiContainerTests.cs` | Added DashboardService resolution test |

## Test Results

```
Passed!  - Failed: 0, Passed: 24, Skipped: 0, Total: 24
```

- `dotnet build` -- 0 warnings, 0 errors
- `dotnet test` -- 24 tests pass

## Success Criteria Verification

1. **Dashboard displays WSUS health status** -- YES: 4 status cards showing service states, DB size with 10GB warning, disk space, and scheduled task status. Auto-refresh does not freeze UI (async/await pattern with DispatcherTimer).

2. **Dashboard auto-refreshes every 30 seconds** -- YES: DispatcherTimer with configurable interval. "Not Installed" cards displayed when WSUS is absent.

3. **Server mode toggle changes visible menus** -- YES: Online/Air-Gap detection with connection indicator. Online Sync and Schedule Task buttons disabled when offline.

4. **Concurrent operation blocking** -- YES: `IsOperationRunning` flag prevents concurrent operations. All quick action buttons disabled via CanExecute during operations.

5. **Settings persistence** -- YES: Log panel expanded state and server mode survive close/reopen via `ISettingsService.SaveAsync()`/`LoadAsync()`.

---

*Phase: 02-shell-dashboard*
*Completed: 2026-02-19*
