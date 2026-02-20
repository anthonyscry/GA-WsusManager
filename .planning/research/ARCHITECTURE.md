# Architecture Research

**Domain:** Windows Server administration GUI tool (WPF/.NET 9, WSUS + SQL Server Express)
**Researched:** 2026-02-19
**Confidence:** HIGH (WPF/MVVM/DI patterns), MEDIUM (WSUS API constraints)

## Standard Architecture

### System Overview

```
┌────────────────────────────────────────────────────────────────────┐
│                        Presentation Layer                          │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────────────────┐   │
│  │  MainWindow  │  │   Dialogs    │  │   XAML / Data Binding  │   │
│  │  (View-only) │  │  (View-only) │  │   (no code-behind)     │   │
│  └──────┬───────┘  └──────┬───────┘  └───────────┬────────────┘   │
│         │                 │                       │                │
│  ┌──────▼─────────────────▼───────────────────────▼────────────┐  │
│  │                     MainViewModel                            │  │
│  │  [ObservableProperty] [RelayCommand] [NotifyCanExecuteChanged]│  │
│  └─────────────────────────────┬────────────────────────────────┘  │
└─────────────────────────────────┼──────────────────────────────────┘
                                  │ constructor injection
┌─────────────────────────────────┼──────────────────────────────────┐
│                        Service Layer                               │
│  ┌────────────────┐  ┌─────────────────┐  ┌──────────────────┐    │
│  │  IWsusService  │  │ IDatabaseService │  │ IHealthService   │    │
│  │ (operations,   │  │ (SQL queries,    │  │ (diagnostics,    │    │
│  │  sync, cleanup)│  │  maintenance)    │  │  auto-repair)    │    │
│  └────────┬───────┘  └────────┬────────┘  └────────┬─────────┘    │
│  ┌────────┴───────┐  ┌────────┴────────┐  ┌────────┴─────────┐    │
│  │ IServiceMgr    │  │ IFirewallService │  │ ISettingsService │    │
│  │ (Win services: │  │ (netsh / rules   │  │ (JSON persist    │    │
│  │  SQL/WSUS/IIS) │  │  8530, 8531)     │  │  APPDATA)        │    │
│  └────────┬───────┘  └────────┬────────┘  └────────┬─────────┘    │
└───────────┼───────────────────┼───────────────────┼───────────────┘
            │                   │                   │
┌───────────┼───────────────────┼───────────────────┼───────────────┐
│                     Infrastructure Layer                           │
│  ┌────────▼───────┐  ┌────────▼────────┐  ┌───────▼──────────┐   │
│  │  ProcessRunner │  │  SqlHelper       │  │  FileSystem      │   │
│  │  (wsusutil,    │  │  (Microsoft.Data │  │  (C:\WSUS\,      │   │
│  │   netsh, sc)   │  │   .SqlClient)    │  │  content, logs)  │   │
│  └────────────────┘  └─────────────────┘  └──────────────────┘   │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │  WSUS Administration Shim  (Process-based isolation)         │  │
│  │  Spawns a .NET Framework helper EXE when WSUS COM API needed │  │
│  └──────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────┘
            │
┌───────────▼────────────────────────────────────────────────────────┐
│                     External Systems                               │
│   SQL Server Express (SUSDB)   WSUS Windows Service (WsusService) │
│   IIS (port 8530/8531)         Windows Firewall  Windows SCM      │
└────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Typical Implementation |
|-----------|----------------|------------------------|
| `MainWindow` (View) | XAML layout only, no logic | WPF Window with zero code-behind logic |
| `MainViewModel` | All UI state, commands, operation orchestration | CommunityToolkit.Mvvm 8.4, `[ObservableProperty]`, `[RelayCommand]` |
| `IWsusService` | WSUS-level operations: sync, cleanup, approve, export/import | C# class using `ProcessRunner` for wsusutil, direct SQL for DB ops |
| `IDatabaseService` | SQL operations against SUSDB: size check, index rebuild, shrink, cleanup queries | `Microsoft.Data.SqlClient` with async methods |
| `IHealthService` | Run diagnostics, detect problems, auto-repair | Orchestrates service/firewall/permissions checks |
| `IWindowsServiceManager` | Start/stop/status for SQL Server, WSUS, IIS services | `System.ServiceProcess.ServiceController` |
| `IFirewallService` | Check and configure firewall rules for 8530/8531 | `ProcessRunner` wrapping `netsh advfirewall` |
| `ISettingsService` | Persist/load settings JSON to `%APPDATA%\WsusManager\settings.json` | `System.Text.Json` |
| `ILogService` | Structured file logging to `C:\WSUS\Logs\` | Serilog with file sink |
| `ProcessRunner` | Launch external processes with captured stdout/stderr | `System.Diagnostics.Process` with `async` stream reading |
| `SqlHelper` | SQL connection factory, query execution, sysadmin checks | `Microsoft.Data.SqlClient` connection pooling |
| `WsusApiShim` (optional) | Bridge to `Microsoft.UpdateServices.Administration` COM API | Separate .NET Framework 4.8 helper process, communicates over stdin/stdout JSON |

---

## The WSUS COM API Problem

**Confidence: HIGH** — confirmed via community forum at social.technet.microsoft.com.

`Microsoft.UpdateServices.Administration` is a .NET Framework 4.x COM-interop assembly. It **does not load in .NET 9** (modern .NET). There are no plans from Microsoft to update it.

**Implication:** Any operation that uses `IUpdateServer`, `IUpdateApproval`, etc. requires a strategy.

**Recommended strategy: Bypass the WSUS COM API entirely.**

The existing PowerShell v3 codebase already demonstrates this is viable. Nearly all operations in the current v3.8.x codebase use:
1. Direct SUSDB SQL queries (most maintenance, cleanup, index operations)
2. `wsusutil.exe` via shell (export, import, reset, checkhealth)
3. `WsusServerCleanup` via the built-in WSUS API through PowerShell (which runs in .NET Framework)

For v4.0 in .NET 9, use the same two approaches natively:
- SQL queries via `Microsoft.Data.SqlClient` for all database operations
- `ProcessRunner` wrapping `wsusutil.exe` for export/import/reset/checkhealth
- Auto-approve operations: call `wsusutil.exe approveall` or use stored procedures in SUSDB

**If COM API access is truly required** (e.g., auto-approval with granular classification control), use the **WsusApiShim** pattern: a tiny separate .NET Framework 4.8 EXE that accepts JSON over stdin, calls the COM API, and returns JSON over stdout. The main .NET 9 app spawns it via `ProcessRunner`. This isolates the .NET Framework dependency completely and keeps the main app on .NET 9.

---

## Recommended Project Structure

```
WsusManager/
├── src/
│   ├── WsusManager.App/              # WPF application entry point
│   │   ├── App.xaml                  # Application definition (no StartupUri)
│   │   ├── App.xaml.cs               # DI host setup, startup
│   │   ├── Program.cs                # [STAThread] Main() bootstrapper
│   │   ├── Views/
│   │   │   ├── MainWindow.xaml       # Main application window (XAML only)
│   │   │   ├── MainWindow.xaml.cs    # Constructor only (DataContext = ViewModel)
│   │   │   └── Dialogs/              # Modal dialogs (Settings, Export, Restore, etc.)
│   │   ├── ViewModels/
│   │   │   ├── MainViewModel.cs      # Primary ViewModel (dashboard + operation control)
│   │   │   └── Dialogs/              # Per-dialog ViewModels
│   │   └── Converters/               # IValueConverter implementations
│   │
│   └── WsusManager.Core/             # Business logic library (no WPF dependency)
│       ├── Services/
│       │   ├── Interfaces/           # IWsusService, IDatabaseService, etc.
│       │   ├── WsusService.cs        # WSUS operations via wsusutil + SQL
│       │   ├── DatabaseService.cs    # SQL Server / SUSDB operations
│       │   ├── HealthService.cs      # Diagnostics and auto-repair
│       │   ├── WindowsServiceManager.cs
│       │   ├── FirewallService.cs
│       │   └── SettingsService.cs
│       ├── Infrastructure/
│       │   ├── ProcessRunner.cs      # External process execution (async)
│       │   ├── SqlHelper.cs          # SqlClient connection + query helpers
│       │   └── FileSystemHelper.cs   # Path validation, directory helpers
│       ├── Models/
│       │   ├── AppSettings.cs        # Settings data model (JSON serializable)
│       │   ├── WsusHealthResult.cs   # Health check result model
│       │   ├── DatabaseStats.cs      # DB size, update counts, etc.
│       │   └── OperationResult.cs    # Generic operation result (success/failure/output)
│       └── Logging/
│           └── LogService.cs         # Serilog wrapper with C:\WSUS\Logs\ file sink
│
├── tests/
│   └── WsusManager.Tests/            # xUnit test project
│       ├── Services/                 # Unit tests per service
│       ├── Infrastructure/           # ProcessRunner, SqlHelper tests
│       └── ViewModels/               # ViewModel unit tests
│
├── tools/
│   └── WsusManager.ApiShim/          # Optional: .NET Framework 4.8 helper
│       └── Program.cs                # Reads JSON stdin, calls WSUS COM API
│
└── WsusManager.sln
```

### Structure Rationale

- **WsusManager.App vs WsusManager.Core:** Separating WPF from business logic enables unit testing all services without a WPF runtime. The Core library has no WPF dependency — only .NET Standard 2.1 / .NET 9 compatible libraries.
- **Services/Interfaces/:** All services behind interfaces. ViewModels only see interfaces, never concrete implementations. This enables mocking in tests.
- **Infrastructure/:** Low-level system calls (process spawning, SQL, filesystem) isolated from business logic. Easy to swap implementations.
- **Models/:** Plain data objects with no behavior. Serializable to/from JSON. ViewModel observability happens in the ViewModel, not the model.
- **tools/WsusManager.ApiShim/:** Only built if COM API operations are required. Optional deployment artifact (not required for single-EXE distribution if not needed).

---

## Architectural Patterns

### Pattern 1: Generic Host + Constructor Injection

**What:** Use `Microsoft.Extensions.Hosting` `Host.CreateApplicationBuilder()` as the DI/logging/config container. Wire `MainWindow` and `MainViewModel` through the DI container so all service dependencies are injected automatically.

**When to use:** Always — this is the modern .NET 9 WPF startup pattern.

**Trade-offs:** Slightly more startup ceremony than `new App()`, but gains unified DI, structured logging (via `ILogger<T>`), and configuration (`appsettings.json`) for free.

**Example:**
```csharp
// Program.cs
[STAThread]
public static void Main(string[] args)
{
    var builder = Host.CreateApplicationBuilder(args);

    // Services
    builder.Services.AddSingleton<ISettingsService, SettingsService>();
    builder.Services.AddSingleton<ILogService, LogService>();
    builder.Services.AddSingleton<SqlHelper>();
    builder.Services.AddSingleton<ProcessRunner>();
    builder.Services.AddSingleton<IDatabaseService, DatabaseService>();
    builder.Services.AddSingleton<IWindowsServiceManager, WindowsServiceManager>();
    builder.Services.AddSingleton<IFirewallService, FirewallService>();
    builder.Services.AddSingleton<IHealthService, HealthService>();
    builder.Services.AddSingleton<IWsusService, WsusService>();

    // ViewModels
    builder.Services.AddSingleton<MainViewModel>();

    // Views
    builder.Services.AddSingleton<MainWindow>();

    // Add Serilog
    builder.Services.AddLogging(lb =>
        lb.AddSerilog(new LoggerConfiguration()
            .WriteTo.File(@"C:\WSUS\Logs\WsusManager-.log", rollingInterval: RollingInterval.Day)
            .CreateLogger()));

    var host = builder.Build();

    var app = new Application();
    var window = host.Services.GetRequiredService<MainWindow>();
    app.Run(window);
}
```

### Pattern 2: Async Command Pattern with CancellationToken

**What:** All long-running operations in the ViewModel use `async Task` RelayCommands. Each operation accepts a `CancellationToken` from a shared `CancellationTokenSource` that the Cancel button triggers. Progress is reported via `IProgress<OperationProgress>`.

**When to use:** Every operation that runs for more than ~200ms (health check, cleanup, sync, export, install).

**Trade-offs:** Requires discipline to pass `CancellationToken` through all service method calls. The payoff is that cancellation works at every layer without killing the process.

**Example:**
```csharp
// MainViewModel.cs
public partial class MainViewModel : ObservableObject
{
    private CancellationTokenSource? _operationCts;

    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(RunHealthCheckCommand))]
    [NotifyCanExecuteChangedFor(nameof(RunDeepCleanupCommand))]
    private bool _isOperationRunning;

    [ObservableProperty]
    private string _logOutput = string.Empty;

    [RelayCommand(CanExecute = nameof(CanRunOperation))]
    private async Task RunHealthCheckAsync()
    {
        _operationCts = new CancellationTokenSource();
        IsOperationRunning = true;

        var progress = new Progress<string>(line =>
            LogOutput += line + Environment.NewLine);

        try
        {
            await _healthService.RunDiagnosticsAsync(progress, _operationCts.Token);
        }
        catch (OperationCanceledException)
        {
            LogOutput += "[Cancelled]" + Environment.NewLine;
        }
        finally
        {
            IsOperationRunning = false;
            _operationCts.Dispose();
            _operationCts = null;
        }
    }

    [RelayCommand]
    private void CancelOperation() => _operationCts?.Cancel();

    private bool CanRunOperation() => !IsOperationRunning;
}
```

### Pattern 3: Service Methods Return `OperationResult`

**What:** Every service method returns `OperationResult` (or `OperationResult<T>`) rather than throwing exceptions for expected failure conditions. Exceptions are still thrown for programming errors (null args, etc.) but operational failures (SQL Server down, service not found) return a structured result.

**When to use:** All public service methods.

**Trade-offs:** More verbose than throw-on-failure, but prevents exception-based control flow and makes caller logic cleaner.

**Example:**
```csharp
public record OperationResult(bool Success, string Message, Exception? Exception = null)
{
    public static OperationResult Ok(string message = "Success") => new(true, message);
    public static OperationResult Fail(string message, Exception? ex = null) => new(false, message, ex);
}

