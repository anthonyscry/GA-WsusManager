# Architecture Research

**Domain:** C#/.NET 8 WPF Desktop Application — Quality & Polish Improvements
**Researched:** 2026-02-21
**Confidence:** HIGH

## Standard Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Quality & Polish Layer                             │
├─────────────────────────────────────────────────────────────────────────────┤
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐         │
│  │ Integration Tests│  │ UI Automation    │  │ Benchmark Suites │         │
│  │ (WsusManager.E2E)│  │ (WsusManager.UI) │  │ (WsusManager.Bench)│        │
│  └────────┬─────────┘  └────────┬─────────┘  └────────┬─────────┘         │
│           │                      │                      │                   │
├───────────┴──────────────────────┴──────────────────────┴───────────────────┤
│                        Analysis & Instrumentation                            │
├─────────────────────────────────────────────────────────────────────────────┤
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐         │
│  │ Roslyn Analyzers │  │ Code Coverage    │  │ Documentation    │         │
│  │ (.editorconfig)  │  │ (Coverlet)       │  │ (DocFx)          │         │
│  └────────┬─────────┘  └────────┬─────────┘  └────────┬─────────┘         │
│           │                      │                      │                   │
├───────────┴──────────────────────┴──────────────────────┴───────────────────┤
│                           Application Layer                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                        MainViewModel (MVVM)                          │   │
│  │  [ObservableProperty] + [RelayCommand] + INotifyPropertyChanged     │   │
│  └───────────────────────────────┬─────────────────────────────────────┘   │
│                                  │                                         │
├──────────────────────────────────┼─────────────────────────────────────────┤
│                                  │                                         │
│  ┌───────────────────────────────┴─────────────────────────────────────┐   │
│  │                         Service Layer (DI)                          │   │
│  │  IHealthService | ISyncService | IExportService | ... (18 services)│   │
│  └───────────────────────────────┬─────────────────────────────────────┘   │
│                                  │                                         │
├──────────────────────────────────┼─────────────────────────────────────────┤
│                                  │                                         │
│  ┌───────────────────────────────┴─────────────────────────────────────┐   │
│  │                        Core/Infrastructure                          │   │
│  │  LogService | ProcessRunner | WinRmExecutor | ThemeService         │   │
│  └───────────────────────────────┬─────────────────────────────────────┘   │
│                                  │                                         │
├──────────────────────────────────┼─────────────────────────────────────────┤
│                                  │                                         │
│  ┌───────────────────────────────┴─────────────────────────────────────┐   │
│  │                      External Dependencies                           │   │
│  │  WSUS API (runtime) | SQL Server | WinRM | FileSystem | Registry   │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Typical Implementation |
|-----------|----------------|------------------------|
| **Integration Tests** | End-to-end workflow validation across service boundaries | xUnit + real service instances + test containers |
| **UI Automation Tests** | Critical user path automation (button clicks, dialogs) | FlaUI.UIA3 + WinAppDriver + Page Object Model |
| **Benchmark Suites** | Performance regression detection for hot paths | BenchmarkDotNet + MemoryDiagnoser |
| **Roslyn Analyzers** | Compile-time code quality and security checks | .NET SDK analyzers + Roslynator + Meziantou |
| **Code Coverage** | Test coverage measurement and reporting | Coverlet collector + ReportGenerator |
| **Documentation Generator** | API doc website from XML comments | DocFx + Markdown + metadata |

## Recommended Project Structure

