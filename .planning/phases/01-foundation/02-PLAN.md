# Phase 1: Foundation — Plan

**Created:** 2026-02-19
**Requirements:** FOUND-01, FOUND-02, FOUND-03, FOUND-04, FOUND-05, GUI-05
**Goal:** Compilable C#/.NET 9 WPF solution with DI wiring, async operation pattern, UAC manifest, structured logging, DPI awareness, and single-file publish — producing a running skeleton before any WSUS features.

---

## Plans

### Plan 1: Solution scaffold and project structure

**What:** Create the .NET 9 solution with two projects (WsusManager.App for WPF, WsusManager.Core for business logic) and one test project (WsusManager.Tests). Configure csproj files with correct target frameworks, NuGet references, single-file publish settings, and UAC manifest.

**Requirements covered:** FOUND-02 (single EXE), FOUND-03 (UAC manifest), GUI-05 (DPI awareness via manifest)

**Files to create:**
- `src/WsusManager.sln` — Solution file
- `src/WsusManager.App/WsusManager.App.csproj` — WPF app project (.NET 9, WinExe, single-file publish config, UAC manifest, DPI awareness)
- `src/WsusManager.App/app.manifest` — UAC requireAdministrator + DPI awareness (per-monitor v2)
- `src/WsusManager.App/App.xaml` — Application definition (no StartupUri, handled in code)
- `src/WsusManager.App/App.xaml.cs` — DI host setup, exception handler wiring
- `src/WsusManager.App/Program.cs` — `[STAThread] Main()` entry point
- `src/WsusManager.Core/WsusManager.Core.csproj` — Class library (.NET 9, no WPF dependency)
- `src/WsusManager.Tests/WsusManager.Tests.csproj` — xUnit test project

**Verification:**
1. `dotnet build src/WsusManager.sln` succeeds with zero errors
2. `dotnet publish src/WsusManager.App -c Release -r win-x64 --self-contained` produces a single EXE
3. The app.manifest contains `requireAdministrator` and `dpiAwareness` elements
4. Test project builds and `dotnet test` passes (placeholder test)

---

### Plan 2: Structured logging with Serilog

**What:** Implement the logging infrastructure that writes structured log entries to `C:\WSUS\Logs\WsusManager-{Date}.log` with daily rolling files. Create a thin wrapper service behind an interface for DI injection. Log application version, startup duration, and environment info on startup.

**Requirements covered:** FOUND-04 (structured logging to C:\WSUS\Logs\)

**Files to create:**
- `src/WsusManager.Core/Logging/ILogService.cs` — Logging service interface
- `src/WsusManager.Core/Logging/LogService.cs` — Serilog implementation with file sink to C:\WSUS\Logs\

**Files to modify:**
- `src/WsusManager.App/Program.cs` — Register Serilog and ILogService in DI, log startup info

**Verification:**
1. On startup, a log file is created at `C:\WSUS\Logs\WsusManager-{date}.log`
2. Log file contains application version, startup duration, and OS info
3. Log entries use structured format: `[Timestamp Level] Message`
4. Unit test: LogService creates log directory if missing

---

### Plan 3: RunOperationAsync pattern and OperationResult model

**What:** Implement the core async operation runner pattern in a base ViewModel class. This is the single wrapper through which every future operation will execute. It manages the `IsOperationRunning` flag, CancellationTokenSource lifecycle, progress reporting via `IProgress<string>`, and ensures the finally block always resets state. Also create the `OperationResult` model used by all services.

**Requirements covered:** FOUND-05 (graceful error handling), part of the async foundation

**Files to create:**
- `src/WsusManager.Core/Models/OperationResult.cs` — Result type with Ok/Fail factory methods
- `src/WsusManager.App/ViewModels/MainViewModel.cs` — ViewModel with `RunOperationAsync`, `IsOperationRunning`, `LogOutput`, `CancelCommand`

**Verification:**
1. Unit test: RunOperationAsync sets IsOperationRunning=true during execution and false after
2. Unit test: RunOperationAsync catches OperationCanceledException and reports "[Cancelled]"
3. Unit test: RunOperationAsync catches unhandled exceptions and reports error to log
4. Unit test: CancelCommand triggers cancellation of running operation
5. Unit test: CanExecute returns false when IsOperationRunning is true

---

### Plan 4: Main window with empty shell and global error handling

**What:** Create the MainWindow XAML with a minimal placeholder layout (just a title bar and empty content area) wired to MainViewModel via DI. Add global unhandled exception handlers (Dispatcher + TaskScheduler + AppDomain) that show a user-friendly error dialog with expandable details and write full details to the log. Wire the window to show immediately on startup for sub-second perceived startup.

**Requirements covered:** FOUND-01 (sub-second startup), FOUND-05 (graceful error handling with user-friendly dialogs)

**Files to create:**
- `src/WsusManager.App/Views/MainWindow.xaml` — Minimal window (title, placeholder content)
- `src/WsusManager.App/Views/MainWindow.xaml.cs` — Constructor sets DataContext from DI

