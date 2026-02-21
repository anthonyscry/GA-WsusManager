# Architecture Documentation

This document describes the architecture of WSUS Manager v4.x (C# WPF application), including design decisions, component relationships, and technical choices.

## Overview

WSUS Manager is a Windows desktop application built with C#, WPF, and .NET 8. It provides a modern GUI for managing Windows Server Update Services (WSUS) with support for air-gapped networks.

### Key Characteristics

- **Architecture Pattern:** MVVM (Model-View-ViewModel) with CommunityToolkit.Mvvm
- **Dependency Injection:** Microsoft.Extensions.DependencyInjection
- **UI Framework:** WPF (Windows Presentation Foundation)
- **Target Framework:** .NET 8.0
- **Testing Framework:** xUnit
- **Packaging:** Single-file EXE (self-contained)

### Design Goals

1. **Separation of Concerns:** Business logic separate from UI
2. **Testability:** All logic unit-testable without UI dependencies
3. **Maintainability:** Clear structure, consistent patterns
4. **Performance:** Responsive UI, minimal overhead
5. **Simplicity:** Avoid over-engineering, pragmatic choices

## Architecture Diagram

```
+-------------------------------------------------------------------------+
|                        WsusManager.App                           |
|                        (WPF Application)                         |
+-------------------------------------------------------------------------+
|                                                                   |
|  +------------------------------------------------------------------+ |
|  |                     Views (XAML)                           | |
|  |  +------------+  +------------+  +------------+          | |
|  |  | MainWindow |  |  Dialogs   |  |   Panels   |          | |
|  |  +------------+  +------------+  +------------+          | |
|  +------------------------------------------------------------------+ |
|                              |                                   |
|                              v                                   |
|  +------------------------------------------------------------------+ |
|  |                  ViewModels (MVVM)                         | |
|  |  +--------------+  +--------------+  +--------------+   | |
|  |  |MainViewModel |  |SettingsVM    |  |DiagnosticsVM |   | |
|  |  +--------------+  +--------------+  +--------------+   | |
|  +------------------------------------------------------------------+ |
|                              |                                   |
|                              v                                   |
|  +------------------------------------------------------------------+ |
|  |                Service Layer (DI Container)                | |
|  |  +--------------+  +--------------+  +--------------+   | |
|  |  |HealthService |  |DatabaseSvc   |  |WsusService   |   | |
|  |  +--------------+  +--------------+  +--------------+   | |
|  +------------------------------------------------------------------+ |
|                                                                   |
+-------------------------------------------------------------------------+
                              |
                              v
+-------------------------------------------------------------------------+
|                        WsusManager.Core                          |
|                        (Business Logic)                          |
+-------------------------------------------------------------------------+
|                                                                   |
|  +------------------------------------------------------------------+ |
|  |                     Services                                | |
|  |  - IHealthService       - IDatabaseService                 | |
|  |  - IWsusService         - IServiceManager                  | |
|  |  - IFirewallService     - IClientManagementService         | |
|  +------------------------------------------------------------------+ |
|                                                                   |
|  +------------------------------------------------------------------+ |
|  |                      Models                                 | |
|  |  - HealthCheckResult    - DatabaseBackupInfo               | |
|  |  - WsusClient           - SyncProfile                      | |
|  +------------------------------------------------------------------+ |
|                                                                   |
|  +------------------------------------------------------------------+ |
|  |                  Infrastructure                             | |
|  |  - Logging (ILogger)    - Admin checks                  | |
|  |  - Path validation       - Process execution             | |
|  +------------------------------------------------------------------+ |
|                                                                   |
+-------------------------------------------------------------------------+
                              |
                              v
                        +-----------+
                        |  External |
                        | Systems   |
                        +-----------+
```

## Component Layers

### Presentation Layer (WsusManager.App)

**Responsibility:** UI rendering and user interaction

**Components:**
- **Views:** XAML files defining UI layout (MainWindow.xaml, dialogs, panels)
- **ViewModels:** MVVM view models with commands and observable properties
- **Services:** App-specific services (ThemeService, SettingsService)

**Key Technologies:**
- WPF XAML for UI definition
- Data binding for UI updates
- CommunityToolkit.Mvvm for MVVM helpers
- Async/await for non-blocking operations

**Example: MainViewModel**

```csharp
public partial class MainViewModel : ViewModelBase
{
    private readonly IHealthService _healthService;
    private readonly IThemeService _themeService;

    [ObservableProperty]
    private string _statusMessage = "Ready";

    [RelayCommand(CanExecute = nameof(CanExecuteOperation))]
    private async Task RunDiagnosticsAsync()
    {
        await RunOperationAsync("Diagnostics", async () =>
        {
            var result = await _healthService.CheckHealthAsync(CancellationToken.None);
            return result.IsHealthy;
        });
    }
}
```

### Business Logic Layer (WsusManager.Core)

**Responsibility:** Domain logic and external operations

**Components:**
- **Services:** Business logic interfaces and implementations
- **Models:** Data transfer objects and entities
- **Infrastructure:** Cross-cutting concerns (logging, validation)

**Key Design Principles:**
- Interface-based design (dependency inversion)
- Single responsibility (each service does one thing well)
- No UI dependencies (testable without WPF)

**Example: HealthService**

```csharp
internal class HealthService : IHealthService
{
    private readonly ILogger<HealthService> _logger;
    private readonly IDbConnectionFactory _connectionFactory;
    private readonly IServiceManager _serviceManager;

    public async Task<HealthCheckResult> CheckHealthAsync(CancellationToken cancellationToken)
    {
        // Business logic: check services, database, firewall, permissions
        var services = await _serviceManager.GetStatusAsync(ServiceType.Wsus);
        var db = await CheckDatabaseAsync(cancellationToken);
        // ...
        return new HealthCheckResult { IsHealthy = allChecksPass };
    }
}
```

### External Integration Layer

**Responsibility:** Communication with external systems

**Integrations:**
- **SQL Server:** Database operations via ADO.NET
- **WinRM:** Remote PowerShell execution
- **Windows Services:** Service management via ServiceController
- **File System:** Export/import operations, log files

**Pattern:** Adapter pattern - external systems wrapped in service interfaces

## MVVM Pattern

WSUS Manager uses the Model-View-ViewModel pattern for clear separation of concerns:

### Model

**What:** Data entities and business logic

**Location:** `WsusManager.Core/Models/`

**Examples:**
```csharp
public class HealthCheckResult
{
    public bool IsHealthy { get; set; }
    public ServiceStatus Services { get; set; }
    public DatabaseStatus Database { get; set; }
}
```

### View

**What:** UI definition (no code-behind logic)

**Location:** `WsusManager.App/Views/`

**Example (XAML):**
```xml
<Button Command="{Binding RunDiagnosticsCommand}"
        Content="Run Diagnostics"
        IsEnabled="{Binding IsOperationRunning, Converter={StaticResource InverseBoolConverter}}" />
```

### ViewModel

**What:** Presentation logic and state

**Location:** `WsusManager.App/ViewModels/`

**Responsibilities:**
- Expose data as observable properties
- Implement commands for user actions
- Handle UI logic (navigation, dialogs, progress)

**Example:**
```csharp
public partial class DiagnosticsViewModel : ViewModelBase
{
    [ObservableProperty]
    private bool _isRunning;

    [RelayCommand]
    private async Task RunAsync()
    {
        IsRunning = true;
        try
        {
            await _healthService.CheckHealthAsync(CancellationToken.None);
        }
        finally
        {
            IsRunning = false;
        }
    }
}
```

**Key Benefits:**
- UI is dumb (XAML only)
- ViewModel is testable (no WPF dependencies)
- Model is reusable (across UIs)

## Dependency Injection

WSUS Manager uses Microsoft.Extensions.DependencyInjection for IoC (Inversion of Control).

### Service Registration

**Location:** `WsusManager.App/ServiceCollectionExtensions.cs`

```csharp
public static IServiceCollection AddAppServices(this IServiceCollection services)
{
    // Core services
    services.AddTransient<IHealthService, HealthService>();
    services.AddTransient<IDatabaseService, DatabaseService>();
    services.AddTransient<IWsusService, WsusService>();

    // App services
    services.AddSingleton<IThemeService, ThemeService>();
    services.AddSingleton<ISettingsService, SettingsService>();

    // ViewModels
    services.AddTransient<MainViewModel>();
    services.AddTransient<DiagnosticsViewModel>();

    return services;
}
```

### Service Lifetimes

- **Transient:** New instance each time (stateless services)
- **Scoped:** One instance per scope (not used currently)
- **Singleton:** One instance per app lifetime (stateful services like ThemeService)

### Constructor Injection

Services injected via constructors:

```csharp
public class MainViewModel
{
    private readonly IHealthService _healthService;
    private readonly IThemeService _themeService;

    public MainViewModel(IHealthService healthService, IThemeService themeService)
    {
        _healthService = healthService;
        _themeService = themeService;
    }
}
```

**Benefits:**
- Loose coupling (depends on interfaces, not implementations)
- Testability (easily mock dependencies)
- Maintainability (clear dependencies)

## Async/Await Pattern

WSUS Manager uses async/await throughout for responsive UI.

### ConfigureAwait Guidelines

**Library code (WsusManager.Core):**
```csharp
public async Task<HealthCheckResult> CheckHealthAsync(CancellationToken cancellationToken)
{
    await Task.Delay(1000, cancellationToken).ConfigureAwait(false);
    // ... no need for dispatcher
}
```

**UI code (WsusManager.App):**
```csharp
[RelayCommand]
private async Task RunDiagnosticsAsync()
{
    var result = await _healthService.CheckHealthAsync(CancellationToken.None);
    // Back on UI thread automatically, no ConfigureAwait(true) needed
}
```

**Rule:** Library code uses `ConfigureAwait(false)`, UI code uses default (true).

### Operation Runner Pattern

All operations go through `RunOperationAsync` wrapper:

```csharp
protected async Task<bool> RunOperationAsync(string name, Func<Task<bool>> operation)
{
    IsOperationRunning = true;
    StatusMessage = $"Running {name}...";
    LogPanelExpanded = true;

    try
    {
        var result = await operation();
        StatusMessage = result ? $"{name} completed" : $"{name} failed";
        return result;
    }
    catch (Exception ex)
    {
        StatusMessage = $"{name} error: {ex.Message}";
        return false;
    }
    finally
    {
        IsOperationRunning = false;
        RefreshCanExecute();
    }
}
```

**Benefits:**
- Consistent error handling
- UI state management (busy indicators, log panel)
- User feedback (status messages, banners)

## Data Binding

WPF data binding connects View to ViewModel automatically.

### Binding Modes

- **OneWay:** View displays ViewModel property (read-only)
- **TwoWay:** View and ViewModel sync (editable fields)
- **OneWayToSource:** View updates ViewModel (rare)

### Example

**ViewModel:**
```csharp
[ObservableProperty]
private string _serverName = "localhost";
```

**View:**
```xml
<TextBox Text="{Binding ServerName, UpdateSourceTrigger=PropertyChanged}" />
```

**Generated Property:** CommunityToolkit.Mvvm generates property with INotifyPropertyChanged

### Commands

Commands bind user actions to ViewModel methods:

```xml
<Button Command="{Binding RunDiagnosticsCommand}" Content="Run Diagnostics" />
```

```csharp
[RelayCommand(CanExecute = nameof(CanExecuteOperation))]
private async Task RunDiagnosticsAsync() { ... }
```

**Benefits:**
- No code-behind needed
- Automatic enable/disable via CanExecute
- Type-safe (compile-time checking)

## Logging

WSUS Manager uses `ILogger<T>` from Microsoft.Extensions.Logging.

### Logger Usage

```csharp
public class HealthService
{
    private readonly ILogger<HealthService> _logger;

    public HealthService(ILogger<HealthService> logger)
    {
        _logger = logger;
    }

    public async Task CheckHealthAsync()
    {
        _logger.LogInformation("Starting health check");
        try
        {
            // ... operation ...
            _logger.LogInformation("Health check passed");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Health check failed");
            throw;
        }
    }
}
```

### Log Levels

- **Trace:** Detailed diagnostics (disabled by default)
- **Debug:** Development diagnostics
- **Information:** Normal operation (startup, operations)
- **Warning:** Non-critical issues (retries, workarounds)
- **Error:** Errors that don't stop the app
- **Critical:** Serious failures (crashes, data loss)

### Log Output

Logs written to:
- **Console:** Visual Studio Output window (debug builds)
- **File:** `%APPDATA%\WsusManager\logs\` (release builds)
- **UI:** Log panel in main window

## Theme System

WSUS Manager supports 6 built-in themes (Dark, Light, Blue, Green, Purple, Red).

### Architecture

```
+-------------------------+
|                    ThemeService                         |
|  - LoadTheme(string name)                              |
|  - CurrentTheme (ObservableProperty)                   |
|  - ApplyTheme(ResourceDictionary theme)                |
+-------------------------+
                          |
                          v
+-------------------------+
|                  Theme Resource Dictionaries             |
|  +------------+  +------------+  +------------+        |
|  |Colors.xaml |  |Fonts.xaml  |  |Dark.xaml   |        |
|  +------------+  +------------+  +------------+        |
|  +------------+  +------------+  +------------+        |
|  |Light.xaml  |  |Blue.xaml   |  |Green.xaml  |        |
|  +------------+  +------------+  +------------+        |
+-------------------------+
                          |
                          v
+-------------------------+
|                 XAML DynamicResource                    |
|  <Button Background="{DynamicResource ButtonBrush}" />  |
+-------------------------+
```

### DynamicResource vs StaticResource

- **StaticResource:** Resolved at load time (default, faster)
- **DynamicResource:** Resolved at runtime (required for theme switching)

**Migration:** Phase 16 migrated all theme-related resources from StaticResource to DynamicResource.

## Testing Strategy

WSUS Manager uses xUnit for unit testing with a focus on testable design.

### Test Structure

```
WsusManager.Tests/
+-- Services/           # Service layer tests
|   +-- HealthServiceTests.cs
|   +-- DatabaseServiceTests.cs
|   +-- WsusServiceTests.cs
+-- ViewModels/         # ViewModel tests
|   +-- MainViewModelTests.cs
|   +-- SettingsViewModelTests.cs
+-- Validation/         # Integration/validation tests
    +-- PathValidationTests.cs
```

### Test Patterns

**AAA Pattern (Arrange, Act, Assert):**
```csharp
[Fact]
public async Task ExecuteAsync_WithValidConfig_ReturnsSuccess()
{
    // Arrange
    var mockLogger = new Mock<ILogger<HealthService>>();
    var mockConnection = new Mock<IDbConnection>();
    var service = new HealthService(mockLogger.Object, mockConnection.Object);

    // Act
    var result = await service.CheckHealthAsync(CancellationToken.None);

    // Assert
    Assert.True(result.IsHealthy);
}
```

### Mocking

Uses Moq for mocking dependencies:
```csharp
var mockService = new Mock<IHealthService>();
mockService.Setup(x => x.CheckHealthAsync(It.IsAny<CancellationToken>()))
           .ReturnsAsync(new HealthCheckResult { IsHealthy = true });
```

## Design Decisions

### Why .NET 8?

**Decision:** Target .NET 8 LTS (Long Term Support)

**Rationale:**
- LTS support until 2026-11-10
- Stable and mature (not bleeding edge)
- Better performance than .NET Framework
- Cross-platform (though we target Windows-only)

**Alternatives considered:**
- .NET 9: Too new, not LTS
- .NET 6: Reaching end of support

### Why WPF?

**Decision:** Use WPF (Windows Presentation Foundation)

**Rationale:**
- Native Windows UI (WinForms is dated)
- XAML for declarative UI (easier than WinForms designer)
- Mature platform (stable, well-documented)
- Data binding support (perfect for MVVM)

**Alternatives considered:**
- WinUI 3: Too new, less stable, more complex
- Avalonia: Cross-platform (not needed, adds complexity)
- Console/CLI: Not user-friendly for WSUS admins

### Why MVVM?

**Decision:** MVVM pattern with CommunityToolkit.Mvvm

**Rationale:**
- Separation of concerns (UI separate from logic)
- Testable ViewModels (no UI dependencies)
- CommunityToolkit.Mvvm reduces boilerplate (source generators)
- Industry standard for WPF

**Alternatives considered:**
- Code-behind: Hard to test, mixes concerns
- MVP: Less idiomatic for WPF
- MVC: Not designed for WPF

### Why xUnit?

**Decision:** Use xUnit for testing

**Rationale:**
- Modern and actively maintained
- Better support for parallel tests
- Cleaner syntax than NUnit/MSTest
- Widely used in .NET community

**Alternatives considered:**
- NUnit: Older, less active
- MSTest: Microsoft-specific, less portable

### Why Single-File EXE?

**Decision:** Publish as self-contained single-file EXE

**Rationale:**
- Easy deployment (one file, no install)
- No .NET runtime dependency (embedded)
- Simple for users (double-click to run)
- Reduced support burden (no version conflicts)

**Trade-offs:**
- Larger file size (~15-20 MB vs 280 KB PowerShell EXE)
- Slower first startup (self-extraction)
- Acceptable for desktop application

## Performance Considerations

### Startup Time

**Target:** < 2s cold start, < 500ms warm start

**Optimizations:**
- Lazy-load ViewModels (don't initialize until navigation)
- Async service initialization (don't block UI)
- Minimize assembly load time (single-file EXE)

### Memory Usage

**Target:** < 100 MB steady state

**Optimizations:**
- Use `ObservableCollection` correctly (prevent memory leaks)
- Unsubscribe event handlers in cleanup
- Avoid large object graphs in ViewModels

### UI Responsiveness

**Target:** No UI freezes during operations

**Optimizations:**
- All operations are async (no blocking calls)
- Progress feedback during long operations
- Background thread for heavy work (ConfigureAwait(false) in libraries)

## Security Considerations

### Admin Privileges

**Requirement:** Application must run as Administrator

**Enforcement:**
- App.manifest requests admin level
- Startup check warns if not admin
- Operations fail gracefully with error message

### SQL Injection

**Prevention:**
- Parameterized queries (never concatenate SQL)
- Input validation on all user inputs
- Stored procedures with parameters

### Path Validation

**Prevention:**
- `Test-SafePath` validates paths before use
- `Get-EscapedPath` escapes dangerous characters
- Whitelist approach (only allow safe paths)

## Future Enhancements

Potential architecture improvements for future releases:

- [ ] CLI interface (native C#, not PowerShell)
- [ ] Plugin system for extensibility
- [ ] Background service for scheduled tasks
- [ ] Remote management API
- [ ] Multi-server management

## Related Documentation

- **[CONTRIBUTING.md](../CONTRIBUTING.md)** - Development guidelines
- **[CLAUDE.md](../CLAUDE.md)** - Legacy PowerShell documentation
- **[README.md](../README.md)** - Project overview

---

*Last updated: 2026-02-21*
*For questions, open a GitHub Discussion or Issue.*
