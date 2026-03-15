# Phase 6: Installation and Scheduling — Plan

**Created:** 2026-02-20
**Requirements:** INST-01, INST-02, INST-03, SCHED-01, SCHED-02, SCHED-03, SCHED-04, GPO-01, GPO-02
**Goal:** Administrators can install WSUS with SQL Server Express through a guided wizard that requires no interactive console input, create Windows scheduled tasks for automated maintenance using domain credentials, and copy GPO deployment files with step-by-step instructions.

---

## Plans

### Plan 1: Installation service — PowerShell script orchestration

**What:** Create `IInstallationService` that validates installation prerequisites and launches the legacy `Install-WsusWithSqlExpress.ps1` script via `IProcessRunner` in non-interactive mode. The service collects all parameters (installer path, SA username, SA password) upfront and passes them as CLI arguments. No interactive console prompts appear during installation. Output streams to the log panel in real-time via the progress reporter. After installation completes successfully, the service signals that a dashboard refresh is needed to detect the newly-installed WSUS role.

**Requirements covered:** INST-01 (guided install), INST-02 (non-interactive from GUI)

**Files to create:**
- `src/WsusManager.Core/Models/InstallOptions.cs` — Record with: `string InstallerPath` (default `C:\WSUS\SQLDB`), `string SaUsername` (default `sa`), `string SaPassword`, `bool InstallSsms` (default false)
- `src/WsusManager.Core/Services/Interfaces/IInstallationService.cs` — Interface with:
  - `Task<OperationResult> ValidatePrerequisitesAsync(InstallOptions options, CancellationToken ct = default)` — Checks: installer path exists, `SQLEXPRADV_x64_ENU.exe` present, password not empty, password meets complexity (15+ chars, 1 number, 1 special char)
  - `Task<OperationResult> InstallAsync(InstallOptions options, IProgress<string> progress, CancellationToken ct)` — Runs `Install-WsusWithSqlExpress.ps1 -NonInteractive -InstallerPath {path} -SaUsername {user} -SaPassword {pass}` via `IProcessRunner`. Streams output lines to progress.
- `src/WsusManager.Core/Services/InstallationService.cs` — Implementation. Constructor injects `IProcessRunner`, `ILogService`. Locates the PowerShell script relative to the EXE directory (checks `Scripts\Install-WsusWithSqlExpress.ps1` and fallback to adjacent directory). Uses `powershell.exe -ExecutionPolicy Bypass -File` as the executable.

**Files to modify:**
- `src/WsusManager.App/Program.cs` — Register `IInstallationService` in DI

**Implementation notes:**
- The install script is the only operation that deliberately shells out to PowerShell. The script handles SQL Express setup, WSUS role installation, IIS configuration, and post-install steps — reimplementing in C# provides no benefit.
- Script path resolution: check `{AppDir}\Scripts\Install-WsusWithSqlExpress.ps1`, then `{AppDir}\Install-WsusWithSqlExpress.ps1`. Return `OperationResult.Fail` with a clear message listing search paths if not found.
- Password validation matches legacy: minimum 15 characters, at least 1 digit, at least 1 special character.

**Verification:**
1. Unit test: `ValidatePrerequisitesAsync` fails when installer path does not exist
2. Unit test: `ValidatePrerequisitesAsync` fails when required EXE is missing from path
3. Unit test: `ValidatePrerequisitesAsync` fails when password is empty
4. Unit test: `ValidatePrerequisitesAsync` fails when password does not meet complexity requirements
5. Unit test: `InstallAsync` constructs correct PowerShell arguments with `-NonInteractive`
6. Unit test: `InstallAsync` returns failure when script path not found
7. `dotnet build` succeeds with zero warnings

---

### Plan 2: Scheduled task service — schtasks.exe orchestration

**What:** Create `IScheduledTaskService` that creates, queries, and deletes Windows scheduled tasks using `schtasks.exe` via `IProcessRunner`. Uses `schtasks.exe` instead of COM TaskScheduler API — this is simpler, avoids a NuGet dependency, works reliably on Server 2019, and matches the existing `schtasks.exe` calls in `DashboardService.CheckScheduledTask`. The service creates a task that runs `powershell.exe -ExecutionPolicy Bypass -File Invoke-WsusMonthlyMaintenance.ps1 -Unattended -MaintenanceProfile {profile}` with domain credentials, running whether the user is logged on or not.

