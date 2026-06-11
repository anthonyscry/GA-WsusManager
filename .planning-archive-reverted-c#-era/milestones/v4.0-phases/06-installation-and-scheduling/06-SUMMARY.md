# Phase 6: Installation and Scheduling -- Summary

**Completed:** 2026-02-20
**Tests:** 214 total (44 new Phase 6 tests + 170 existing)
**Build:** 0 warnings, 0 errors (Debug + Release)

---

## What Was Built

### Plan 1: Installation Service
- `InstallOptions` model with installer path, SA username, SA password, SSMS flag
- `IInstallationService` interface with `ValidatePrerequisitesAsync` and `InstallAsync`
- `InstallationService` implementation: validates prerequisites (path exists, EXE present, password complexity 15+ chars / 1 digit / 1 special), locates Install-WsusWithSqlExpress.ps1 relative to EXE, runs via `IProcessRunner` with `-NonInteractive` flag

### Plan 2: Scheduled Task Service
- `ScheduleType` enum (Monthly, Weekly, Daily)
- `ScheduledTaskOptions` model with all scheduling fields and domain credentials
- `IScheduledTaskService` interface with `CreateTaskAsync`, `QueryTaskAsync`, `DeleteTaskAsync`
- `ScheduledTaskService` implementation: uses `schtasks.exe` via `IProcessRunner`, builds correct arguments per schedule type, includes `/RU` + `/RP` + `/RL HIGHEST` for elevated domain credentials, parses CSV output for status queries

