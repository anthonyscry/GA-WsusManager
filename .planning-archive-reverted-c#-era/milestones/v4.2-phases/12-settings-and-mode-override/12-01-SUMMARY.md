---
phase: 12-settings-and-mode-override
plan: 01
subsystem: settings-dialog
tags: [wpf, settings, dialog, mvvm]
dependency_graph:
  requires: []
  provides: [SettingsDialog, OpenSettings command]
  affects: [MainViewModel, settings.json]
tech_stack:
  added: []
  patterns: [dialog-before-panel, relay-command, app-settings-persistence]
key_files:
  created:
    - src/WsusManager.App/Views/SettingsDialog.xaml
    - src/WsusManager.App/Views/SettingsDialog.xaml.cs
  modified:
    - src/WsusManager.App/ViewModels/MainViewModel.cs
decisions:
  - "Navigate('Settings') redirects to dialog rather than adding a Settings panel — modal dialog is more appropriate for configuration and matches the existing dialog pattern"
  - "OpenSettings has no CanExecute restriction — settings must always be accessible regardless of WSUS installation state or running operations"
metrics:
  duration: 163s
  completed: 2026-02-21
  tasks_completed: 2
  files_changed: 3
---

# Phase 12 Plan 01: Settings Dialog Summary

**One-liner:** Editable WPF Settings dialog with ServerMode ComboBox and TextBox fields for RefreshInterval, ContentPath, SqlInstance — persists to settings.json and applies immediately.

## What Was Built

A fully-functional Settings dialog that replaces the generic placeholder panel. Administrators can now edit all `AppSettings` fields without restarting the application.

### SettingsDialog.xaml / SettingsDialog.xaml.cs

- Width=480, Height=380, dark theme, no resize, center-owner
- ComboBox `CboServerMode` with "Online" / "Air-Gap" items, pre-selected from `_settings.ServerMode`
- TextBox fields for `RefreshIntervalSeconds`, `ContentPath`, `SqlInstance`
- Save button validates interval >= 5 seconds before accepting
- ESC key closes without saving (per CLAUDE.md GUI-09 pattern)
- `Result` property exposes the collected `AppSettings` on `DialogResult == true`
- Caller (`OpenSettings`) merges `LogPanelExpanded` and `LiveTerminalMode` to avoid losing those fields

### MainViewModel.cs — OpenSettings command

- `Navigate("Settings")` redirects to dialog instead of panel navigation
- `OpenSettings` [RelayCommand] — no CanExecute restriction (settings always accessible)
- Preserves `LogPanelExpanded` and `LiveTerminalMode` from current `_settings`
- Restarts auto-refresh timer if `RefreshIntervalSeconds` changed
- Calls `ApplySettings`, `SaveSettingsAsync`, `RefreshDashboard` after save
- Logs confirmation: "Settings saved. Server mode: X, Refresh: Ys"
- `OpenSettingsCommand.NotifyCanExecuteChanged()` added to `NotifyCommandCanExecuteChanged`

## Verification Results

- `dotnet build` — zero C# errors, zero warnings (68 MSB3021 file-copy errors are pre-existing WSL/Windows permission issue, not compilation errors)
- `SettingsDialog.baml` and `SettingsDialog.g.cs` generated in obj/ — XAML parsed successfully
- `SettingsDialog.xaml` and `SettingsDialog.xaml.cs` exist at expected paths
- `OpenSettings` RelayCommand at line 940 of MainViewModel.cs
- `Navigate("Settings")` guard at line 113 redirects to dialog

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check: PASSED

- FOUND: src/WsusManager.App/Views/SettingsDialog.xaml
- FOUND: src/WsusManager.App/Views/SettingsDialog.xaml.cs
- FOUND: OpenSettings RelayCommand in MainViewModel.cs (line 940)
- FOUND: Navigate("Settings") guard (line 113)
- FOUND: commit ee4fc94 (Task 1)
- FOUND: commit a536e58 (Task 2)