**Requirements covered:** SCHED-01 (create task), SCHED-02 (domain credentials), SCHED-03 (logon-not-required), SCHED-04 (profile and schedule selection)

**Files to create:**
- `src/WsusManager.Core/Models/ScheduledTaskOptions.cs` — Record with: `string TaskName` (default `WSUS Monthly Maintenance`), `ScheduleType Schedule` (Monthly/Weekly/Daily), `int DayOfMonth` (1-31, default 15), `DayOfWeek DayOfWeek` (default Saturday), `string Time` (HH:mm, default `02:00`), `string MaintenanceProfile` (Full/Quick/SyncOnly, default `Full`), `string Username` (default `.\dod_admin`), `string Password`, `int ExecutionTimeLimitHours` (default 4)
- `src/WsusManager.Core/Models/ScheduleType.cs` — Enum: `Monthly`, `Weekly`, `Daily`
- `src/WsusManager.Core/Services/Interfaces/IScheduledTaskService.cs` — Interface with:
  - `Task<OperationResult> CreateTaskAsync(ScheduledTaskOptions options, IProgress<string>? progress, CancellationToken ct)` — Creates (or replaces) a scheduled task
  - `Task<OperationResult<string>> QueryTaskAsync(string taskName, CancellationToken ct)` — Returns task status string (Ready/Running/Disabled/Not Found)
  - `Task<OperationResult> DeleteTaskAsync(string taskName, IProgress<string>? progress, CancellationToken ct)` — Deletes an existing task
