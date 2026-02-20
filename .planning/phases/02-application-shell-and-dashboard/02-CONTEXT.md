# Phase 2: Application Shell and Dashboard - Context

**Gathered:** 2026-02-19
**Status:** Ready for planning

<domain>
## Phase Boundary

Working windowed application with modernized dark theme, live dashboard showing WSUS health/DB size/sync status/service states, server mode toggle (Online vs Air-Gap), expandable log panel for operation output, settings persistence, and operation blocking infrastructure (one operation at a time, buttons disabled during execution).

</domain>

<decisions>
## Implementation Decisions

### Dashboard Layout
- Status cards for each metric (WSUS status, DB size, sync time, services) — individual cards, not a unified panel
- Compact view by default with expand/hover for additional details per card
- Window is resizable — layout must adapt to different window sizes
- Cards should show key status (healthy/warning/error), then reveal details on interaction

### Dark Theme Style
- Use .NET 9's built-in WPF Fluent dark theme (`ThemeMode="Dark"`) as the base
- Accent color: GA-ASI corporate blue for buttons, highlights, and active states
- Claude's discretion on card styling (flat vs elevated, shadows, border treatment)

### Log Panel Behavior
- Bottom-docked panel, below the dashboard area
- Open by default on startup, shows startup info and version
- Smart auto-scroll: auto-scrolls to bottom when user is at the bottom; pauses auto-scroll if user scrolls up to read earlier output
- Fixed height (~200-250px), not user-resizable
- Expand/collapse toggle button to show/hide the panel

### Navigation Design
- Left sidebar with vertical navigation — icons + labels, similar to Windows Admin Center
- Operations grouped by category: Diagnostics, Database, Sync/Transfer, Setup
- Quick action buttons on the dashboard for the most common operations (Health Check, Deep Cleanup, etc.)
- Prominent Online/Air-Gap mode toggle near the top of the window, always visible
- Air-Gap mode hides/disables online-only operations (sync), shows air-gap operations (import/export)

### Claude's Discretion
- Card styling details (shadows, borders, hover effects)
- Exact sidebar width and icon choices
- Dashboard card arrangement (grid columns, spacing)
- Quick action button selection and placement
- Responsive layout breakpoints for window resizing
- Collapse behavior of sidebar at small window sizes

</decisions>

<specifics>
## Specific Ideas

- Left sidebar + dashboard quick actions gives two ways to access operations: browse by category in sidebar, or one-click from dashboard for frequent tasks
- GA-ASI blue accent on Fluent dark should feel professional and branded without being garish
- Smart scroll on log panel prevents the annoying behavior where output pushes away what you're reading
- Prominent mode toggle is important because air-gapped servers are the primary use case — users shouldn't have to dig into settings to switch modes

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 02-application-shell-and-dashboard*
*Context gathered: 2026-02-19*