```
src/
├── WsusManager.Core/          # Existing: Business logic layer
│   ├── Models/                # Existing: Data models
│   ├── Services/              # Existing: Business services
│   ├── Services/Interfaces/   # Existing: Service contracts
│   ├── Infrastructure/        # Existing: ProcessRunner, WinRmExecutor
│   ├── Logging/               # Existing: LogService
│   └── WsusManager.Core.csproj
│
├── WsusManager.App/           # Existing: WPF UI layer
│   ├── ViewModels/            # Existing: MainViewModel
│   ├── Views/                 # Existing: MainWindow, Dialogs
│   ├── Themes/                # Existing: XAML theme resources
│   ├── Services/              # Existing: ThemeService (DI registration)
│   └── WsusManager.App.csproj
│
├── WsusManager.Tests/         # Existing: Unit tests
│   ├── Services/              # Existing: Service unit tests
│   ├── ViewModels/            # Existing: ViewModel unit tests
│   ├── Foundation/            # Existing: Model/utility tests
│   ├── Integration/           # Existing: DI container tests
│   ├── Validation/            # Existing: EXE/dist validation
│   └── WsusManager.Tests.csproj
│
├── WsusManager.E2E/           # NEW: Integration tests
│   ├── Workflows/             # Health → Repair → Dashboard sync workflow
│   ├── Database/              # Backup → DeepCleanup → Restore workflow
│   ├── Transfer/              # Export → Import cycle (air-gap simulation)
│   ├── ClientManagement/      # WinRM remote operations (requires setup)
│   └── WsusManager.E2E.csproj
│
├── WsusManager.UI.Tests/      # NEW: UI automation tests
│   ├── Pages/                 # Page Object Model (MainWindow, SettingsDialog)
│   ├── Scenarios/             # Critical user paths (install, transfer, schedule)
│   ├── Helpers/               # ApplicationLauncher, WaitHelper, ScreenshotHelper
│   ├── appsettings.json       # Test configuration (EXE path, timeouts)
│   └── WsusManager.UI.Tests.csproj
│
├── WsusManager.Benchmarks/    # NEW: Performance benchmarks
│   ├── Services/              # Service method benchmarks (SqlService, SyncService)
│   ├── ViewModel/             # ViewModel command benchmarks
│   ├── Startup/               # Application startup benchmark
│   └── WsusManager.Benchmarks.csproj
│
├── WsusManager.Docs/          # NEW: Documentation project
│   ├── api/                   # Auto-generated from XML comments
│   ├── articles/              # Architecture, getting started, troubleshooting
│   ├── docfx.json             # DocFx configuration
│   └── index.md               # Documentation homepage
│
├── Directory.Build.props      # SHARED: Roslyn analyzer packages
├── .editorconfig              # SHARED: Code style + analyzer rules
└── stylecop.json              # SHARED: StyleCop analyzer configuration
```

### Structure Rationale

