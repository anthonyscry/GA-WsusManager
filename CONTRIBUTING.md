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

### Incremental Adoption (Phase 19)

We are incrementally adopting analyzer rules to avoid warning fatigue.

**Phase 1a (Current):** Critical rules as warnings
- CA2007: ConfigureAwait on awaited task (async/await UI safety)
- MA0004: Use Task.ConfigureAwait(false) when sync context not needed
- MA0074: Use StringComparison parameter for string operations
- MA0006: Use string.Equals instead of == operator
- CA1001: Types owning disposable fields should be disposable
- CA1716: Don't use reserved language keywords for member names
- CA1806: Check TryParse return values

**Phase 1b (Future):** After fixing current warnings, elevate CA2007 to error.

**Baseline (2026-02-21):** 716 warnings (down from 8946 with full StyleCop)

See [.editorconfig](src/.editorconfig) for the full rule configuration.

### Common Analyzer Rules

| Rule ID | Description | Severity | Action |
|---------|-------------|----------|--------|
| CA2007 | ConfigureAwait on awaited task | Warning | Add `.ConfigureAwait(false)` for library code |
| MA0004 | Use ConfigureAwait(false) | Warning | Library code should not capture sync context |
| MA0074 | Use StringComparison | Warning | Add StringComparison.Ordinal/InvariantCulture |
| MA0006 | Use string.Equals | Warning | Replace `==` with `string.Equals()` |
| SA1101 | Prefix local calls with this | None | Style preference (disabled) |
| SA1600 | Elements should be documented | None | XML docs (Phase 20) |

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

## Adding New Features

1. **Interface First**: Define interfaces in `WsusManager.Core/Services/Interfaces/`
2. **Implementation**: Implement in `WsusManager.Core/Services/`
3. **Unit Tests**: Add tests in `WsusManager.Tests/Services/`
4. **ViewModel Integration**: Wire up in ViewModels if UI-related
5. **Documentation**: Add XML documentation comments to public APIs

## Questions?

- Open an issue for bugs or feature requests
- Start a discussion for questions
- Check existing documentation in `docs/` and `wiki/`

Thank you for contributing!