// In HealthService
public async Task<OperationResult> CheckSqlConnectivityAsync(CancellationToken ct)
{
    try
    {
        await _sqlHelper.TestConnectionAsync(ct);
        return OperationResult.Ok("SQL Server connection verified");
    }
    catch (SqlException ex)
    {
        return OperationResult.Fail($"SQL Server unreachable: {ex.Message}", ex);
    }
}
```

### Pattern 4: ProcessRunner for External Commands

**What:** All shell command execution is centralized in `ProcessRunner`. It spawns processes with redirected stdout/stderr, returns output line-by-line via `IAsyncEnumerable<string>` or an `IProgress<string>` callback, and respects `CancellationToken` (kills the process on cancellation).

**When to use:** `wsusutil.exe`, `netsh.exe`, `sc.exe`, `wuauclt.exe`, any shell command.

**Trade-offs:** All process output flows through one path — easier to log, test, and cancel. Slightly higher overhead than direct calls but negligible for admin tools.

**Example:**
```csharp
public class ProcessRunner
{
    public async Task<ProcessResult> RunAsync(
        string executable,
        string arguments,
        IProgress<string>? progress = null,
        CancellationToken ct = default)
    {
        using var proc = new Process
        {
            StartInfo = new ProcessStartInfo(executable, arguments)
            {
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            }
        };

        var outputLines = new List<string>();
        proc.OutputDataReceived += (_, e) =>
        {
            if (e.Data is null) return;
            outputLines.Add(e.Data);
            progress?.Report(e.Data);
        };
        proc.ErrorDataReceived += (_, e) =>
        {
            if (e.Data is null) return;
            outputLines.Add($"[ERR] {e.Data}");
            progress?.Report($"[ERR] {e.Data}");
        };

        proc.Start();
        proc.BeginOutputReadLine();
        proc.BeginErrorReadLine();

        await proc.WaitForExitAsync(ct);

        return new ProcessResult(proc.ExitCode, outputLines);
    }
}
```

### Pattern 5: Dashboard State via Polling + Dispatcher-Free Updates

**What:** A background `PeriodicTimer` (30-second interval) calls `RefreshDashboardAsync()` on the ViewModel. Because the ViewModel uses `[ObservableProperty]` from CommunityToolkit.Mvvm, property changes automatically marshal to the UI thread via the synchronization context captured at construction time. No explicit `Dispatcher.Invoke` is needed.

**When to use:** Auto-refresh of WSUS service status, DB size, sync date, update counts.

**Trade-offs:** `PeriodicTimer` (introduced in .NET 6) is allocation-free and cancellation-aware. No timer cleanup bugs.

**Example:**
```csharp
// MainViewModel.cs constructor or OnActivated
private async Task StartDashboardRefreshAsync(CancellationToken ct)
{
    using var timer = new PeriodicTimer(TimeSpan.FromSeconds(30));
    while (await timer.WaitForNextTickAsync(ct))
    {
        await RefreshDashboardAsync(ct);
    }
}

