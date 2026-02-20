# Phase 2: Application Shell and Dashboard - Context

**Gathered:** 2026-02-19
**Status:** Ready for planning

<domain>
## Phase Boundary

Working windowed application with dark theme matching the existing PowerShell GUI (GitHub-style dark: #0D1117 background, #161B22 sidebar, #21262D cards), live dashboard with auto-refreshing status cards (Services, Database, Disk, Task), server mode toggle (Online vs Air-Gap) with context-aware menu disabling, expandable operation log panel with cancel/clear/save/hide controls, and settings persistence across sessions. This phase produces the complete application shell — all navigation, layout, and dashboard data — but no actual WSUS operations (Health Check, Deep Cleanup, Export/Import, etc.). Those are Phase 3+.

</domain>

<decisions>
## Implementation Decisions

### Dashboard Layout
- Replicate the exact PowerShell GUI layout: 180px sidebar, main content area with header, 4 status cards in a row, Quick Actions bar, Configuration info panel, and log panel at bottom
- 4 dashboard cards: Services (SQL/WSUS/IIS running count), Database (SUSDB size / 10GB limit), Disk (free space GB), Task (scheduled task status)
- Cards use colored top bars: Green = healthy, Orange = warning, Red = critical, Blue = info, Gray = not installed
- Dashboard auto-refreshes every 30 seconds with a timer

### Dark Theme Colors (matching PowerShell exactly)
- Background: #0D1117 (BgDark)
- Sidebar: #161B22 (BgSidebar)
- Cards: #21262D (BgCard)
- Border: #30363D
- Blue accent: #58A6FF
- Green: #3FB950
- Orange: #D29922
- Red: #F85149
- Primary text: #E6EDF3 (Text1)
- Secondary text: #8B949E (Text2)
- Tertiary text: #484F58 (Text3)

### Navigation Structure
- Sidebar with branding at top (WSUS Manager + version), nav buttons in middle (grouped by category), utility buttons at bottom (Help, Settings, About)
- Categories: Dashboard, SETUP (Install WSUS, Restore DB, Create GPO), TRANSFER (Export/Import), MAINTENANCE (Online Sync, Schedule Task, Cleanup), DIAGNOSTICS (Run Diagnostics, Reset Content)
- Active nav button highlighted with #21262D background + blue left border
- Clicking a nav button shows the corresponding panel in the content area

### Server Mode
- Auto-detect Online vs Air-Gap based on internet connectivity check (non-blocking ping with 500ms timeout)
- Online/Offline indicator dot in header with color and text
- Air-Gap mode disables Online Sync and Schedule Task buttons (greyed out, 50% opacity)
- Mode stored in settings but overridden by connectivity check on each refresh

### Log Panel
- Fixed 250px height at bottom of main content, expandable/collapsible via Hide/Show toggle button
- Header bar with: "Output Log" title, status label, Cancel button (hidden when no operation), Live Terminal toggle, Hide, Clear, Save buttons
- TextBox with Consolas font, read-only, horizontal and vertical scrollbars
- Log panel state (expanded/collapsed) persists in settings

### Concurrent Operation Guards
- `IsOperationRunning` flag prevents starting a second operation (already in MainViewModel from Phase 1)
- All operation buttons disabled (50% opacity) while an operation runs
- Cancel button visible only during operations
- Input fields (password boxes, path textboxes) disabled during operations

### WSUS Installation Detection
- Check if WSUS Windows service exists on the server
- When not installed: dashboard shows "Not Installed" / "N/A", all operation buttons except Install WSUS are disabled
- When not installed: log panel shows installation instructions on startup

### Settings Persistence
- Settings from Phase 1 already persist to %APPDATA%\WsusManager\settings.json
- Phase 2 adds: server mode, log panel expanded state, live terminal mode toggle
- Settings loaded on startup, saved on change

### Claude's Discretion
- MVVM binding strategy for dashboard cards (individual properties vs collection)
- Dashboard data service interface design
- Timer implementation for auto-refresh (DispatcherTimer vs async loop)
- Log panel expand/collapse animation (if any)
- Panel switching mechanism (Visibility toggling vs ContentControl with templates)

</decisions>

<specifics>
## Specific Ideas

- Dashboard data queries must be non-blocking — run on background thread and marshal results to UI thread via Progress<string> or ObservableProperty bindings
- Internet connectivity check must use .NET Ping with 500ms timeout (not Test-Connection) to avoid UI freezing
- The 4 dashboard cards should query actual Windows services (MSSQL$SQLEXPRESS, WsusService, W3SVC) and SQL database size
- Card status bar color should change dynamically based on thresholds (DB > 9GB = red, > 7GB = orange, else green)
- Log panel "Save" button should open a file save dialog and write the current log content to the selected file
- Navigation should use panel visibility toggling (Dashboard, Install, Operation, About, Help panels) — same pattern as the PowerShell version
- The window should remember its size/position between sessions (nice to have, Claude's discretion)

</specifics>

<deferred>
## Deferred Ideas

- Live Terminal Mode toggle (opens external PowerShell console) — deferred to Phase 3+ when operations actually execute
- Settings dialog (edit settings UI) — deferred to a later phase
- Install panel UI (password boxes, browse button) — deferred to Phase 6 (Installation)
- Help panel content — deferred to Phase 7 (Polish)
- About panel content — can be included as a simple static panel if convenient

</deferred>

---

*Phase: 02-shell-dashboard*
*Context gathered: 2026-02-19*
