# Phase 2: Application Shell and Dashboard — Plan

**Created:** 2026-02-19
**Requirements:** DASH-01, DASH-02, DASH-03, DASH-04, DASH-05, GUI-01, GUI-02, GUI-03, GUI-04, GUI-06, GUI-07, OPS-01, OPS-02, OPS-03, OPS-04
**Goal:** The application window is fully functional — dark-themed, DPI-aware, showing live service and database status on the dashboard, with server mode switching, an expandable operation log panel, settings persistence, and all concurrent-operation guards in place.

---

## Plans

### Plan 1: Dark theme resource dictionary and base styles

**What:** Create a WPF ResourceDictionary with all dark theme colors, button styles (NavBtn, Btn, BtnSec, BtnGreen, BtnRed), and common control templates matching the existing PowerShell GUI exactly. These resources are consumed by all XAML in subsequent plans.

**Requirements covered:** GUI-01 (dark theme matching GA-AppLocker style)

**Files to create:**
- `src/WsusManager.App/Themes/DarkTheme.xaml` — ResourceDictionary with SolidColorBrush resources (BgDark #0D1117, BgSidebar #161B22, BgCard #21262D, Border #30363D, Blue #58A6FF, Green #3FB950, Orange #D29922, Red #F85149, Text1 #E6EDF3, Text2 #8B949E, Text3 #484F58) and button styles (NavBtn, Btn, BtnSec, BtnGreen, BtnRed) with hover/disabled triggers

**Files to modify:**
- `src/WsusManager.App/App.xaml` — Merge DarkTheme.xaml into Application.Resources

**Verification:**
1. Application launches with dark background (#0D1117)
2. Theme resources are accessible from any XAML via `{StaticResource BgDark}` etc.
3. Button styles render correctly with hover effects and disabled states

---

### Plan 2: Main window layout with sidebar navigation

**What:** Replace the placeholder MainWindow.xaml with the full application layout: 180px sidebar (branding, categorized nav buttons, utility buttons), main content area with header (page title + connection indicator), and placeholder content panels. Wire nav button click handlers to switch between panels (Dashboard, Install, Operation, About, Help). Implement active nav button highlighting with blue left border.

**Requirements covered:** GUI-02 (sidebar navigation with categories), GUI-03 (panel switching)

**Files to modify:**
- `src/WsusManager.App/Views/MainWindow.xaml` — Full layout with Grid columns (180px + *), sidebar DockPanel with nav buttons, main content Grid with header and panel placeholders
- `src/WsusManager.App/Views/MainWindow.xaml.cs` — Keep minimal (DataContext from DI only)

**Files to modify:**
- `src/WsusManager.App/ViewModels/MainViewModel.cs` — Add navigation properties: `CurrentPanel` (string), `PageTitle` (string), `NavigateCommand` (RelayCommand<string>), active button tracking

**Verification:**
1. Sidebar shows branding ("WSUS Manager" + version), categorized buttons (SETUP, TRANSFER, MAINTENANCE, DIAGNOSTICS), and utility buttons (Help, Settings, About)
2. Clicking nav buttons switches the visible content panel and updates the page title
3. Active nav button shows #21262D background with blue left border; others are transparent
4. Window uses MinWidth=800, MinHeight=600, starts centered at 950x736

---

### Plan 3: Dashboard service for data collection

**What:** Create an `IDashboardService` that queries actual system state: Windows service statuses (MSSQL$SQLEXPRESS, WsusService, W3SVC), SUSDB database size via SQL, disk free space on the WSUS content drive, scheduled task status, and internet connectivity. All queries must be async and non-blocking. Include a `DashboardData` model to hold all collected values.

**Requirements covered:** DASH-01 (service status), DASH-02 (DB size with 10GB warning), DASH-03 (disk space), DASH-04 (task status)

**Files to create:**
- `src/WsusManager.Core/Models/DashboardData.cs` — Model with properties: ServiceRunningCount (int), ServiceNames (string[]), DatabaseSizeGB (double, -1 if offline), DiskFreeGB (double), TaskStatus (string), IsWsusInstalled (bool), IsOnline (bool)
- `src/WsusManager.Core/Services/Interfaces/IDashboardService.cs` — Interface with `Task<DashboardData> CollectAsync(AppSettings settings, CancellationToken ct)`
- `src/WsusManager.Core/Services/DashboardService.cs` — Implementation using ServiceController, SqlConnection, DriveInfo, TaskScheduler, and .NET Ping (500ms timeout for connectivity)

**Verification:**
1. Unit test: DashboardService returns service count when services exist
2. Unit test: DashboardService returns -1 for DB size when SQL is not running
3. Unit test: DashboardService returns disk free space for content drive
4. Unit test: Internet connectivity check uses 500ms timeout (does not block)
5. Unit test: IsWsusInstalled is false when WsusService is not found

---

### Plan 4: Dashboard panel with status cards and auto-refresh

**What:** Build the dashboard content panel in MainWindow.xaml with 4 status cards (Services, Database, Disk, Task) using UniformGrid, Quick Actions bar (Diagnostics, Deep Cleanup, Online Sync, Start Services buttons), and Configuration info section. Wire the dashboard to auto-refresh every 30 seconds using a DispatcherTimer. Card top-bar colors change dynamically based on thresholds. Display "Not Installed" states when WSUS is absent.

**Requirements covered:** DASH-01 (service status display), DASH-02 (DB size with 10GB warning), DASH-03 (disk space), DASH-04 (task status), DASH-05 (auto-refresh every 30s), GUI-06 (WSUS not-installed state)

**Files to modify:**
- `src/WsusManager.App/Views/MainWindow.xaml` — Dashboard panel with UniformGrid of 4 cards, Quick Actions WrapPanel, Configuration Border with key-value grid
- `src/WsusManager.App/ViewModels/MainViewModel.cs` — Add dashboard properties: `ServicesValue`, `ServicesSubtext`, `ServicesBarColor`, `DatabaseValue`, `DatabaseSubtext`, `DatabaseBarColor`, `DiskValue`, `DiskSubtext`, `DiskBarColor`, `TaskValue`, `TaskBarColor`, config display properties, `RefreshDashboardCommand`, auto-refresh timer setup/teardown

**Files to modify:**
- `src/WsusManager.App/Program.cs` — Register IDashboardService in DI

**Verification:**
1. Dashboard shows 4 cards with colored top bars matching the PowerShell GUI layout
2. Cards display "Not Installed" / "N/A" when WSUS service is absent
3. DB card shows "X.X / 10 GB" with color thresholds (green < 7, orange 7-9, red >= 9)
4. Dashboard auto-refreshes every 30 seconds without freezing the UI
5. Quick Action buttons are present (non-functional until Phase 3+)
6. Configuration section shows Content path, SQL instance, Export root, and Log path

---

### Plan 5: Server mode detection and context-aware menus

**What:** Implement the Online/Air-Gap server mode detection that auto-detects connectivity on each dashboard refresh. Display the connection status indicator (colored dot + text) in the header. Disable Online Sync and Schedule Task buttons when in Air-Gap mode (greyed out, 50% opacity). Store the mode in settings but override with actual connectivity check.

**Requirements covered:** GUI-04 (server mode toggle with context-aware menus)

**Files to modify:**
- `src/WsusManager.App/ViewModels/MainViewModel.cs` — Add `IsOnline` property, `ServerMode` property, update dashboard refresh to set server mode, bind button enabled states to IsOnline for maintenance/schedule buttons
- `src/WsusManager.App/Views/MainWindow.xaml` — Bind Online Sync and Schedule Task button IsEnabled and Opacity to IsOnline, bind connection indicator dot Fill and text

**Verification:**
1. Header shows green dot + "Online" when internet is available
2. Header shows red dot + "Offline" when internet is unavailable
3. Online Sync and Schedule Task buttons are disabled (50% opacity) when offline
4. Server mode updates on each 30-second dashboard refresh
5. Other buttons (Diagnostics, Cleanup, Export/Import, Install) remain enabled regardless of mode

---

### Plan 6: Operation log panel with controls

**What:** Implement the expandable log panel at the bottom of the main content area. Panel has a header bar with "Output Log" title, status label, Cancel button (visible only during operations), Hide/Show toggle, Clear, and Save buttons. Log text area uses Consolas font, read-only TextBox. Panel height is 250px when expanded, collapsed to just the header bar. Expand/collapse state persists in settings. Wire ClearLog and CancelOperation commands from MainViewModel.

**Requirements covered:** OPS-01 (log panel), OPS-02 (cancel operation), GUI-07 (log panel state persistence)

**Files to modify:**
- `src/WsusManager.App/Views/MainWindow.xaml` — Log panel Border at bottom of content area with header Grid and TextBox, bound to LogOutput and visibility properties
- `src/WsusManager.App/ViewModels/MainViewModel.cs` — Add `IsLogPanelExpanded` property (persisted), `ToggleLogPanelCommand`, `SaveLogCommand` (opens SaveFileDialog), `LogPanelHeight` computed property
- `src/WsusManager.Core/Models/AppSettings.cs` — Already has LogPanelExpanded property

**Verification:**
1. Log panel shows at bottom of content area with 250px height
2. Hide button collapses panel to header only; Show button restores it
3. Clear button empties the log text
4. Save button opens a file save dialog and writes log content to the selected file
5. Cancel button appears only when IsOperationRunning is true
6. Log panel expanded/collapsed state survives app restart

---

### Plan 7: WSUS installation detection and button state management

**What:** Implement WSUS installation detection that checks for the WsusService Windows service. When WSUS is not installed: all operation buttons except Install WSUS are disabled (50% opacity), dashboard cards show "Not Installed" / "N/A", and the log panel displays installation instructions on startup. Wire button enabled states to both `IsWsusInstalled` and `IsOperationRunning` — buttons should be disabled if either WSUS is missing or an operation is running.

**Requirements covered:** GUI-06 (WSUS not-installed detection), OPS-03 (concurrent operation blocking), OPS-04 (button state management)

**Files to modify:**
- `src/WsusManager.App/ViewModels/MainViewModel.cs` — Add `IsWsusInstalled` property, update button CanExecute to check both IsWsusInstalled and !IsOperationRunning, add startup message when WSUS not installed, list of WsusRequiredButtons for state management

**Verification:**
1. When WSUS service is absent, all operation buttons except Install WSUS are disabled at 50% opacity
2. When WSUS service is present, buttons are enabled (unless an operation is running)
3. Dashboard shows "Not Installed" cards when WSUS is absent
4. Log panel shows "WSUS is not installed..." message with instructions on startup when WSUS is absent
5. Button states update correctly after dashboard refresh detects WSUS installation change
6. Unit test: CanExecute returns false when IsWsusInstalled is false (for WSUS-required commands)
7. Unit test: CanExecute returns false when IsOperationRunning is true

---

### Plan 8: Settings persistence integration and final wiring

**What:** Wire settings loading on startup and saving on change for all Phase 2 settings (server mode, log panel expanded state, live terminal mode toggle). Load settings before the first dashboard refresh. Save settings when log panel is toggled or server mode changes. Ensure all Phase 2 components are registered in DI. Add integration tests for the complete dashboard refresh cycle and settings round-trip.

**Requirements covered:** GUI-07 (settings persistence), final integration

**Files to modify:**
- `src/WsusManager.App/ViewModels/MainViewModel.cs` — Add `InitializeAsync()` method called after window loads: load settings, apply log panel state, trigger first dashboard refresh. Save settings on property changes.
- `src/WsusManager.App/Views/MainWindow.xaml.cs` — Call ViewModel.InitializeAsync() on Window.Loaded event
- `src/WsusManager.App/Program.cs` — Verify all Phase 2 services registered in DI

**Files to create:**
- `src/WsusManager.Tests/Services/DashboardServiceTests.cs` — Tests for dashboard data collection
- `src/WsusManager.Tests/ViewModels/DashboardViewModelTests.cs` — Tests for dashboard display logic (card colors, thresholds, button states)

**Verification:**
1. Application starts, loads settings, and displays dashboard with correct log panel state
2. Toggling log panel saves the new state immediately
3. Settings survive a full close and reopen cycle (server mode, log panel state, live terminal toggle)
4. All Phase 2 DI registrations resolve without error
5. Unit test: Dashboard threshold logic (DB size colors, disk space colors, service count display)
6. Unit test: Settings round-trip (save then load returns same values)
7. `dotnet build` and `dotnet test` both pass

---

## Plan Summary

| Plan | Description | Requirements |
|------|-------------|--------------|
| 1 | Dark theme resource dictionary and base styles | GUI-01 |
| 2 | Main window layout with sidebar navigation | GUI-02, GUI-03 |
| 3 | Dashboard service for data collection | DASH-01, DASH-02, DASH-03, DASH-04 |
| 4 | Dashboard panel with status cards and auto-refresh | DASH-01, DASH-02, DASH-03, DASH-04, DASH-05, GUI-06 |
| 5 | Server mode detection and context-aware menus | GUI-04 |
| 6 | Operation log panel with controls | OPS-01, OPS-02, GUI-07 |
| 7 | WSUS installation detection and button state management | GUI-06, OPS-03, OPS-04 |
| 8 | Settings persistence integration and final wiring | GUI-07, integration |

## Execution Order

Plans 1 through 8 execute sequentially. Each plan builds on the previous:
- Plan 1 creates the theme resources that all subsequent XAML uses
- Plan 2 creates the window layout that Plans 4-7 populate with content
- Plan 3 creates the data service that Plan 4 displays in the dashboard
- Plan 4 creates the dashboard cards that Plan 5 updates with server mode
- Plan 5 adds server mode that affects button states in Plan 7
- Plan 6 creates the log panel that Plan 7 wires into operation state
- Plan 7 creates the button state management that Plan 8 persists
- Plan 8 ties everything together with settings persistence and tests

## Success Criteria (from Roadmap)

All five Phase 2 success criteria must be TRUE after Plan 8 completes:

1. On launch, the dashboard displays WSUS health status, SQL Server DB size with a warning indicator when approaching 10GB, last sync time, and SQL/WSUS/IIS service states — all without freezing the UI
2. The dashboard auto-refreshes every 30 seconds with a visible refresh indicator, and displays "Not Installed" cards when WSUS is absent from the server
3. Toggling between Online and Air-Gap modes changes the visible menu items and operation buttons accordingly
4. Attempting to start a second operation while one is running disables all operation buttons and prevents concurrent execution
5. Application settings (server mode, log panel state, live terminal toggle) survive a full close and reopen cycle

---

*Phase: 02-shell-dashboard*
*Plan created: 2026-02-19*