// Properties update automatically on UI thread (no Dispatcher.Invoke needed)
[ObservableProperty]
private string _databaseSize = "—";

[ObservableProperty]
private string _wsusServiceStatus = "Unknown";
```

---

## Data Flow

### Operation Flow (e.g., Deep Cleanup)

```
[User clicks "Deep Cleanup"]
    ↓
MainViewModel.RunDeepCleanupCommand
    ├── Sets IsOperationRunning = true (disables all commands via CanExecute)
    ├── Creates new CancellationTokenSource
    ├── Creates Progress<string> that appends to LogOutput property
    ↓
IWsusService.RunDeepCleanupAsync(progress, cancellationToken)
    ├── Step 1: IDatabaseService.DeclineSupersededUpdatesAsync(ct)
    │       └── SqlHelper.ExecuteNonQueryAsync(SUSDB query, ct)
    ├── Step 2: IDatabaseService.PurgeDeclinedUpdatesAsync(progress, ct)
    │       └── SqlHelper.ExecuteReaderAsync → batched deletes, reports per batch
    ├── Step 3: IDatabaseService.RebuildIndexesAsync(progress, ct)
    │       └── SqlHelper.ExecuteNonQueryAsync(sp_WsusDbIndexMaintenance, ct)
    └── Step 4: IDatabaseService.ShrinkDatabaseAsync(ct)
            └── SqlHelper.ExecuteNonQueryAsync(DBCC SHRINKDATABASE, ct)
    ↓