**Files to modify:**
- `src/WsusManager.App/App.xaml.cs` — Global exception handlers (DispatcherUnhandledException, TaskScheduler.UnobservedTaskException, AppDomain.CurrentDomain.UnhandledException)
- `src/WsusManager.App/Program.cs` — Startup timing measurement, log startup duration

**Verification:**
1. Application launches and shows a window with title "WSUS Manager"
2. Startup timing is logged (target: under 1 second)
3. Throwing an unhandled exception in the ViewModel shows an error dialog (not a crash)
4. Error dialog has "Show Details" expansion with stack trace
5. Error details are written to the log file
6. Unit test: MainViewModel can be constructed with mocked services

---

### Plan 5: Settings service and infrastructure helpers

**What:** Create the SettingsService that reads/writes JSON to `%APPDATA%\WsusManager\settings.json`, the ProcessRunner for external command execution, and the basic AppSettings model. These are infrastructure components needed by every subsequent phase.

**Requirements covered:** Foundation infrastructure for all future phases

**Files to create:**
- `src/WsusManager.Core/Models/AppSettings.cs` — Settings data model (server mode, log panel state, live terminal toggle)
- `src/WsusManager.Core/Services/Interfaces/ISettingsService.cs` — Settings service interface
- `src/WsusManager.Core/Services/SettingsService.cs` — JSON file persistence to %APPDATA%
- `src/WsusManager.Core/Infrastructure/ProcessRunner.cs` — External process execution with async output capture and cancellation
- `src/WsusManager.Core/Infrastructure/IProcessRunner.cs` — Interface for testability
- `src/WsusManager.Core/Models/ProcessResult.cs` — Process execution result (exit code, output lines)

**Verification:**
1. Unit test: SettingsService.SaveAsync writes JSON to expected path
2. Unit test: SettingsService.LoadAsync reads JSON and deserializes correctly
3. Unit test: SettingsService.LoadAsync returns defaults when file is missing
4. Unit test: ProcessRunner.RunAsync captures stdout and stderr
5. Unit test: ProcessRunner.RunAsync kills process on cancellation
6. Unit test: ProcessRunner reports progress via IProgress<string>

---

### Plan 6: DI wiring, final integration, and publish validation

**What:** Wire all services and ViewModels into the DI container in Program.cs. Verify the complete startup path: Program.Main → Host.Build → resolve MainWindow → show window → log startup. Validate single-file publish produces a working EXE. Add a smoke test that verifies the solution builds and the EXE exists.

**Requirements covered:** FOUND-01 (startup time), FOUND-02 (single EXE), final integration

**Files to modify:**
- `src/WsusManager.App/Program.cs` — Complete DI registration for all services, ViewModels, and views

**Files to create:**
- `src/WsusManager.Tests/Integration/StartupTests.cs` — Verify DI container resolves all services without error
- `src/WsusManager.Tests/Foundation/OperationResultTests.cs` — OperationResult model tests
- `src/WsusManager.Tests/Foundation/SettingsServiceTests.cs` — Settings persistence tests

**Verification:**
1. `dotnet build src/WsusManager.sln` succeeds
2. `dotnet test src/WsusManager.Tests` passes all tests
3. `dotnet publish src/WsusManager.App -c Release -r win-x64 --self-contained -p:PublishSingleFile=true` produces a single EXE
4. Published EXE file exists and is > 10MB (sanity check for embedded runtime)
5. DI container resolves MainViewModel with all dependencies without exception

---

## Plan Summary

| Plan | Description | Requirements |
|------|-------------|--------------|
| 1 | Solution scaffold and project structure | FOUND-02, FOUND-03, GUI-05 |
| 2 | Structured logging with Serilog | FOUND-04 |
| 3 | RunOperationAsync pattern and OperationResult | FOUND-05 |
| 4 | Main window shell and global error handling | FOUND-01, FOUND-05 |
| 5 | Settings service and infrastructure helpers | Foundation |
| 6 | DI wiring, integration, publish validation | FOUND-01, FOUND-02 |

## Execution Order

Plans 1 through 6 execute sequentially. Each plan builds on the previous:
- Plan 1 creates the projects that Plans 2-6 add code to
- Plan 2 creates logging that Plans 3-6 use
- Plan 3 creates the operation pattern that Plan 4 wires into the window
- Plan 4 creates the window that Plan 6 wires into DI
- Plan 5 creates infrastructure that Plan 6 registers in DI
- Plan 6 ties everything together and validates the complete system

## Success Criteria (from Roadmap)

All five Phase 1 success criteria must be TRUE after Plan 6 completes:

1. The solution builds without errors and the published EXE runs on a clean Windows Server 2019 machine without installing .NET runtime
2. Launching the EXE without administrator privileges triggers a UAC elevation prompt before the window appears
3. Every operation invocation routes through a single `RunOperationAsync` wrapper — no raw async void handlers with uncaught exceptions
4. Application starts and shows its main window in under 1 second on Windows Server 2019
5. All log output writes structured entries to `C:\WSUS\Logs\` on startup

---

*Phase: 01-foundation*
*Plan created: 2026-02-19*
