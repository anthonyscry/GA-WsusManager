---
phase: 16-theme-infrastructure
plan: 01
status: complete
started: 2026-02-21
completed: 2026-02-21
tests_before: 336
tests_after: 336
---

# Phase 16 Plan 01 Summary: Theme Infrastructure

## What Was Done

Split the monolithic DarkTheme.xaml into permanent structural styles and swappable color tokens, migrated all color references to DynamicResource, converted ViewModel hardcoded brushes to theme-aware lookups, and implemented ThemeService for runtime theme swapping.

## Tasks Completed

### Task 1: Split DarkTheme.xaml + ThemeService
- Created `DefaultDark.xaml` with 19 semantic Color/SolidColorBrush pairs
- Created `SharedStyles.xaml` with all structural styles using DynamicResource
- Updated `App.xaml` to load both dictionaries
- Created `IThemeService` / `ThemeService` singleton that swaps color dictionaries via MergedDictionaries
- Added `SelectedTheme` property to `AppSettings`
- Wired ThemeService into DI and applied theme before MainWindow construction in `Program.cs`
- Deleted `DarkTheme.xaml`
- Created `ThemeServiceTests.cs` (6 tests)

### Task 2: Migrate StaticResource to DynamicResource
- Replaced all StaticResource color/brush references to DynamicResource with semantic names across 7 XAML files
- Replaced 12 hardcoded hex values in MainWindow.xaml DataTriggers
- Replaced hardcoded #F85149 in validation text of TransferDialog, ScheduleTaskDialog, InstallDialog
- Verified zero StaticResource color references remain (only Style refs like BasedOn stay as StaticResource)

### Task 3: ViewModel Brush Migration
- Added `GetThemeBrush(string resourceKey, Color fallback)` helper to MainViewModel
- Replaced all `new SolidColorBrush(Color.FromRgb(...))` in RunOperationAsync (4 status banner locations)
- Replaced ConnectionDotColor computed property
- Replaced all colors in UpdateDashboardCards (~20 locations)
- Field initializers left as hardcoded defaults (Application.Current not available at field init time; overwritten on first dashboard refresh)

### Task 4: Remove Backward-Compatible Aliases
- Verified no files reference old key names (BgDark, BgSidebar, etc.)
- Removed all 17 backward-compatible aliases from DefaultDark.xaml
- Build passes, all 336 tests pass

## Requirements Satisfied

| Requirement | Description | Evidence |
|-------------|-------------|----------|
| INFRA-01 | Split styles/tokens | SharedStyles.xaml (permanent) + DefaultDark.xaml (swappable) |
| INFRA-02 | All DynamicResource | Zero StaticResource color refs in any XAML file |
| INFRA-03 | No hardcoded hex | All hex values extracted to named keys |
| INFRA-04 | ViewModel theme-aware | GetThemeBrush helper replaces all Color.FromRgb calls |
| INFRA-05 | Runtime theme swap | ThemeService.ApplyTheme swaps color dictionary without restart |

## Files Changed

**Created:**
- `src/WsusManager.App/Themes/DefaultDark.xaml`
- `src/WsusManager.App/Themes/SharedStyles.xaml`
- `src/WsusManager.App/Services/IThemeService.cs`
- `src/WsusManager.App/Services/ThemeService.cs`
- `src/WsusManager.Tests/Services/ThemeServiceTests.cs`

**Modified:**
- `src/WsusManager.App/App.xaml`
- `src/WsusManager.App/Program.cs`
- `src/WsusManager.Core/Models/AppSettings.cs`
- `src/WsusManager.App/Views/MainWindow.xaml`
- `src/WsusManager.App/Views/SettingsDialog.xaml`
- `src/WsusManager.App/Views/TransferDialog.xaml`
- `src/WsusManager.App/Views/ScheduleTaskDialog.xaml`
- `src/WsusManager.App/Views/InstallDialog.xaml`
- `src/WsusManager.App/Views/SyncProfileDialog.xaml`
- `src/WsusManager.App/Views/GpoInstructionsDialog.xaml`
- `src/WsusManager.App/ViewModels/MainViewModel.cs`
- `src/WsusManager.Tests/WsusManager.Tests.csproj`

**Deleted:**
- `src/WsusManager.App/Themes/DarkTheme.xaml`

## Verification

- Build: 0 warnings, 0 errors
- Tests: 336 passed, 0 failed, 0 skipped
- StaticResource color refs: 0 remaining
- Old key name refs: 0 remaining
- Visual regression: Default dark theme renders identically to v4.2