Returns OperationResult
    ↓
MainViewModel finally block:
    ├── Sets IsOperationRunning = false (re-enables commands)
    └── Reports final status to LogOutput
```

### Dashboard Refresh Flow

```
PeriodicTimer (30s tick)
    ↓
MainViewModel.RefreshDashboardAsync()
    ├── IWindowsServiceManager.GetServiceStatusAsync("WsusService") → StatusText
    ├── IWindowsServiceManager.GetServiceStatusAsync("MSSQL$SQLEXPRESS") → StatusText
    ├── IDatabaseService.GetDatabaseSizeAsync() → string "4.2 GB / 10 GB limit"
    ├── IWsusService.GetLastSyncDateAsync() → DateTime? → string
    └── IWsusService.GetPendingUpdateCountAsync() → int
    ↓
[ObservableProperty] setters fire on captured SynchronizationContext
    ↓
WPF data binding updates UI labels — no Dispatcher.Invoke needed
```

### Settings Flow

```
App startup
    ↓
ISettingsService.LoadAsync()
    └── System.Text.Json deserialize %APPDATA%\WsusManager\settings.json
    ↓
MainViewModel receives AppSettings via DI constructor
    ↓
User changes setting in Settings dialog
    ↓
SettingsViewModel updates AppSettings model
    ↓