- `src/WsusManager.Core/Services/ScheduledTaskService.cs` — Implementation. Constructor injects `IProcessRunner`, `ILogService`. `CreateTaskAsync`:
  1. Delete existing task with same name (ignore failure = task doesn't exist)
  2. Build `schtasks /Create` arguments: `/TN "{name}"`, `/TR "powershell.exe -ExecutionPolicy Bypass -File \"{scriptPath}\" -Unattended -MaintenanceProfile {profile}"`, `/SC {MONTHLY|WEEKLY|DAILY}`, `/D {day}` or `/MO {day}`, `/ST {time}`, `/RU "{username}"`, `/RP "{password}"`, `/RL HIGHEST`, `/F`
  3. Run via `IProcessRunner` and check exit code
  4. Report success with next run time or failure with error details

**Files to modify:**
- `src/WsusManager.App/Program.cs` — Register `IScheduledTaskService` in DI

**Implementation notes:**
- `schtasks /Create` with `/SC MONTHLY /D 15` sets day-of-month. `/SC WEEKLY /D SAT` sets day-of-week. `/SC DAILY` needs no day parameter.
- The `/RU` and `/RP` parameters handle domain credentials. The task runs with RunLevel HIGHEST and the "run whether user is logged on or not" behavior is the default when credentials are provided.
- Execution time limit: `/ET` is not available for all schedule types. Instead, use the `/XML` approach or accept the default behavior. If `schtasks` doesn't support the 4-hour limit directly, log it as a limitation.
- Script path for the task action: locate `Invoke-WsusMonthlyMaintenance.ps1` using the same pattern as the install script (relative to EXE directory).

**Verification:**
1. Unit test: `CreateTaskAsync` builds correct `schtasks /Create` arguments for Monthly schedule
2. Unit test: `CreateTaskAsync` builds correct arguments for Weekly schedule with day-of-week
3. Unit test: `CreateTaskAsync` builds correct arguments for Daily schedule
4. Unit test: `CreateTaskAsync` includes `/RU` and `/RP` with provided credentials
5. Unit test: `CreateTaskAsync` includes `/RL HIGHEST` for elevated execution
6. Unit test: `DeleteTaskAsync` calls `schtasks /Delete` with `/F` (force, no confirmation)
7. Unit test: `QueryTaskAsync` parses CSV output for task status
8. `dotnet build` succeeds

---

### Plan 3: GPO deployment service

**What:** Create `IGpoDeploymentService` that copies GPO deployment files from the application's `DomainController/` directory to `C:\WSUS\WSUS GPO\`. The source directory contains `Set-WsusGroupPolicy.ps1` and the `WSUS GPOs/` subdirectory. After copying, the service returns a structured instructions text that the UI can display. The service validates source files exist before copying.

**Requirements covered:** GPO-01 (copy files), GPO-02 (instructions)

**Files to create:**
- `src/WsusManager.Core/Services/Interfaces/IGpoDeploymentService.cs` — Interface with:
  - `Task<OperationResult<string>> DeployGpoFilesAsync(IProgress<string>? progress, CancellationToken ct)` — Copies files and returns instruction text on success
- `src/WsusManager.Core/Services/GpoDeploymentService.cs` — Implementation. Constructor injects `ILogService`. `DeployGpoFilesAsync`:
  1. Locate `DomainController/` directory relative to EXE (same resolution pattern as install script)
  2. Validate source directory exists and contains expected files
  3. Create destination `C:\WSUS\WSUS GPO\` if it doesn't exist
  4. Copy all files recursively (overwrite existing)
  5. Return instruction text:
     - "GPO files copied to C:\WSUS\WSUS GPO\"
     - "Steps for DC admin:"
     - "1. Copy the WSUS GPO folder to the Domain Controller"
     - "2. Run Set-WsusGroupPolicy.ps1 on the DC"
     - "3. Force client check-in: gpupdate /force && wuauclt /detectnow"

**Files to modify:**
- `src/WsusManager.App/Program.cs` — Register `IGpoDeploymentService` in DI

**Implementation notes:**
- Use `Directory.CreateDirectory` for destination. Use `File.Copy` with overwrite for individual files.
- Recursive copy of entire `DomainController/` directory tree preserving structure.
- If source directory not found, return `OperationResult.Fail` with expected path.

**Verification:**
1. Unit test: Returns failure when `DomainController/` directory not found
2. Unit test: Creates destination directory when it doesn't exist
3. Unit test: Returns instruction text on success
4. `dotnet build` succeeds

---

### Plan 4: Installation dialog and ViewModel command

**What:** Create the Install WSUS dialog (WPF Window) and wire the `RunInstallWsusCommand` in `MainViewModel`. The dialog collects: Installer Path (with browse button, default `C:\WSUS\SQLDB`), SA Username (text, default `sa`), SA Password (password box). Pre-flight validation runs before starting. This is the ONLY operation that remains enabled when WSUS is not installed — all other operations require WSUS to be present (INST-03). After successful installation, refresh dashboard and re-enable all operation buttons.

**Requirements covered:** INST-01 (wizard UI), INST-02 (non-interactive), INST-03 (button state)

**Files to create:**
- `src/WsusManager.App/Views/InstallDialog.xaml` — WPF dialog with:
  - Dark theme styling (matching existing dialogs)
  - Installer Path field with Browse button (default `C:\WSUS\SQLDB`)
  - SA Username field (default `sa`)
  - SA Password field (PasswordBox)
  - Description text explaining what will be installed
  - OK ("Install") and Cancel buttons
  - ESC key closes dialog (GUI-04)
  - ~480x360 size matching existing dialog patterns
- `src/WsusManager.App/Views/InstallDialog.xaml.cs` — Code-behind: browse button handler (OpenFolderDialog), password extraction, validation before closing. Returns `InstallOptions` via public property.

**Files to modify:**
- `src/WsusManager.App/ViewModels/MainViewModel.cs` — Add:
  - Constructor parameter for `IInstallationService`
  - `RunInstallWsusCommand` — Show `InstallDialog`, validate via `IInstallationService.ValidatePrerequisitesAsync`, run `InstallAsync` through `RunOperationAsync`. On success, refresh dashboard.
  - New `CanExecuteInstall()` — returns `!IsOperationRunning` (does NOT require IsWsusInstalled, unlike other operations)
  - Update `NotifyCommandCanExecuteChanged` with `RunInstallWsusCommand`
- `src/WsusManager.App/Views/MainWindow.xaml` — Wire "Install WSUS" sidebar button to `RunInstallWsusCommand` (instead of NavigateCommand)

**Implementation notes:**
- Dialog before panel switch pattern (per CLAUDE.md): show the install dialog first, only navigate to the operation panel and start the install after user confirms.
- Password is extracted from PasswordBox in code-behind (PasswordBox.Password is not bindable by design in WPF for security).
- The install button must use `CanExecuteInstall` (not `CanExecuteWsusOperation`) so it stays enabled when WSUS is not installed.

**Verification:**
1. Install dialog shows all three fields with correct defaults
2. ESC key closes dialog
3. Browse button opens folder picker
4. Install button enabled when WSUS is NOT installed
5. Install runs through RunOperationAsync with progress in log panel
6. Dashboard refreshes after successful install
7. `dotnet build` succeeds

---

### Plan 5: Schedule task dialog and ViewModel command

**What:** Create the Schedule Task dialog (WPF Window) and wire the `RunScheduleTaskCommand` in `MainViewModel`. The dialog matches the legacy PowerShell schedule dialog (~540px height) with all fields visible: Task Name, Schedule Type (combo: Monthly/Weekly/Daily), Day of Month (1-31), Day of Week (combo), Time (HH:mm), Maintenance Profile (combo: Full/Quick/SyncOnly), Username, Password. Day of Month and Day of Week fields toggle visibility based on selected schedule type.

**Requirements covered:** SCHED-01 (create task UI), SCHED-02 (domain credentials), SCHED-03 (logon-not-required), SCHED-04 (profile and schedule)

**Files to create:**
- `src/WsusManager.App/Views/ScheduleTaskDialog.xaml` — WPF dialog with:
  - Dark theme styling (~520x560 size)
  - Task Name text field (default "WSUS Monthly Maintenance")
  - Schedule Type combo: Monthly, Weekly, Daily
  - Day of Month text field (1-31, default 15) — visible only when Monthly
  - Day of Week combo (Sunday-Saturday, default Saturday) — visible only when Weekly
  - Time text field (HH:mm, default "02:00")
  - Maintenance Profile combo: Full Sync, Quick Sync, Sync Only (default Full)
  - Username text field (default `.\dod_admin`)
  - Password field (PasswordBox)
  - OK ("Create Task") and Cancel buttons
  - ESC key closes dialog (GUI-04)
- `src/WsusManager.App/Views/ScheduleTaskDialog.xaml.cs` — Code-behind: schedule type changed handler (toggles day fields), validation, returns `ScheduledTaskOptions` via public property.

**Files to modify:**
- `src/WsusManager.App/ViewModels/MainViewModel.cs` — Add:
  - Constructor parameter for `IScheduledTaskService`
  - `RunScheduleTaskCommand` — Show `ScheduleTaskDialog`, run `IScheduledTaskService.CreateTaskAsync` through `RunOperationAsync`. On success, refresh dashboard to update Task card status.
  - Wire command with `CanExecuteWsusOperation`
  - Update `NotifyCommandCanExecuteChanged` with `RunScheduleTaskCommand`
- `src/WsusManager.App/Views/MainWindow.xaml` — Wire "Schedule Task" sidebar button to `RunScheduleTaskCommand` (instead of NavigateCommand)

**Verification:**
1. Schedule dialog shows all fields with correct defaults
2. Day of Month visible only when Monthly selected; Day of Week only when Weekly
3. ESC key closes dialog
4. Creating task runs through RunOperationAsync
5. Dashboard Task card updates after successful creation
6. `dotnet build` succeeds

---

### Plan 6: GPO deployment command and sidebar wiring

**What:** Add the "Create GPO" button to the sidebar and wire the `RunCreateGpoCommand` in `MainViewModel`. Clicking the button runs `IGpoDeploymentService.DeployGpoFilesAsync` through `RunOperationAsync`. On success, shows a custom dialog with copyable instruction text (not a plain MessageBox, since the instructions contain commands the admin needs to copy). Also add "Create GPO" under the SETUP category in the sidebar.

**Requirements covered:** GPO-01 (copy files UI), GPO-02 (instructions dialog)

**Files to create:**
- `src/WsusManager.App/Views/GpoInstructionsDialog.xaml` — Small dark-themed dialog (~480x380) with:
  - Success header
  - Read-only TextBox with instruction text (selectable/copyable)
  - "Copy to Clipboard" button
  - "Close" button
  - ESC key closes (GUI-04)
- `src/WsusManager.App/Views/GpoInstructionsDialog.xaml.cs` — Code-behind: constructor takes instruction text, Copy button copies to clipboard

**Files to modify:**
- `src/WsusManager.App/ViewModels/MainViewModel.cs` — Add:
  - Constructor parameter for `IGpoDeploymentService`
  - `RunCreateGpoCommand` — Run `DeployGpoFilesAsync`, on success show `GpoInstructionsDialog` with returned instruction text
  - Wire with `CanExecuteWsusOperation`
  - Update `NotifyCommandCanExecuteChanged` with `RunCreateGpoCommand`
- `src/WsusManager.App/Views/MainWindow.xaml` — Add "Create GPO" button under SETUP category (after Install WSUS button), bound to `RunCreateGpoCommand`

**Verification:**
1. Create GPO button appears in sidebar under SETUP
2. Running the command copies files and shows instruction dialog
3. Instruction text is selectable and copyable
4. Copy to Clipboard button works
5. ESC closes the instruction dialog
6. `dotnet build` succeeds

---

### Plan 7: Tests and integration verification

**What:** Add comprehensive unit tests for all Phase 6 services and ViewModel commands. Verify all success criteria from the roadmap. Update DI container tests to verify new service registrations.

**Requirements covered:** All Phase 6 requirements (verification)

**Files to create:**
- `src/WsusManager.Tests/Services/InstallationServiceTests.cs` — Tests: prerequisite validation (missing path, missing EXE, empty password, weak password, valid password), install argument construction, script-not-found failure, progress reporting
- `src/WsusManager.Tests/Services/ScheduledTaskServiceTests.cs` — Tests: Monthly/Weekly/Daily argument construction, credential inclusion, elevated RunLevel, delete force flag, query status parsing (Ready/Running/Disabled/Not Found), task name quoting
- `src/WsusManager.Tests/Services/GpoDeploymentServiceTests.cs` — Tests: source-not-found failure, destination creation, instruction text content, success result

**Files to modify:**
- `src/WsusManager.Tests/ViewModels/MainViewModelTests.cs` — Add tests: `RunInstallWsus` CanExecute does NOT require IsWsusInstalled, `RunScheduleTask` CanExecute requires IsWsusInstalled, `RunCreateGpo` CanExecute requires IsWsusInstalled
- `src/WsusManager.Tests/Integration/DiContainerTests.cs` — Add resolution tests for IInstallationService, IScheduledTaskService, IGpoDeploymentService

**Verification:**
1. `dotnet build` — 0 warnings, 0 errors
2. `dotnet test` — All tests pass (existing 170+ plus new Phase 6 tests)
3. All 4 Phase 6 success criteria verified in tests:
   - Installation wizard runs non-interactively with parameters collected via dialog
   - WSUS not-installed state: only Install button enabled, others disabled
   - Scheduled task created with domain credentials, runs whether logged on or not
   - GPO files copied with step-by-step instructions shown

---

## Plan Summary

| Plan | Description | Requirements |
|------|-------------|--------------|
| 1 | Installation service — PowerShell script orchestration | INST-01, INST-02 |
| 2 | Scheduled task service — schtasks.exe orchestration | SCHED-01, SCHED-02, SCHED-03, SCHED-04 |
| 3 | GPO deployment service | GPO-01, GPO-02 |
| 4 | Installation dialog and ViewModel command | INST-01, INST-02, INST-03 |
| 5 | Schedule task dialog and ViewModel command | SCHED-01, SCHED-02, SCHED-03, SCHED-04 |
| 6 | GPO deployment command and sidebar wiring | GPO-01, GPO-02 |
| 7 | Tests and integration verification | All Phase 6 |

## Execution Order

Plans 1 through 7 execute sequentially. Each plan builds on the previous:
- Plans 1–3 create the Core services (installation, scheduling, GPO) — no UI dependencies
- Plan 4 creates the install dialog and wires it using Plan 1's service
- Plan 5 creates the schedule task dialog and wires it using Plan 2's service
- Plan 6 wires the GPO button using Plan 3's service
- Plan 7 adds tests and verifies all success criteria

## Success Criteria (from Roadmap)

All four Phase 6 success criteria must be TRUE after Plan 7 completes:

1. The installation wizard guides the user through WSUS + SQL Express setup entirely within the GUI — no console prompts appear, and all input (paths, credentials) is collected through dialog fields before installation begins
2. All WSUS operation buttons are disabled and show visual feedback when WSUS is not yet installed on the server — only the Install WSUS button remains active
3. User can create a Windows scheduled task that runs maintenance automatically on the configured day using domain credentials, and the task runs successfully whether or not the user is logged on
4. User can copy GPO deployment files to `C:\WSUS\WSUS GPO` and sees clear instructions for applying the GPO on the domain controller

---

*Phase: 06-installation-and-scheduling*
*Plan created: 2026-02-20*
