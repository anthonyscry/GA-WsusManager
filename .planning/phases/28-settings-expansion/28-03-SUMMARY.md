# Phase 28-03: Redesign SettingsDialog XAML with Sections - Summary

**Completed:** 2026-02-21

## Objective
Redesign SettingsDialog.xaml with 4 sections for Operations, Logging, Behavior, and Advanced settings. Add all 8 new controls with proper layout, tooltips, and validation support.

## Files Modified

1. **`src/WsusManager.App/Views/SettingsDialog.xaml`**
   - Changed height from 620 to 780 pixels
   - Wrapped content in ScrollViewer for flexibility
   - Added 4 new GroupBox sections with proper styling
   - Updated Grid.RowDefinitions to accommodate new sections
   - Added stub handler for Reset to Defaults button

2. **`src/WsusManager.App/Views/SettingsDialog.xaml.cs`**
   - Added stub `BtnResetToDefaults_Click` handler (TODO for 28-04)

## New Sections Added

### Section 2: Operations (Grid.Row="2")
- Default Sync Profile ComboBox
  - Values: Full Sync, Quick Sync, Sync Only
  - Tag attributes for enum matching
  - AutomationId: DefaultSyncProfileComboBox
  - ToolTip: "Preset selection when opening Online Sync dialog."

### Section 3: Logging (Grid.Row="3")
- Log Level ComboBox
  - Values: Debug, Info, Warning, Error, Fatal
  - Tag attributes for enum matching
  - AutomationId: LogLevelComboBox
  - ToolTip: "Minimum log level to output..."

- Retention Days TextBox
  - InputScope="Number"
  - AutomationId: LogRetentionDaysTextBox
  - ToolTip: "Number of days to retain log files..."

- Max File Size (MB) TextBox
  - InputScope="Number"
  - AutomationId: LogMaxFileSizeMbTextBox
  - ToolTip: "Maximum log file size in MB..."

### Section 4: Behavior (Grid.Row="4")
- Persist Window State CheckBox
  - AutomationId: PersistWindowStateCheckBox
  - ToolTip: "Save and restore window position..."

- Refresh Interval ComboBox
  - Values: 10 seconds, 30 seconds, 60 seconds, Disabled
  - Tag attributes: Sec10, Sec30, Sec60, Disabled
  - AutomationId: DashboardRefreshIntervalComboBox
  - ToolTip: "How often to refresh dashboard data..."

- Confirmation Prompts CheckBox
  - Content: "Require confirmation for destructive operations"
  - AutomationId: RequireConfirmationDestructiveCheckBox
  - ToolTip: "Show confirmation before destructive operations..."

### Section 5: Advanced (Grid.Row="5")
- WinRM Timeout (sec) TextBox
  - InputScope="Number"
  - AutomationId: WinRMTimeoutSecondsTextBox
  - ToolTip: "WinRM operation timeout in seconds..."

- WinRM Retry Count TextBox
  - InputScope="Number"
  - AutomationId: WinRMRetryCountTextBox
  - ToolTip: "Number of WinRM operation retry attempts..."

- Reset to Defaults Button
  - Style: BtnSec
  - AutomationId: ResetToDefaultsButton
  - ToolTip: "Reset all settings to their default values..."
  - Click handler: BtnResetToDefaults_Click (stub)

## Existing Sections (Updated Grid.Row values)
- Header: Grid.Row="0" (unchanged)
- Server Mode: Grid.Row="1" (unchanged)
- Operations: Grid.Row="2" (new)
- Logging: Grid.Row="3" (new)
- Behavior: Grid.Row="4" (new)
- Advanced: Grid.Row="5" (new)
- General: Grid.Row="6" (was 2)
- Appearance: Grid.Row="7" (was 3)
- Buttons: Grid.Row="8" (was 5)

## UI Design Patterns
- Two-column layout: 160px label column, * control column
- GroupBox with custom HeaderTemplate for consistent styling
- ToolTips on all labels and buttons
- AutomationIds for UI testing
- ScrollViewer wrapper for responsive layout

## Verification

- [x] Build succeeds: dotnet build src/WsusManager.App
- [x] 4 GroupBox sections exist: Operations, Logging, Behavior, Advanced
- [x] All 8 new settings have controls (3 ComboBox, 3 TextBox, 2 CheckBox)
- [x] All controls have AutomationIds for testing
- [x] All controls have ToolTips for context
- [x] Reset to Defaults button in Advanced section
- [x] Two-column layout used (160px label, * control)
- [x] ScrollViewer wraps content if window height exceeded

## Next Steps

Proceed to Phase 28-04: Update SettingsDialog code-behind with validation

---

**Status:** Complete ✅
