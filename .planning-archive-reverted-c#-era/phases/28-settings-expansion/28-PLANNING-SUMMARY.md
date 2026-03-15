# Phase 28: Settings Expansion - Planning Summary

**Status:** Planning Complete
**Phase:** 28-settings-expansion
**Date:** 2026-02-21

## Phase Objective

Expand the Settings dialog with 8 configurable settings across 4 categories (Operations, Logging, Behavior, Advanced). All settings persist to settings.json and take effect immediately without application restart.

## What Was Planned

### 7 Execution Plans Created

1. **28-01-PLAN.md**: Extend AppSettings with 8 new properties and 3 enums
   - Creates DefaultSyncProfile, LogLevel, DashboardRefreshInterval enums
   - Adds 8 properties to AppSettings with JSON serialization
   - ~180 lines of code

2. **28-02-PLAN.md**: Create SettingsValidationService
   - Creates ValidationResult model
   - Creates ISettingsValidationService interface and implementation
   - Validates numeric settings with min/max ranges
   - Registers service in DI container

3. **28-03-PLAN.md**: Redesign SettingsDialog XAML
   - 4 GroupBox sections: Operations, Logging, Behavior, Advanced
   - 8 new controls: 3 ComboBox, 3 TextBox, 2 CheckBox
   - Two-column layout for compact form
   - ToolTips for all controls
   - Reset to Defaults button

4. **28-04-PLAN.md**: Update SettingsDialog code-behind
   - Inject ISettingsValidationService
   - Pre-populate all controls from current settings
   - Add LostFocus validation with visual feedback
   - Implement Reset to Defaults with confirmation
   - Update Save/Cancel handlers for new properties

5. **28-05-PLAN.md**: Implement window state persistence
   - Create WindowBounds model
   - Add WindowBounds property to AppSettings
   - Save bounds on MainWindow closing
   - Restore bounds on MainWindow loaded
   - Handle invalid bounds gracefully

6. **28-06-PLAN.md**: Implement confirmation prompts
   - Create ConfirmDestructiveOperation helper
   - Add confirmation to Deep Cleanup
   - Add confirmation to Restore Database
   - Add confirmation to Reset Content
   - Ensure non-destructive operations skip confirmation

7. **28-07-PLAN.md**: Integrate settings into application behavior
   - Dashboard refresh timer uses setting
   - WinRM timeout/retry applied to operations
   - Log level filters log output
   - Default sync profile pre-selected in dialog
   - Integration tests created
   - Manual test checklist

### Files Created

- 28-CONTEXT.md - Domain decisions and implementation details
- 28-STATE.md - Phase status and plan overview
- 28-01-PLAN.md through 28-07-PLAN.md - Detailed execution plans

## Architecture Decisions

### Settings Organization
- 4 sections in dialog for logical grouping
- Two-column layout (160px label | * control) for compact form
- GroupBox headers with consistent styling

### Validation Strategy
- Centralized validation service (ISettingsValidationService)
- Min/max range validation for numeric inputs
- Visual feedback (red border + tooltip) on LostFocus
- Validation blocks Save operation

### State Management
- Settings persist to %APPDATA%\WsusManager\settings.json
- JSON serialization with camelCase property names
- Default values for all properties
- Null coalescing for missing JSON properties

### Window Persistence
- WindowBounds model stores position, size, and state
- Saves on close (RestoreBounds for maximized windows)
- Restores on load if within screen working area
- Fallback to default size if invalid

### Confirmation Prompts
- Single toggle for all destructive operations
- Confirmation dialog: "Are you sure? This cannot be undone."
- Non-destructive operations skip confirmation
- Setting can be disabled for bulk operations

## Dependencies

```
28-01 (Enums & AppSettings)
    ├── 28-02 (ValidationService)
    ├── 28-03 (XAML Redesign)
    │   └── 28-04 (Code-behind)
    │       └── 28-06 (Confirmation Prompts)
    └── 28-05 (Window Persistence)

28-07 (Integration) depends on all above
```

## Estimated Effort

| Plan | Estimated Time | Complexity |
|------|---------------|------------|
| 28-01 | 45 min | Low |
| 28-02 | 45 min | Low |
| 28-03 | 60 min | Medium |
| 28-04 | 90 min | Medium |
| 28-05 | 60 min | Medium |
| 28-06 | 45 min | Low |
| 28-07 | 90 min | Medium |
| **Total** | **7-8 hours** | **Medium** |

## Success Criteria

- [ ] All 8 settings added to AppSettings with proper defaults
- [ ] Settings dialog redesigned with 4 GroupBox sections
- [ ] Validation service with min/max range checking
- [ ] Validation feedback on invalid controls
- [ ] Reset to Defaults button with confirmation
- [ ] Window state persistence working
- [ ] Confirmation prompts for destructive operations
- [ ] Dashboard refresh interval applies immediately
- [ ] All settings work without restart
- [ ] Unit and integration tests passing
- [ ] Build succeeds with 0 warnings, 0 errors

## Next Steps

1. Execute plans sequentially from 28-01 through 28-07
2. Create SUMMARY.md after each plan completion
3. Run full test suite after all plans complete
4. Perform manual testing using checklist
5. Create 28-COMPLETION-REPORT.md

## Deferred Ideas

- Per-operation settings granularity (individual timeouts per operation)
- Settings import/export (copy settings between machines)
- Settings profiles (named configurations)
- Advanced network settings (proxy configuration)

These are noted in CONTEXT.md for future phases.

---

*Phase 28 Planning Complete - Ready for Execution*
