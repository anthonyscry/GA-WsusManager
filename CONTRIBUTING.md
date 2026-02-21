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