ISettingsService.SaveAsync(settings)
    └── System.Text.Json serialize → write file
    ↓
MainViewModel observes change (via IOptions<AppSettings> or direct property)
```

---

## Build Order (Phase Dependencies)

The component dependency graph determines what must be built before what:

```
1. Infrastructure (no dependencies)
   ├── ProcessRunner
   ├── SqlHelper
   └── FileSystemHelper

2. Models (no dependencies)
   ├── AppSettings
   ├── OperationResult
   ├── WsusHealthResult
   └── DatabaseStats

3. Core Services (depends on Infrastructure + Models)
   ├── ISettingsService / SettingsService   ← needed by all other services
   ├── ILogService / LogService             ← needed by all other services
   ├── IWindowsServiceManager               ← needed by HealthService
   ├── IFirewallService                     ← needed by HealthService
   ├── IDatabaseService                     ← needed by WsusService, HealthService
   ├── IWsusService                         ← depends on DatabaseService
   └── IHealthService                       ← depends on ServiceManager, Firewall, Database

4. ViewModel (depends on all Services)
   └── MainViewModel + Dialog ViewModels

5. Views (depends on ViewModels)
   ├── MainWindow.xaml
   └── Dialogs/

6. App Entry Point (wires everything together)
   └── Program.cs (DI registration, host startup)