- **WsusManager.E2E/**: Isolates slow integration tests from fast unit tests — allows CI to run them in parallel
- **WsusManager.UI.Tests/**: Separate project avoids STA thread conflicts with unit tests — FlaUI requires `[STAThread]` assembly attribute
- **WsusManager.Benchmarks/**: Benchmarks should not run on every test execution — separate project prevents accidental benchmark runs
- **WsusManager.Docs/**: Documentation generation requires separate build step — keeps doc artifacts out of production code
- **Directory.Build.props**: Centralized analyzer configuration ensures consistent code quality across all projects
- **.editorconfig**: IDE-agnostic rule enforcement — works in VS, VS Code, Rider

## Architectural Patterns

### Pattern 1: Test Pyramid for WPF Applications

**What:** Three-tier testing strategy with decreasing test count and increasing execution time

```
           ┌─────────────────┐
           │   UI Automation │  ← 10-20 critical user paths (FlaUI)
           │     (Slow)      │     Seconds to minutes per test
           ├─────────────────┤
           │  Integration    │  ← 50-100 end-to-end workflows
           │   (Medium)      │     Hundreds of milliseconds per test
           ├─────────────────┤
           │     Unit        │  ← 300+ isolated component tests
           │    (Fast)       │     Milliseconds per test
           └─────────────────┘
```

**When to use:** All WPF applications — provides fast feedback during development with confidence that critical user paths work

**Trade-offs:**
- **Pros:** Fast unit test feedback, comprehensive integration coverage, user-facing UI test validation
- **Cons:** Requires maintaining three test suites, UI tests are flaky if element IDs change

### Pattern 2: Page Object Model for UI Automation

**What:** Encapsulate UI elements and interactions in reusable "page" classes

```csharp
// WsusManager.UI.Tests/Pages/MainWindowPage.cs
public class MainWindowPage
{
    private readonly Window _window;

    public MainWindowPage(Window window)
    {
        _window = window;
        DashboardButton = FindButton("BtnDashboard");
        DiagnosticsButton = FindButton("BtnDiagnostics");
        LogOutput = FindTextBox("LogOutput");
    }

    public Button DashboardButton { get; }
    public Button DiagnosticsButton { get; }
    public TextBox LogOutput { get; }

    public void ClickDashboard() => DashboardButton.Click();
    public string GetLogText() => LogOutput.Text;
}
```

**When to use:** UI automation tests — improves maintainability and reduces duplication

**Trade-offs:**
- **Pros:** Single source of truth for UI selectors, reusable across tests, easier to update when UI changes
- **Cons:** Additional abstraction layer to maintain, initial setup overhead

### Pattern 3: Shared Analyzer Configuration via Directory.Build.props

**What:** Centralized Roslyn analyzer packages and rules for entire solution

```xml
<!-- Directory.Build.props (solution root) -->
<Project>
  <PropertyGroup>
    <EnableNETAnalyzers>true</EnableNETAnalyzers>
    <AnalysisMode>Recommended</AnalysisMode>
    <WarningsAsErrors>CA2007;CA1062</WarningsAsErrors>
    <TreatWarningsAsErrors>false</TreatWarningsAsErrors>
    <EnforceCodeStyleInBuild>true</EnforceCodeStyleInBuild>
    <GenerateDocumentationFile>true</GenerateDocumentationFile>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="Roslynator.Analyzers" Version="4.12.0" />
    <PackageReference Include="Meziantou.Analyzers" Version="2.0.0" />
    <PackageReference Include="StyleCop.Analyzers" Version="1.2.0-beta.556">
      <PrivateAssets>all</PrivateAssets>
    </PackageReference>
  </ItemGroup>
</Project>
```

**When to use:** All .NET solutions — ensures consistent code quality across all projects

**Trade-offs:**
- **Pros:** Single source of truth, all projects inherit analyzers automatically, enforces team standards
- **Cons:** Requires MSBuild import understanding, can be overridden per-project if needed

### Pattern 4: Integration Test Fixture with Shared Context

**What:** Reusable test fixture that sets up real service instances once per test class

```csharp
// WsusManager.E2E/Workflows/HealthCheckWorkflowTests.cs
public class HealthCheckWorkflowTests : IAsyncLifetime
{
    private IServiceProvider _services = null!;
    private IHealthService _healthService = null!;
    private IDashboardService _dashboardService = null!;
    private string _tempDir = null!;

    public async Task InitializeAsync()
    {
        _tempDir = Path.Combine(Path.GetTempPath(), $"WsusE2E_{Guid.NewGuid():N}");
        Directory.CreateDirectory(_tempDir);

        _services = new ServiceCollection()
            .AddSingleton<ILogService>(new LogService(_tempDir))
            .AddSingleton<IProcessRunner, ProcessRunner>()
            .AddSingleton<IWindowsServiceManager, WindowsServiceManager>()
            // ... register all Core services ...
            .BuildServiceProvider();

        _healthService = _services.GetRequiredService<IHealthService>();
        _dashboardService = _services.GetRequiredService<IDashboardService>();
    }

    public async Task DisposeAsync()
    {
        if (_services is IAsyncDisposable asyncDisposable)
            await asyncDisposable.DisposeAsync();

        try { Directory.Delete(_tempDir, recursive: true); }
        catch { }
    }

    [Fact]
    public async Task RunDiagnostics_ThenRepair_WindowsServices_AreFixed()
    {
        // Arrange: Simulate broken services
        // Act: Run diagnostics, then repair
        // Assert: Services are healthy after repair
    }
}
```

**When to use:** Integration tests — reduces fixture setup overhead and allows test methods to share service instances

**Trade-offs:**
- **Pros:** Faster test execution (services created once per class, not per test), realistic service interactions
- **Cons:** Tests can affect each other if services have mutable state, requires careful test isolation

### Pattern 5: Benchmark with Baseline Comparison

**What:** Benchmark critical paths with BenchmarkDotNet and compare against baseline

```csharp
// WsusManager.Benchmarks/Services/SyncServiceBenchmarks.cs
[MemoryDiagnoser]
[SimpleJob(warmupCount: 3, iterationCount: 10, targetCount: 10)]
public class SyncServiceBenchmarks
{
    private ISyncService _syncService = null!;
    private SyncProfile _profile = null!;

    [GlobalSetup]
    public void Setup()
    {
        // Setup real service with test data
    }

    [Benchmark(Baseline = true)]
    public async Task<SyncResult> FullSync()
    {
        return await _syncService.RunAsync(_profile, progress: null, CancellationToken.None);
    }

    [Benchmark]
    public async Task<SyncResult> QuickSync()
    {
        return await _syncService.RunAsync(_profile.WithQuickMode(), progress: null, CancellationToken.None);
    }
}
```

**When to use:** Performance regression detection — ensures code changes don't degrade performance

**Trade-offs:**
- **Pros:** Statistical rigor, automatic warmup/iterations, memory allocation tracking, baseline comparison
- **Cons:** Requires stable test environment, slow to run (not for CI on every commit)

### Pattern 6: DocFx Documentation from XML Comments

**What:** Generate API documentation website from triple-slash comments

```csharp
/// <summary>
/// Service for performing WSUS synchronization with Microsoft Update.
/// </summary>
/// <remarks>
/// This service requires WSUS to be installed and the Update Services API to be available.
/// It supports both full synchronization and quick sync modes.
/// </remarks>
/// <example>
/// <code>
/// var syncService = new SyncService(wsusServerService, processRunner);
/// var profile = new SyncProfile { Mode = SyncMode.Full };
/// var result = await syncService.RunAsync(profile, progress, cancellationToken);
/// </code>
/// </example>
public interface ISyncService
{
    /// <summary>
    /// Runs WSUS synchronization with the specified profile.
    /// </summary>
    /// <param name="profile">The synchronization profile (full or quick mode).</param>
    /// <param name="progress">Optional progress reporter for status updates.</param>
    /// <param name="cancellationToken">Cancellation token for async operation.</param>
    /// <returns>A <see cref="SyncResult"/> containing synchronization statistics.</returns>
    /// <exception cref="InvalidOperationException">Thrown when WSUS is not installed.</exception>
    Task<SyncResult> RunAsync(SyncProfile profile, IProgress<string>? progress, CancellationToken cancellationToken);
}
```

**When to use:** All public APIs — provides IntelliSense documentation and generates web docs

**Trade-offs:**
- **Pros:** Automatic doc generation, IntelliSense integration, centralized API reference
- **Cons:** Verbose comments increase code size, must be kept in sync with code changes

## Data Flow

### Quality Gate Flow (CI/CD Pipeline)

```
[Developer Push]
    ↓
[Build Solution]
    ↓
[Run Unit Tests] ←── xUnit + Moq (fast, ~5 seconds)
    ↓              └── Coverlet collector (coverage)
    ↓
[Run Integration Tests] ←── xUnit + real services (medium, ~30 seconds)
    ↓
[Static Analysis] ←── Roslyn analyzers (build-time)
    ↓              ├── .NET SDK analyzers (CA rules)
    ↓              ├── Roslynator (refactoring)
    ↓              └── Meziantou (security)
    ↓
[UI Automation Tests] ←── FlaUI.UIA3 (slow, ~2 minutes)
    ↓                       └── Optional: Only on release branches
    ↓
[Code Coverage Report] ←── ReportGenerator (HTML artifacts)
    ↓
[Generate Docs] ←── DocFx (API documentation website)
    ↓
[Benchmarks] ←── BenchmarkDotNet (manual trigger only)
    ↓
[Publish EXE] ←── dotnet publish (single-file)
    ↓
[Release Package] ←── GitHub Release with artifacts
```

### Test Discovery Flow

```
dotnet test
    ↓
[Discover all *Tests.csproj]
    ↓
├── WsusManager.Tests (Unit + Integration)
│   ├── Filter: Category != "E2E" && Category != "UI"
│   └── Run: All unit + integration tests
│
├── WsusManager.E2E (Integration Workflows)
│   └── Run: Only if --filter "Category=E2E"
│
└── WsusManager.UI.Tests (UI Automation)
    └── Run: Only if --filter "Category=UI"
```

### Coverage Collection Flow

```
dotnet test --collect:"XPlat Code Coverage"
    ↓
[Coverlet Collector]
    ↓
├── Instrument assemblies at runtime
├── Track line/branch/method coverage
└── Generate coverage.cobertura.xml
    ↓
[ReportGenerator]
    ↓
Generate HTML report
    ↓
[GitHub Actions Upload Artifact]
```

## Scaling Considerations

| Scale | Architecture Adjustments |
|-------|--------------------------|
| **0-1K users** (Current) | Single EXE deployment, local SQL Express, no scaling needed |
| **1K-10K users** | Multi-server WSUS deployment (upstream/downstream), centralized reporting |
| **10K+ users** | Distributed WSUS architecture, separate reporting database, load balancing |

### Quality & Polish Scaling Priorities

1. **First bottleneck:** Test execution time — mitigate by running unit/integration tests in parallel, UI tests only on release branches
2. **Second bottleneck:** Documentation maintenance — mitigate by enforcing XML comments on public APIs, auto-generating docs
3. **Third bottleneck:** Benchmark stability — mitigate by running benchmarks in isolated environment, dedicated benchmark runner

## Anti-Patterns

### Anti-Pattern 1: UI Tests That Depend on Implementation Details

**What people do:** Locating elements by control type or text content that changes frequently

```csharp
// BAD: Fragile selector
var button = window.FindFirstDescendant(cf => cf.ByText("Click me"))?.AsButton();
```

**Why it's wrong:** UI text changes during localization or redesign break tests

**Do this instead:** Use stable AutomationId selectors

```csharp
// GOOD: Stable selector
var button = window.FindFirstDescendant(cf => cf.ByAutomationId("BtnSubmit"))?.AsButton();
```

### Anti-Pattern 2: Integration Tests That Require External Services

**What people do:** Writing integration tests that require actual WSUS server or SQL database

```csharp
// BAD: Requires real WSUS installation
[Fact]
public async Task SyncWithRealWsusServer()
{
    // Fails on CI machines without WSUS
}
```

**Why it's wrong:** Tests fail in CI, require special environment setup

**Do this instead:** Mock external dependencies or use test containers

```csharp
// GOOD: Uses local SQL Express or mocks
[Fact]
public async Task CleanupWithLocalSqlExpress()
{
    // Uses connection string to localhost\SQLEXPRESS
}
```

### Anti-Pattern 3: Benchmarks That Run on Every Commit

**What people do:** Adding benchmark project to default test run

```yaml
# BAD: Runs benchmarks on every commit
- name: Run tests
  run: dotnet test src/**/*.csproj
