# Phase 28: Settings Expansion - Context

**Gathered:** 2026-02-21
**Status:** Ready for planning

<domain>
## Phase Boundary

Expand Settings dialog with 8 configurable settings across 4 categories: Operations (default sync profile), Logging (level, retention policy), Behavior (window state persistence, dashboard refresh interval, confirmation prompts), and Advanced (WinRM timeout/retry, reset to defaults). Settings persist to settings.json and take effect immediately (no restart required).

</domain>

<decisions>
## Implementation Decisions

### Settings Organization
- **4 sections** in Settings dialog: Operations, Logging, Behavior, Advanced
- **Operations**: Default sync profile (combobox: Full/Quick/Sync Only)
- **Logging**: Level (combobox: Debug/Info/Warning/Error/Fatal), Retention days (numeric), Max file size MB (numeric)
- **Behavior**: Window state persistence (checkbox), Dashboard refresh interval (combobox: 10s/30s/60s/Disabled), Confirmation prompts (checkbox for destructive operations)
- **Advanced**: WinRM timeout seconds (numeric), WinRM retry count (numeric), Reset to Defaults button
- **Layout**: Use GroupBox for each section with descriptive headers

### UI Control Types
- **Combobox** for enum-like choices (sync profile, log level, refresh interval)
- **Checkbox** for boolean toggles (window state, confirmations)
- **Numeric input** (TextBox with InputScope="Number") for numeric values (timeout, retry count, retention days, max file size)
- **Button** for "Reset to Defaults" with confirmation dialog
- **Labels** with ToolTip for additional context where helpful

### Persistence Format
- **Extend existing AppSettings.cs** with new properties:
  - `DefaultSyncProfile` (enum: Full, Quick, SyncOnly)
  - `LogLevel` (enum: Debug, Info, Warning, Error, Fatal)
  - `LogRetentionDays` (int, default 30)
  - `LogMaxFileSizeMb` (int, default 10)
  - `PersistWindowState` (bool, default true)
  - `DashboardRefreshInterval` (enum: Sec10, Sec30, Sec60, Disabled)
  - `RequireConfirmationDestructive` (bool, default true)
  - `WinRMTimeoutSeconds` (int, default 60)
  - `WinRMRetryCount` (int, default 3)
- **settings.json** structure matches property names (camelCase JSON)
- **Save on OK button only**, Cancel discards changes

### Validation
- **Min/max values**: RetentionDays (1-365), MaxFileSizeMb (1-1000), WinRMTimeoutSeconds (10-300), WinRMRetryCount (1-10)
- **Validation triggers**: On TextBox.LostFocus or OK button click
- **Error display**: Red border on invalid controls, error message in dialog footer
- **Default values**: All properties have default values if missing from JSON

### Reset to Defaults
- **Button location**: Bottom of Advanced section
- **Confirmation dialog**: "Reset all settings to default values? This cannot be undone."
- **Action**: Set all properties to default values, update UI controls, save immediately
- **No undo**: Reset is immediate and final

### Immediate Effect
- **All settings take effect immediately** upon clicking OK (no application restart required)
- **Exception**: Window state persistence applies on next launch
- **Log level change**: Affects new log messages immediately
- **Refresh interval**: Timer restarted with new value
- **WinRM settings**: Used on next client operation

### Settings Dialog Changes
- **Convert from read-only to editable** (currently shows values but can't edit)
- **Add Save/Cancel buttons** (currently just Close)
- **Two-column layout** for compact form: Label | Control
- **Scrollable content** if dialog exceeds screen height

### Window State Persistence
- **Save on closing**: Window bounds (Width, Height, Left, Top), WindowState (Normal/Maximized)
- **Restore on startup**: Apply saved bounds if within screen working area
- **Fallback**: Default window size if saved bounds invalid
- **Screen handling**: If saved bounds span multiple monitors, use primary monitor bounds

### Confirmation Prompt Behavior
- **Single toggle** for all destructive operations (cleanup, restore, content reset)
- **Prompt text**: "Are you sure you want to [operation]? This action cannot be undone."
- **Affected operations**: Deep Cleanup, Restore Database, Reset Content
- **Non-destructive operations** (health check, sync, export) don't use this toggle

### Claude's Discretion
- Exact spacing and margins in Settings dialog layout
- Whether to add "Apply" button in addition to OK/Cancel
- ToolTip content for each setting (if more detail needed)
- Exact error message wording for validation failures
- GroupBox border style and header styling

</decisions>

<specifics>
## Specific Ideas

- "Settings dialog should be similar to Windows Control Panel — familiar to admins"
- "Use two-column layout: labels on left, controls on right — saves vertical space"
- "Default values should be sensible for most environments — don't make admins configure everything"
- "Reset to Defaults should have a confirmation dialog — accidental resets would be frustrating"

</specifics>

<deferred>
## Deferred Ideas

- Per-operation settings granularity (individual timeouts per operation) — keep simple for now
- Settings import/export (copy settings between machines) — add to backlog
- Settings profiles (named configurations) — add to backlog
- Advanced network settings (proxy configuration) — separate phase for network config

</deferred>

---

*Phase: 28-settings-expansion*
*Context gathered: 2026-02-21*