```

**Recommended phase build sequence:**
- **Phase 1:** Infrastructure + Models + SettingsService + LogService (foundation — fully testable, no WPF)
- **Phase 2:** WindowsServiceManager + FirewallService + DatabaseService (core system integrations)
- **Phase 3:** WsusService + HealthService (WSUS-specific logic — builds on Phase 2)
- **Phase 4:** MainViewModel + DI host wiring (ties all services together)
- **Phase 5:** MainWindow XAML + data bindings + dashboard (visible product)
- **Phase 6:** Dialog ViewModels + Views (Export, Restore, Settings, Install)
- **Phase 7:** ScheduledTask, GPO deployment, air-gap workflows

---

## Anti-Patterns

### Anti-Pattern 1: Dispatcher.Invoke in ViewModels or Services

**What people do:** Call `Application.Current.Dispatcher.Invoke()` to update UI from service code.

**Why it's wrong:** It creates a hard dependency on the WPF runtime in the Core library, breaks unit testing, and is the root cause of every threading bug in the PowerShell v3 codebase. The 12 documented PowerShell anti-patterns in CLAUDE.md are largely symptoms of not having this boundary.

**Do this instead:** Properties on `ObservableObject` (CommunityToolkit.Mvvm) automatically marshal to the UI thread. Services report progress via `IProgress<T>` — the `Progress<T>` class captures the synchronization context at construction (which is the UI thread if created in a ViewModel). No dispatcher calls needed anywhere in the Core library.

### Anti-Pattern 2: Shared Mutable State Between Operations

**What people do:** Use class-level `bool _operationRunning` flags and update them from multiple concurrent paths.

**Why it's wrong:** Race conditions when async operations complete out of order. This was PowerShell anti-pattern #12 (operation status flag not resetting).

**Do this instead:** Use `[ObservableProperty] private bool _isOperationRunning` as the single source of truth. `[NotifyCanExecuteChangedFor]` automatically disables all operation commands when it is `true`. The `finally` block in every command handler resets it — there is only one place to forget.

### Anti-Pattern 3: Large Monolithic ViewModel

**What people do:** Put all operations and all UI state into one 3000-line ViewModel (exactly what PowerShell WsusManagementGui.ps1 became).

**Why it's wrong:** Impossible to test, hard to reason about, every change has side effects.

**Do this instead:** `MainViewModel` owns only: dashboard state, operation running state, log output, and navigation state. Each dialog (Settings, Export, Install, etc.) gets its own dialog ViewModel. Operations that require complex parameter input go to a dialog ViewModel that is shown, collects input, and returns a result — then `MainViewModel` calls the service with that result.

### Anti-Pattern 4: ProcessRunner Without Cancellation Propagation

**What people do:** Start a process with `proc.Start()` and then call `CancellationToken.Register(() => proc.Kill())` as an afterthought.

**Why it's wrong:** The process may have already exited by the time `Kill()` is called. On Windows Server, `Kill()` without `entireProcessTree: true` leaves orphan child processes. `WaitForExitAsync` does not respect cancellation by default before .NET 6.

**Do this instead:** Use `proc.WaitForExitAsync(ct)` (available since .NET 5) which respects cancellation. On cancellation, call `proc.Kill(entireProcessTree: true)` inside the `catch (OperationCanceledException)` block.

### Anti-Pattern 5: Accessing SUSDB Directly in Every Service

**What people do:** Scatter `new SqlConnection(connStr)` calls throughout service classes.

**Why it's wrong:** Connection string is duplicated, error handling is inconsistent, sysadmin checks are missed, testing requires a real SQL Server.

**Do this instead:** All SQL access flows through `SqlHelper`. It owns the connection string (read from settings), provides async `ExecuteNonQueryAsync`, `ExecuteScalarAsync`, `ExecuteReaderAsync`, and `TestConnectionAsync` helpers, and checks the sysadmin permission once via `Assert-SqlSysadmin` equivalent. Services call `_sqlHelper.ExecuteNonQueryAsync(...)` — they never construct `SqlConnection` directly.

---

## Integration Points

### External Systems

| System | Integration Pattern | Notes |
|--------|---------------------|-------|
| SQL Server Express (SUSDB) | `Microsoft.Data.SqlClient` async ADO.NET | Connection string: `Data Source=localhost\SQLEXPRESS;Initial Catalog=SUSDB;Integrated Security=true;TrustServerCertificate=true` |
| WSUS Windows Service | `System.ServiceProcess.ServiceController` | Re-query status every time (no `Refresh()` — not available on ServiceController in .NET 9 the same way as .NET Framework) |
| IIS (W3SVC) | `ServiceController` + optional `ProcessRunner` wrapping `appcmd.exe` | Only for start/stop, not full IIS management |
| Windows Firewall | `ProcessRunner` + `netsh advfirewall firewall` | `netsh` is present on all Windows Server 2019+ targets |
| `wsusutil.exe` | `ProcessRunner` | Path: `%ProgramFiles%\Update Services\Tools\wsusutil.exe` |
| Windows Task Scheduler | `Microsoft.Win32.TaskScheduler` (TaskScheduler NuGet) or `ProcessRunner` + `schtasks.exe` | NuGet library preferred for type safety |
| Windows Event Log | `Microsoft.Extensions.Logging.EventLog` (built into generic host on Windows) | Already provided by generic host |
| File System (C:\WSUS\) | `System.IO` directly | Validate paths with `Path.GetFullPath` + prefix check to prevent traversal |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| ViewModel to Service | Constructor-injected interface, `async Task` calls | ViewModel never knows concrete types |
| Service to Infrastructure | Constructor-injected `SqlHelper` / `ProcessRunner` | Infrastructure classes are concrete (no interface needed unless testing requires mocking) |
| ViewModel to ViewModel (Dialogs) | Dialog ViewModel returned as result; `MainViewModel` invokes service after dialog completes | No shared state between dialog and main ViewModel |
| Main App to WsusApiShim (if used) | `ProcessRunner` spawning a separate process, JSON over stdin/stdout | Only needed if WSUS COM API auto-approval proves necessary |

---

## Single EXE Publication

The application publishes as a self-contained single-file EXE using .NET 9's `PublishSingleFile` + `SelfContained` options:

```xml
<!-- WsusManager.App.csproj -->
<PropertyGroup>
  <PublishSingleFile>true</PublishSingleFile>
  <SelfContained>true</SelfContained>
  <RuntimeIdentifier>win-x64</RuntimeIdentifier>
  <PublishReadyToRun>true</PublishReadyToRun>
  <IncludeNativeLibrariesForSelfExtract>true</IncludeNativeLibrariesForSelfExtract>