```

**Why it's wrong:** Benchmarks are slow (minutes) and noisy in shared CI environments

**Do this instead:** Run benchmarks manually or on schedule

```yaml
# GOOD: Run benchmarks only manually
- name: Run benchmarks
  if: github.event_name == 'workflow_dispatch'
  run: dotnet run --project src/WsusManager.Benchmarks
```

### Anti-Pattern 4: Documentation Comments Without Examples

**What people do:** Writing XML comments without usage examples

```csharp
// BAD: No example
/// <summary>
/// Runs WSUS synchronization.
/// </summary>
Task<SyncResult> RunAsync(SyncProfile profile, ...);
```

**Why it's wrong:** Developers must read source code to understand usage

**Do this instead:** Include example code in comments

```csharp
// GOOD: Includes example
/// <summary>
/// Runs WSUS synchronization.
/// </summary>
/// <example>
/// <code>
/// var result = await syncService.RunAsync(profile, progress, token);
/// </code>
/// </example>
Task<SyncResult> RunAsync(SyncProfile profile, ...);
```

### Anti-Pattern 5: Analyzer Warnings Suppressed Without Justification

**What people do:** Adding `#pragma warning disable` without comment

```csharp
// BAD: Unexplained suppression
#pragma warning disable CA2007
await Task.Delay(1000);
```

