# Contributing to WSUS Manager

Thank you for your interest in contributing to WSUS Manager! This document provides guidelines for contributing to the project.

## Getting Started

WSUS Manager is a C# WPF application targeting .NET 8.0. The project uses:

- **.NET 8.0** - Target framework
- **WPF** - UI framework
- **xUnit** - Testing framework
- **Coverlet** - Code coverage
- **Roslyn Analyzers** - Static code analysis

## Prerequisites

- Windows 10/11 or Windows Server 2019+
- [.NET 8.0 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)
- Visual Studio 2022 (recommended) or VS Code with C# extension

## Building

```bash
# From the repository root
cd src
dotnet restore
dotnet build --configuration Release
```

## Running Tests

```bash
cd src
dotnet test
```

## Testing Guidelines

### Test Structure

Tests follow AAA pattern (Arrange, Act, Assert):

```csharp
[Fact]
public async Task ExecuteAsync_WithValidConfig_ReturnsSuccess()
{
    // Arrange
    var service = new HealthService(_mockLogger.Object, _mockConnection.Object);
    var config = new HealthCheckConfig { EnableDatabaseCheck = true };

    // Act
    var result = await service.CheckHealthAsync(config);

    // Assert
    Assert.True(result.IsHealthy);
    Assert.NotNull(result.DatabaseStatus);
}
```

### Naming Conventions

- Test method name: `MethodName_Scenario_ExpectedResult()`
- Async tests: Append `Async` suffix
- Parameterized tests: Use `[Theory]` with `[InlineData]`

### Mocking

Use Moq for mocking dependencies:

```csharp
// Arrange
var mockLogger = new Mock<ILogger<HealthService>>();
var mockConnection = new Mock<IDbConnection>();
mockConnection.Setup(x => x.OpenAsync(It.IsAny<CancellationToken>()))
             .Returns(Task.CompletedTask);

// Act
var service = new HealthService(mockLogger.Object, mockConnection.Object);

// Assert
mockConnection.Verify(x => x.OpenAsync(It.IsAny<CancellationToken>()), Times.Once);
```

### What to Test

- **Service layer:** All public methods, edge cases (null inputs, empty collections)
- **ViewModels:** Command execution, property change notifications, error handling
- **Validation:** Invalid inputs, boundary conditions, error messages
- **Infrastructure:** Log formatting, path validation, admin checks

### What NOT to Test

- Private/internal methods (test via public API)
- Third-party libraries (assume they work)
- UI layout (test ViewModel logic, not XAML)

### Test Data

Use `Theory` with `InlineData` for parameterized tests:

```csharp
[Theory]
[InlineData(null, false)]
[InlineData("", false)]
[InlineData("valid-host", true)]
public async Task ValidateHostname_ReturnsExpectedResult(string hostname, bool isValid)
{
    // Arrange
    var validator = new HostnameValidator();

    // Act
    var result = await validator.ValidateAsync(hostname);

    // Assert
    Assert.Equal(isValid, result.IsValid);
}
```

### Test Categories

The project uses test categories for organization:
- **Unit tests:** Fast, isolated tests (no external dependencies)
- **Integration tests:** Slower tests that use real databases/services
- **Validation tests:** Configuration and validation logic tests
- **ExeValidation tests:** Post-build EXE validation (runs only after publish)

### Coverage Goals (Phase 18)

**Current Status:** 84.27% line coverage, 62.19% branch coverage (560+ tests)

**Target:** Maintain >80% line coverage for new code

**v4.5 Additions (Phase 31):**
- 61 new tests for Phases 26, 28, 29, 30
- Performance benchmark suite (6 benchmarks)
- DataFilteringTests (21 tests)
- CsvExportServiceTests (15 tests)
- KeyboardNavigationTests extended (11 new tests)

See `.planning/phases/18-test-coverage/18-SUMMARY.md` for detailed coverage analysis.

## Code Style

This project uses [.editorconfig](src/.editorconfig) to define consistent code style across all editors.

### Naming Conventions

| Symbol Type | Convention | Example |
|-------------|------------|---------|
| Interfaces | PascalCase, prefixed with `I` | `IHealthService` |
| Classes/Structs/Enums | PascalCase | `HealthChecker`, `SyncProfile` |
| Methods | PascalCase | `CheckHealthAsync()` |
| Properties | PascalCase | `StatusMessage` |
| Private fields | `_camelCase` (underscore prefix) | `_logger`, `_connectionString` |
| Constants | PascalCase | `MaxRetryAttempts` |
| Local variables | camelCase | `retryCount`, `isConnected` |
| Async methods | PascalCase, suffixed with `Async` | `ExecuteAsync()` |

### Formatting Rules