</PropertyGroup>
```

**Known .NET 9 regression** (confirmed in GitHub dotnet/sdk issue #43461): Some WPF assemblies (`PresentationCore.dll`, `PresentationFramework*.dll`) may be missing from self-contained publish output when targeting `net9.0-windows`. **Mitigation:** Pin to .NET 8 for the first production release and track the fix for .NET 9.1+. The architecture does not change — only the target framework moniker.

**EXE size:** Expected 15-25MB self-contained (WPF runtime embedded). The PowerShell version was 280KB + 180KB modules = ~460KB, but required PowerShell runtime (~100MB). The C# EXE is larger in bytes but has zero external dependencies on the target server.

---

## Scaling Considerations

This is a single-server admin tool, not a distributed application. "Scaling" here means managing complexity as the codebase grows.

| Concern | Approach |
|---------|----------|
| Adding new operations | Add method to appropriate service interface → implement → add command to ViewModel. The DI wiring in `Program.cs` is the only change needed. |
| Adding new dialogs | New dialog ViewModel in `ViewModels/Dialogs/`, new XAML in `Views/Dialogs/`. Register dialog ViewModel in DI if it needs services. |
| Multi-server support (future) | Currently out of scope. Architecture supports it: replace `ISettingsService` single-server config with a list; `IWsusService` takes a server connection parameter. ViewModel holds the active server context. |
| Test coverage | `WsusManager.Core` has no WPF dependency → all service code is unit-testable with `xUnit` + mocked interfaces. ViewModel tests use `CommunityToolkit.Mvvm`'s `ObservableObject` which works in test contexts. |

---

## Sources

- [CommunityToolkit.Mvvm IoC documentation](https://learn.microsoft.com/en-us/dotnet/communitytoolkit/mvvm/ioc) — HIGH confidence
- [.NET Community Toolkit 8.4 announcement](https://devblogs.microsoft.com/dotnet/announcing-the-dotnet-community-toolkit-840/) — HIGH confidence (partial properties, analyzers)
- [.NET Generic Host documentation](https://learn.microsoft.com/en-us/dotnet/core/extensions/generic-host) — HIGH confidence
- [Task-based Asynchronous Pattern (TAP)](https://learn.microsoft.com/en-us/dotnet/standard/asynchronous-programming-patterns/task-based-asynchronous-pattern-tap) — HIGH confidence
- [Async patterns for MVVM commands](https://learn.microsoft.com/en-us/archive/msdn-magazine/2014/april/async-programming-patterns-for-asynchronous-mvvm-applications-commands) — MEDIUM confidence (2014 article, patterns still valid)
- [Microsoft.Data.SqlClient async programming](https://learn.microsoft.com/en-us/sql/connect/ado-net/asynchronous-programming) — HIGH confidence
- [Single file deployment overview](https://learn.microsoft.com/en-us/dotnet/core/deploying/single-file/overview) — HIGH confidence
- [.NET 9 self-contained publish regression](https://github.com/dotnet/sdk/issues/43461) — HIGH confidence (confirmed GitHub issue)
- WSUS COM API .NET Core incompatibility — MEDIUM confidence (community forum, no official Microsoft statement found; architecture avoids this entirely)
- PowerShell v3.8.x source patterns — HIGH confidence (existing codebase, 12 documented anti-patterns in CLAUDE.md)

---

*Architecture research for: C#/.NET WPF WSUS management administration tool*
*Researched: 2026-02-19*