**Why it's wrong:** Hides potential bugs, no audit trail for why suppression was needed

**Do this instead:** Justify suppressions with comments

```csharp
// GOOD: Justified suppression
#pragma warning disable CA2007 // Consideration: Not using ConfigureAwait(false) for WPF context
await Task.Delay(1000);
#pragma warning restore CA2007
```

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| **FlaUI.UIA3** | UI Automation Test Project | Requires `[STAThread]` assembly attribute, disable test parallelization |
| **Coverlet** | NuGet package in test projects | Use `coverlet.collector` for xUnit, exclude ViewModels on non-Windows |
| **BenchmarkDotNet** | Console app in separate project | Run manually, not in CI — requires stable environment |
| **DocFx** | Console app + GitHub Actions | Generate docs on release, publish to GitHub Pages |
| **Roslyn Analyzers** | Directory.Build.props package references | Inherits to all projects automatically |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| **Tests → Production Code** | Project reference + InternalsVisibleTo | Unit tests can access internal members, E2E tests use public APIs only |
| **UI Tests → Application** | Process launch (EXE) | UI tests launch compiled EXE, not in-process — requires published build |
| **Benchmarks → Services** | Direct instantiation | Benchmarks use real services, not mocks — requires test data setup |

### Build Order Dependencies

```
1. WsusManager.Core          (No dependencies)
   ↓
2. WsusManager.App           (Depends on Core)
   ↓
3. WsusManager.Tests         (Depends on Core, App)
   ↓
4. WsusManager.E2E           (Depends on Core only — tests real services)
   ↓
5. WsusManager.UI.Tests      (Depends on App EXE — requires published build)
   ↓
6. WsusManager.Benchmarks    (Depends on Core only)
   ↓
7. WsusManager.Docs          (Depends on all projects for XML comments)
```

