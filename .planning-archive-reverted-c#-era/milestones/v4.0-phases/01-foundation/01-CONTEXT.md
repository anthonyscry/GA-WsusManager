# Phase 1: Foundation - Context

**Gathered:** 2026-02-19
**Status:** Ready for planning

<domain>
## Phase Boundary

Compilable .NET 9 solution with DI wiring, async operation pattern, UAC manifest, structured logging, and single-file self-contained EXE publish. This phase produces a running skeleton — no WSUS features, no dashboard data, no operations. Just the architectural foundation that all subsequent phases build on.

</domain>

<decisions>
## Implementation Decisions

### Project Structure
- Root namespace: `WsusManager`
- Claude's discretion on solution layout (single vs multi-project) and folder organization (by domain vs by layer)
- Should balance simplicity with clear separation of concerns

### Logging Behavior
- Log location: `C:\WSUS\Logs\` (same as current PowerShell version)
- Verbosity: Detailed — log every step within operations (SQL queries, service checks, file copies)
- Log rotation: Daily files (WsusManager-2026-02-19.log format)
- Log on startup: application version, startup duration, environment info

### Error Presentation
- Error dialogs: Simple message with expandable "Show Details" section for stack trace / technical info
- Fatal crashes: User-friendly error dialog + full details written to log, then exit
- Operation failures: Show error in log panel, mark operation as failed, let user try again (no popup dialog for operation errors)
- Severity-based: Only fatal/unrecoverable errors get dialogs; operation errors stay in the log panel

### Startup Experience
- Instant window: Main window appears immediately on launch, no splash screen
- Loading state: Claude's discretion on loading indicators (skeleton placeholders, spinners, etc.)
- WSUS not installed: Special guided first-run setup screen that walks user through installing WSUS (not just "Not Installed" dashboard labels)
- Target: Under 1 second from click to visible window

### Claude's Discretion
- Solution project structure (single vs multi-project)
- Folder organization pattern (by domain vs by layer vs hybrid)
- Loading indicator style during dashboard data fetch
- DI container configuration approach
- Exact async operation wrapper design

</decisions>

<specifics>
## Specific Ideas

- Logging should be detailed enough for remote troubleshooting — admins on air-gapped servers can't easily share screens
- Error dialogs with expandable details let power users see what went wrong without overwhelming less technical users
- Guided setup for no-WSUS state is an improvement over the current "Not Installed" labels — makes the tool self-documenting for new deployments

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 01-foundation*
*Context gathered: 2026-02-19*
