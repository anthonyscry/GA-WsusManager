# Phase 28 Manual Test Checklist

## Settings Dialog
- [ ] Settings dialog opens from toolbar
- [ ] All 4 sections display correctly (Operations, Logging, Behavior, Advanced)
- [ ] All controls pre-populated from current settings
- [ ] Save button validates all settings
- [ ] Cancel button closes without saving
- [ ] Reset to Defaults shows confirmation and resets all values
- [ ] Theme preview works and reverts on cancel

## Settings Behavior
- [ ] **Log Level**: Debug shows all messages, Fatal shows only critical
- [ ] **Refresh Interval**: Changes take effect immediately (timer restart)
- [ ] **Refresh Interval**: Disabled stops auto-refresh
- [ ] **Refresh Interval**: 10s/30s/60s options work correctly
- [ ] **Default Sync Profile**: Online Sync dialog pre-selects correct profile
- [ ] **Confirmation Prompts**: Destructive ops show/hide based on setting
- [ ] **Confirmation Prompts**: Deep Cleanup shows/hides confirmation
- [ ] **Confirmation Prompts**: Restore Database shows/hides confirmation
- [ ] **Confirmation Prompts**: Reset Content shows/hides confirmation
- [ ] **Window State Persistence**: Position/size saved and restored
- [ ] **Window State Persistence**: Maximized state saved and restored
- [ ] **Window State Persistence**: Disabled option doesn't save bounds

## Validation
- [ ] **Retention Days**: Rejects < 1 or > 365
- [ ] **Retention Days**: Red border shown on invalid input
- [ ] **Retention Days**: Error message in tooltip on invalid input
- [ ] **Max File Size**: Rejects < 1 or > 1000
- [ ] **Max File Size**: Red border shown on invalid input
- [ ] **Max File Size**: Error message in tooltip on invalid input
- [ ] **WinRM Timeout**: Rejects < 10 or > 300
- [ ] **WinRM Timeout**: Red border shown on invalid input
- [ ] **WinRM Timeout**: Error message in tooltip on invalid input
- [ ] **WinRM Retry Count**: Rejects < 1 or > 10
- [ ] **WinRM Retry Count**: Red border shown on invalid input
- [ ] **WinRM Retry Count**: Error message in tooltip on invalid input

## Edge Cases
- [ ] Settings file missing: Uses defaults
- [ ] Corrupt settings file: Uses defaults
- [ ] Invalid window bounds: Falls back to default size
- [ ] Multi-monitor with saved bounds on disconnected monitor: Falls back to primary
- [ ] Reset to Defaults: Confirmation dialog shows
- [ ] Reset to Defaults: All values reset to defaults
- [ ] Reset to Defaults: Validation errors cleared

## Integration Tests
- [ ] All settings serialize to JSON correctly
- [ ] All settings deserialize from JSON correctly
- [ ] WindowBounds validation works correctly
- [ ] Validation service returns correct results
- [ ] Settings dialog opens and closes without errors

## Performance
- [ ] Settings dialog opens in < 100ms
- [ ] Settings save in < 50ms
- [ ] Window bounds save on close doesn't delay shutdown
- [ ] Refresh interval change doesn't freeze UI

## Accessibility
- [ ] All controls have AutomationIds
- [ ] All controls have ToolTips
- [ ] Keyboard navigation works (Tab, Enter, ESC)
- [ ] Screen reader announces all settings