**Recommended build order for quality improvements:**

1. **Static Analysis Setup** (infrastructure, blocks nothing)
   - Add Directory.Build.props with analyzers
   - Configure .editorconfig rules
   - Add XML documentation generation

2. **Test Infrastructure** (blocks implementation)
   - Create WsusManager.E2E project
   - Create WsusManager.Benchmarks project
   - Add test categories to existing WsusManager.Tests

3. **Coverage & Reporting** (requires tests)
   - Add Coverlet collector
   - Configure ReportGenerator in CI
   - Set coverage thresholds (e.g., 70% line coverage)

4. **UI Automation** (requires stable UI)
   - Create WsusManager.UI.Tests project
   - Add AutomationId to all interactive controls
   - Implement Page Object Model for MainWindow and dialogs

5. **Documentation** (requires XML comments)
   - Add XML comments to all public APIs
   - Create WsusManager.Docs project with DocFx
   - Configure GitHub Actions to publish docs

## Sources

- [FlaUI WPF UI Automation Tutorial](https://m.blog.csdn.net/LZYself/article/details/157428567)
- [WinAppDriver Integration Best Practices](https://xie.infoq.cn/article/5eb36ba2e71dec2600e786190)
- [.NET 8 WPF Testing with xUnit](https://m.blog.csdn.net/u012094427/article/details/148428775)
- [Roslyn Analyzers for .NET 8](https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/overview)
- [Coverlet Code Coverage Documentation](https://github.com/coverlet-coverage/coverlet)
- [BenchmarkDotNet Documentation](https://benchmarkdotnet.org/articles/guides/home.html)
- [DocFx Documentation Generation](https://dotnet.github.io/docfx/)
- [.NET EditorConfig Configuration](https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/configuration-files)
- [xUnit Collection Behavior for STA Threads](https://xunit.net/docs/running-tests-in-parallel)
- [ReportGenerator Documentation](https://github.com/danielpalme/ReportGenerator)

---
*Architecture research for: C#/.NET 8 WPF Quality & Polish Improvements*
*Researched: 2026-02-21*
