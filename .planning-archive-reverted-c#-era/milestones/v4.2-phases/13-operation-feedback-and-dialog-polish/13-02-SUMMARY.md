---
phase: 13-operation-feedback-and-dialog-polish
plan: "02"
subsystem: dialog-validation
tags: [dialogs, validation, ux, real-time-feedback]
dependency_graph:
  requires: []
  provides: [DLG-01, DLG-02, DLG-03, DLG-04]
  affects: [InstallDialog, TransferDialog, ScheduleTaskDialog]
tech_stack:
  added: []
  patterns: [real-time-validation, inline-feedback, safety-net-guard]
key_files:
  created: []
  modified:
    - src/WsusManager.App/Views/InstallDialog.xaml
    - src/WsusManager.App/Views/InstallDialog.xaml.cs
    - src/WsusManager.App/Views/TransferDialog.xaml
    - src/WsusManager.App/Views/TransferDialog.xaml.cs
    - src/WsusManager.App/Views/ScheduleTaskDialog.xaml
    - src/WsusManager.App/Views/ScheduleTaskDialog.xaml.cs
decisions:
  - "Validation TextBlock uses hardcoded #F85149 (matches Red resource) — acceptable for simple inline label"
  - "Ok_Click keeps safety-net guard (early return) rather than full re-validation — belt-and-suspenders"
  - "TransferDialog Export mode always enables BtnOk (all paths optional) — only Import requires source path"
  - "ScheduleTaskDialog initial validation text is descriptive (what is required) rather than an error message"
metrics:
  duration: 4 min
  completed: "2026-02-21"
  tasks: 2
  files_modified: 6
---

# Phase 13 Plan 02: Dialog Input Validation Summary

Real-time inline validation added to all three dialogs so primary action buttons are disabled when required fields are missing or invalid. Red feedback text shows admins exactly what needs to be fixed before proceeding.

## Tasks Completed

| Task | Name | Commit | Key Files |
|------|------|--------|-----------|
| 1 | Install dialog real-time validation | 5e5e37e | InstallDialog.xaml, InstallDialog.xaml.cs |
| 2 | Transfer and Schedule dialog validation | 21ebb7e | TransferDialog.xaml/cs, ScheduleTaskDialog.xaml/cs |

## What Was Built

### Install Dialog (DLG-01)
- `BtnInstall` now has `x:Name` and starts with `IsEnabled="False"`
- `TxtValidation` TextBlock (red #F85149) shows inline feedback
- `ValidateInputs()` checks: installer directory exists, password >= 15 characters
- `Input_Changed` handler wired to both `TextChanged` (TxtInstallerPath) and `PasswordChanged` (PwdSaPassword)
- `BrowseInstallerPath_Click` calls `ValidateInputs()` after setting path
- `Ok_Click` retains minimal safety-net guard; no MessageBox popups

### Transfer Dialog (DLG-02)
- `TxtValidation` TextBlock added before buttons (Grid Row 3, new row added)
- `TextChanged="Input_Changed"` added to `TxtSourcePath`
- `ValidateInputs()`: Export mode always valid; Import mode requires non-empty source path
- `Direction_Changed` calls `ValidateInputs()` so state updates immediately on mode switch
- `BrowseSource_Click` calls `ValidateInputs()` after folder selection
- MessageBox guard for source path removed from `Ok_Click` (replaced with silent return)

### Schedule Task Dialog (DLG-04)
- `BtnCreate` now has `x:Name` and starts with `IsEnabled="False"`
- `TxtValidation` TextBlock added between fields and buttons
- `ValidateInputs()` checks in order: task name not empty, time matches `^\d{2}:\d{2}$`, day of month 1-31 (Monthly only), password not empty
- `Input_Changed` handler wired to TxtTaskName, TxtTime, TxtDayOfMonth (TextChanged) and PwdPassword (PasswordChanged)
- `ScheduleType_Changed` calls `ValidateInputs()` so day-of-month requirement appears/disappears correctly
- `ValidateInputs()` called at end of constructor for correct initial state
- MessageBox validations removed from `Ok_Click`

### DLG-03 Consistency Check
- All three dialogs use `StaticResource` theme references (BgDark, BgInput, Text1, Text2, Border, BtnGreen, BtnSec)
- No hardcoded non-theme colors in any dialog XAML except validation red (#F85149, matches the `Red` resource value)

## Verification

- `dotnet build` — 0 errors, 0 warnings
- `dotnet test` — 263/263 tests pass
- Grep "ValidateInputs" in InstallDialog.xaml.cs: found (3 call sites + definition)
- Grep "ValidateInputs" in TransferDialog.xaml.cs: found (4 call sites + definition)
- Grep "ValidateInputs" in ScheduleTaskDialog.xaml.cs: found (4 call sites + definition)
- Grep "TxtValidation" in all three XAML files: found
- Grep "BtnInstall" in InstallDialog.xaml: found with IsEnabled="False"
- Grep "BtnCreate" in ScheduleTaskDialog.xaml: found with IsEnabled="False"

## Deviations from Plan

None - plan executed exactly as written.

## Self-Check: PASSED

- InstallDialog.xaml modified: FOUND
- InstallDialog.xaml.cs modified: FOUND
- TransferDialog.xaml modified: FOUND
- TransferDialog.xaml.cs modified: FOUND
- ScheduleTaskDialog.xaml modified: FOUND
- ScheduleTaskDialog.xaml.cs modified: FOUND
- Commit 5e5e37e: FOUND
- Commit 21ebb7e: FOUND