- Indent: 4 spaces (no tabs)
- Braces: K&R style (opening brace on same line)
- Newlines: Line ending at end of file
- Using directives: Outside namespace, System first, then alphabetical

### Auto-Formatting

All editors auto-format on save when .editorconfig is supported:
- **Visual Studio Code:** Automatic (C# Dev Kit extension)
- **Visual Studio 2022:** Automatic (native)
- **Rider:** Automatic (native)

To format manually:
```bash
cd src
dotnet format WsusManager.sln
```

### Bulk Reformat (Completed 2026-02-21)

All existing code was reformatted using dotnet-format v9.0 with .NET 9 runtime via gap closure plan 19-GAP-02. The entire codebase now conforms to .editorconfig standards. New code will be auto-formatted by your IDE on save.

## Static Analysis

The project uses multiple Roslyn analyzers to enforce code quality:

- **.NET SDK Analyzers** - Built-in rules
- **Roslynator.Analyzers** - Refactoring suggestions
- **Meziantou.Analyzer** - Security and best practices
- **StyleCop.Analyzers** - Style and naming conventions

Analyzer configuration is in [Directory.Build.props](src/Directory.Build.props) and [.editorconfig](src/.editorconfig).

### Severity Levels

- **Error** - Blocks build (e.g., CA2007 ConfigureAwait for UI thread)
- **Warning** - Code quality issue, review recommended
- **Suggestion** - Style preference, auto-fix available
- **None** - Disabled rule

### Static Analysis Status (19-GAP-01 Complete)

**Status:** Zero warnings in Release build configuration (QUAL-01 satisfied)

**Achieved:** 2026-02-21 via gap closure plan 19-GAP-01

**Key Changes:**
- CA2007 elevated to error (all async calls use ConfigureAwait)
- Non-critical warnings suppressed with justification
- 567 warnings reduced to 0

**Active Errors:**
- CA2007: ConfigureAwait on awaited task (ERROR - blocks build)

**Suppressed Rules (with justification):**
- MA0074, MA0006: String comparison warnings (test code, low value)
- MA0051: Method length warnings (code quality indicator, not blocking)
- xUnit1030, xUnit1012, xUnit1026: Test framework warnings (standard patterns)
- SA1602, SA1649, SA1618, SA1519, SA1507: Style warnings (non-critical)
- CA2201, CA1822, CA1861, CA1848: Code style warnings (acceptable patterns)
- SA1113, SA1001, SA1516, SA1402, SA1139: Formatting warnings (style preference)
- CA1859, CA1816, CA1716, CA1000, CA1834, CA1806, CA1068, CA1001: Low-priority warnings

See [.editorconfig](src/.editorconfig) for the full rule configuration and suppression rationale.

### Common Analyzer Rules

| Rule ID | Description | Severity | Action |
|---------|-------------|----------|--------|
| CA2007 | ConfigureAwait on awaited task | **Error** | Required - blocks build if missing |
| MA0004 | Use ConfigureAwait(false) | None | Fixed - all library code updated |
| MA0074 | Use StringComparison | None | Suppressed - test code only |
| MA0006 | Use string.Equals | None | Suppressed - test code only |
| SA1101 | Prefix local calls with this | None | Style preference (disabled) |
| SA1600 | Elements should be documented | None | XML docs (Phase 20) |

## CI/CD Pipeline

WSUS Manager uses GitHub Actions for continuous integration and deployment.

For detailed workflow documentation, troubleshooting guides, artifact descriptions, and local development commands, see:
- **[docs/ci-cd.md](docs/ci-cd.md)** - Complete CI/CD pipeline documentation

**Quick summary:**
- **Build C# WSUS Manager** - Runs on push/PR to main (build, test, publish)
- **Build PowerShell GUI (Legacy)** - Runs on push/PR to main (code review, test, build)
- **Create Release** - Runs on git tag push or manual trigger
- **Repository Hygiene** - Scheduled daily cleanup of stale PRs, branches, and workflow runs
- **Dependabot Auto-Merge** - Auto-approves minor/patch dependency updates

### Running Workflows Locally

Before pushing, run the same commands CI executes:

```bash
# Build (Release configuration)
cd src
dotnet build --configuration Release

# Run tests with coverage
dotnet test --collect:"XPlat Code Coverage"

# Run tests with coverage report (requires ReportGenerator)
dotnet test --collect:"XPlat Code Coverage" -- DataCollectionRunSettings.DataCollectors.DataCollector.Configuration.Format=opencover
reportgenerator -reports:**/coverage.cobertura.xml -targetdir:coverage.html
```

See [docs/ci-cd.md](docs/ci-cd.md) for full workflow details, artifact descriptions, and troubleshooting.

### Coverage Reports

Coverage is generated but not enforced (minimum threshold not set). View coverage in:
- **CI:** Download `code-coverage-report` artifact from Actions run
- **Local:** Open `coverage.html/index.html` after running with ReportGenerator

### Benchmarking

The project includes performance benchmarks via BenchmarkDotNet:
- **Trigger:** Manual via workflow dispatch
- **Location:** `src/WsusManager.Benchmarks/`
- **Output:** HTML reports with regression detection
- **Baselines:** Stored in `src/WsusManager.Benchmarks/baselines/`

See Phase 22 (Performance Benchmarking) documentation for benchmark categories and regression thresholds.

## Commit Messages

Use conventional commit format:

```
type(scope): description

# Types: feat, fix, refactor, test, docs, chore
# Examples:
feat(core): add database cleanup service
fix(ui): resolve dashboard refresh deadlock
refactor(services): extract common retry logic
test(health): add null input edge case tests
docs(readme): update build instructions
```

## Pull Requests

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Make your changes
4. Run tests (`dotnet test`)
5. Ensure build passes (`dotnet build --configuration Release`)
6. Commit with conventional message
7. Push to your fork
8. Create a pull request

### PR Checklist

- [ ] Tests pass locally
- [ ] Build passes in Release configuration
- [ ] Code follows style conventions (.editorconfig)
- [ ] No new analyzer warnings introduced
- [ ] Documentation updated (if applicable)
- [ ] Commit messages follow conventional format

## Release Process

WSUS Manager uses semantic versioning and automated releases.

### Quick Summary

1. Update version in `src/Directory.Build.props`
2. Update `CHANGELOG.md` with release notes
3. Commit and push to main branch
4. Create git tag: `git tag v4.4.0 && git push origin v4.4.0`
5. GitHub Actions creates release automatically via `.github/workflows/build-csharp.yml`
6. Download release from GitHub Releases page

### Version Format

- **Major:** Breaking changes (e.g., 4.0 → 5.0)
- **Minor:** New features (e.g., 4.4 → 4.5)
- **Patch:** Bug fixes (e.g., 4.4.0 → 4.4.1)

### Release Notes Template

```markdown
## WSUS Manager v{version}

### Added
- New feature 1
- New feature 2

### Fixed
- Bug fix 1
- Bug fix 2

### Changed
- Modification 1

### Technical
- Code quality improvements
- Test coverage updates
```

## Project Structure

```
src/
├── WsusManager.Core/           # Core library (business logic)
│   ├── Services/               # Service implementations
│   ├── Models/                 # Data models
│   ├── Infrastructure/         # Low-level utilities
│   └── Logging/                # Logging services
├── WsusManager.App/            # WPF application
│   ├── ViewModels/             # MVVM view models
│   ├── Views/                  # XAML views
│   └── Services/               # App-specific services
└── WsusManager.Tests/          # xUnit tests
    ├── Services/               # Service tests
    ├── ViewModels/             # ViewModel tests
    └── Validation/             # Validation/integration tests
```

## Architecture

WSUS Manager follows the MVVM pattern with clear separation of concerns:

- **Presentation Layer:** WPF views and ViewModels (WsusManager.App)
- **Business Logic Layer:** Services and models (WsusManager.Core)
- **External Integration:** SQL, WinRM, Windows Services

For detailed architecture documentation, design decisions, and component diagrams, see:
- **[docs/architecture.md](docs/architecture.md)** - Complete architecture documentation

**Key patterns:**
- MVVM with CommunityToolkit.Mvvm
- Dependency injection with Microsoft.Extensions.DependencyInjection
- Async/await throughout for responsive UI
- Interface-based design for testability

## PowerShell Scripts

WSUS Manager includes PowerShell scripts for certain operations that are not yet fully ported to C#.

### PowerShell Scripts in Repository

The repository root contains legacy PowerShell scripts from v3.x:

- **Scripts/Invoke-WsusManagement.ps1** - Core WSUS operations (used by v3.x GUI)
- **Scripts/Invoke-WsusMonthlyMaintenance.ps1** - Online sync with profiles
- **Scripts/Install-WsusWithSqlExpress.ps1** - WSUS installation wizard
- **Scripts/Set-WsusHttps.ps1** - SSL certificate configuration
- **Scripts/Invoke-WsusClientCheckIn.ps1** - Client check-in trigger

### C# Integration

The C# app can call these scripts via `Process.Start()` for operations not yet implemented:

```csharp
var psi = new ProcessStartInfo
{
    FileName = "powershell.exe",
    Arguments = $"-ExecutionPolicy Bypass -File \"{scriptPath}\" -{operation}",
    RedirectStandardOutput = true,
    RedirectStandardError = true,
    UseShellExecute = false,
    CreateNoWindow = true
};

using var process = Process.Start(psi);
// ... read output streams
```

### Testing PowerShell Scripts

PowerShell scripts have corresponding Pester tests in `Tests/`:

```powershell
# Run PowerShell tests
.\Tests\Run-PesterTests.ps1

# Or use Invoke-Pester directly
Invoke-Pester -Path .\Tests -Output Detailed
```

### Future: CLI in C#

A native C# CLI is planned for v4.5 to replace PowerShell scripts entirely.

## Adding New Features

### 1. Define the Interface

Create interface in `WsusManager.Core/Services/Interfaces/`:

```csharp
public interface IMyNewService
{
    Task<MyResult> ExecuteAsync(MyRequest request, CancellationToken cancellationToken);
}
```

### 2. Implement the Service

Create implementation in `WsusManager.Core/Services/`:

```csharp
internal class MyNewService : IMyNewService
{
    private readonly ILogger<MyNewService> _logger;
    private readonly IDependencyService _dependency;

    public MyNewService(ILogger<MyNewService> logger, IDependencyService dependency)
    {
        _logger = logger;
        _dependency = dependency;
    }

    public async Task<MyResult> ExecuteAsync(MyRequest request, CancellationToken cancellationToken)
    {
        _logger.LogInformation("Executing MyNewService");

        // ... implementation ...

        return new MyResult { Success = true };
    }
}
```

### 3. Register in DI Container

Add to `WsusManager.App/Services/ServiceCollectionExtensions.cs`:

```csharp
services.AddTransient<IMyNewService, MyNewService>();
```

### 4. Add Unit Tests

Create test file in `WsusManager.Tests/Services/`:

```csharp
public class MyNewServiceTests
{
    [Fact]
    public async Task ExecuteAsync_WithValidRequest_ReturnsSuccess()
    {
        // Arrange
        var mockLogger = new Mock<ILogger<MyNewService>>();
        var mockDependency = new Mock<IDependencyService>();
        var service = new MyNewService(mockLogger.Object, mockDependency.Object);
        var request = new MyRequest();

        // Act
        var result = await service.ExecuteAsync(request, CancellationToken.None);

        // Assert
        Assert.True(result.Success);
    }
}
```

### 5. Integrate in ViewModel (if UI-related)

Inject service into ViewModel:

```csharp
public class MainViewModel : ViewModelBase
{
    private readonly IMyNewService _myService;

    public MainViewModel(IMyNewService myService)
    {
        _myService = myService;
    }

    [RelayCommand(CanExecute = nameof(CanExecuteMyOperation))]
    private async Task RunMyOperationAsync()
    {
        await RunOperationAsync("My Operation", async () =>
        {
            var result = await _myService.ExecuteAsync(new MyRequest(), CancellationToken.None);
            return result.Success;
        });
    }
}
```

### 6. Add XML Documentation

Document public APIs with XML comments:

```csharp
/// <summary>
/// Executes the my new operation with the specified request.
/// </summary>
/// <param name="request">The request parameters.</param>
/// <param name="cancellationToken">Cancellation token for async operation.</param>
/// <returns>Result of the operation.</returns>
/// <exception cref="ArgumentNullException">Thrown when request is null.</exception>
/// <exception cref="OperationCanceledException">Thrown when operation is canceled.</exception>
public async Task<MyResult> ExecuteAsync(MyRequest request, CancellationToken cancellationToken)
{
    // ...
}
```

## Getting Help

### Documentation

- **[docs/architecture.md](docs/architecture.md)** - Architecture documentation (MVVM, DI, design decisions)
- **[CLAUDE.md](CLAUDE.md)** - Legacy PowerShell development docs (for reference)
- **[README.md](README.md)** - User-facing documentation
- **[docs/](docs/)** - Additional project documentation

### Support Channels

- **GitHub Issues:** Report bugs or request features
- **GitHub Discussions:** Ask questions or start discussions

### Debugging Tips

- **Enable verbose logging:** In the app, Settings → Log Level → Verbose
- **Attach debugger:** Visual Studio → Debug → Attach to Process → WsusManager.App.exe
- **View logs:** Check the log panel in the application or `%APPDATA%\WsusManager\logs\`
- **Run diagnostics:** Use the Diagnostics operation in the app for health check

### Common Issues

| Issue | Solution |
|-------|----------|
| Build fails with "SDK not found" | Install .NET 8.0 SDK |
| Tests fail locally but pass in CI | Check test database settings, ensure SQL Express running |
| Can't attach debugger | Run as Administrator, check UAC settings |
| Analyzer warnings blocking build | Run `dotnet format` or fix manually |
| EXE won't start | Ensure running as Administrator on Windows 10/11 x64

---

Thank you for contributing!