### Plan 3: GPO Deployment Service
- `IGpoDeploymentService` interface with `DeployGpoFilesAsync`
- `GpoDeploymentService` implementation: locates `DomainController/` directory relative to EXE, copies all files recursively to `C:\WSUS\WSUS GPO\`, returns structured instruction text with 3 DC admin steps

### Plan 4: Installation Dialog and ViewModel Command
- `InstallDialog.xaml` / `.xaml.cs`: dark-themed dialog (480x360) with installer path (browse button), SA username, SA password (PasswordBox), ESC closes
- `RunInstallWsusCommand` in MainViewModel: shows dialog first (pattern: dialog before panel switch), validates prerequisites, runs install through `RunOperationAsync`, refreshes dashboard on success
- `CanExecuteInstall()`: returns `!IsOperationRunning` -- does NOT require IsWsusInstalled (the only button that stays enabled when WSUS is not installed)

### Plan 5: Schedule Task Dialog and ViewModel Command
- `ScheduleTaskDialog.xaml` / `.xaml.cs`: dark-themed dialog (520x560) with task name, schedule type combo, day of month (visible when Monthly), day of week combo (visible when Weekly), time, maintenance profile combo, username, password, ESC closes
- `RunScheduleTaskCommand` in MainViewModel: shows dialog, creates task through `RunOperationAsync`, refreshes dashboard to update Task card

### Plan 6: GPO Deployment Command and Sidebar Wiring
- `GpoInstructionsDialog.xaml` / `.xaml.cs`: dark-themed dialog (480x380) with read-only copyable TextBox, "Copy to Clipboard" button, ESC closes
- `RunCreateGpoCommand` in MainViewModel: runs GPO deployment, shows instructions dialog on success
- Sidebar: "Create GPO" button added under SETUP category (after Install WSUS)
- Install WSUS button wired to `RunInstallWsusCommand` (was Navigate)
- Schedule Task button wired to `RunScheduleTaskCommand` (was Navigate)

### Plan 7: Tests and Verification
- `InstallationServiceTests`: 10 tests (prerequisite validation for missing path, missing EXE, empty password, short password, no digit, no special char, valid options; install argument construction, script-not-found, progress reporting)
- `ScheduledTaskServiceTests`: 15 tests (Monthly/Weekly/Daily args, credentials, RL HIGHEST, force flag, task name, start time, all 7 DayOfWeek mappings, delete with /F, query Ready/Running/Disabled/Not Found, create failure when script missing)
- `GpoDeploymentServiceTests`: 6 tests (source not found, instruction text content, recursive copy, overwrite, source name, destination path)
- `MainViewModelTests`: 6 new tests (RunInstallWsus CanExecute true when WSUS not installed, true when installed; RunScheduleTask CanExecute false when not installed, true when installed; RunCreateGpo CanExecute false when not installed, true when installed)
- `DiContainerTests`: 4 new tests (InstallationService, ScheduledTaskService, GpoDeploymentService individual + combined resolution)
- `InternalsVisibleTo` added to Core.csproj for test access to internal methods

### DI Registration
- `IInstallationService` -> `InstallationService` (singleton)
- `IScheduledTaskService` -> `ScheduledTaskService` (singleton)
- `IGpoDeploymentService` -> `GpoDeploymentService` (singleton)

---

## Files Created (18)

### Core Models
- `src/WsusManager.Core/Models/InstallOptions.cs`
- `src/WsusManager.Core/Models/ScheduleType.cs`
- `src/WsusManager.Core/Models/ScheduledTaskOptions.cs`

### Core Service Interfaces
- `src/WsusManager.Core/Services/Interfaces/IInstallationService.cs`
- `src/WsusManager.Core/Services/Interfaces/IScheduledTaskService.cs`
- `src/WsusManager.Core/Services/Interfaces/IGpoDeploymentService.cs`

### Core Service Implementations
- `src/WsusManager.Core/Services/InstallationService.cs`
- `src/WsusManager.Core/Services/ScheduledTaskService.cs`
- `src/WsusManager.Core/Services/GpoDeploymentService.cs`

### WPF Dialogs
- `src/WsusManager.App/Views/InstallDialog.xaml` + `.xaml.cs`
- `src/WsusManager.App/Views/ScheduleTaskDialog.xaml` + `.xaml.cs`
- `src/WsusManager.App/Views/GpoInstructionsDialog.xaml` + `.xaml.cs`

### Tests
- `src/WsusManager.Tests/Services/InstallationServiceTests.cs`
- `src/WsusManager.Tests/Services/ScheduledTaskServiceTests.cs`
- `src/WsusManager.Tests/Services/GpoDeploymentServiceTests.cs`

## Files Modified (6)
- `src/WsusManager.Core/WsusManager.Core.csproj` (InternalsVisibleTo)
- `src/WsusManager.App/Program.cs` (Phase 6 DI registrations)
- `src/WsusManager.App/ViewModels/MainViewModel.cs` (3 new services, 3 new commands, CanExecuteInstall)
- `src/WsusManager.App/Views/MainWindow.xaml` (sidebar wiring: Install, Create GPO, Schedule Task)
- `src/WsusManager.Tests/Integration/DiContainerTests.cs` (Phase 6 registrations + 4 tests)
- `src/WsusManager.Tests/ViewModels/MainViewModelTests.cs` (3 new mocks + 6 CanExecute tests)

---

## Success Criteria Verification

1. **Installation wizard guides user through WSUS + SQL Express setup entirely within GUI** -- InstallDialog collects all parameters (path, username, password) before installation. InstallationService passes `-NonInteractive` to the PowerShell script. No console prompts appear.

2. **All WSUS operation buttons disabled when WSUS not installed; only Install button remains active** -- `CanExecuteWsusOperation()` requires `IsWsusInstalled`. `CanExecuteInstall()` only requires `!IsOperationRunning`. Verified by 6 CanExecute unit tests.

3. **User can create a scheduled task with domain credentials, runs whether logged on or not** -- ScheduleTaskDialog collects username + password. ScheduledTaskService uses `/RU` + `/RP` + `/RL HIGHEST`. When credentials are provided to schtasks, the task runs whether logged on or not (Windows default behavior).

4. **User can copy GPO files and sees clear instructions** -- GpoDeploymentService copies DomainController/ to `C:\WSUS\WSUS GPO\`. GpoInstructionsDialog shows copyable instructions with 3 steps for the DC admin.

---

*Phase: 06-installation-and-scheduling*
*Completed: 2026-02-20*
