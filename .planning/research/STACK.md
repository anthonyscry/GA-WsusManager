# Technology Stack

**Project:** GA-WsusManager v4.4 Quality & Polish
**Researched:** 2026-02-21

## Summary

The v4.4 milestone adds quality and polish capabilities to the existing .NET 8 WPF codebase without requiring major architectural changes. Focus on lightweight tools that integrate cleanly with existing GitHub Actions CI/CD and xUnit/Moq test infrastructure.

## Recommended Stack

### Testing & Quality

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| **FlaUI.UIA3** | 4.0.0 | WPF UI automation testing | Modern WPF automation, better than WinAppDriver, active development, lambda-based API |
| **BenchmarkDotNet** | 0.14.x | Performance benchmarking | Industry standard for .NET, integrates with VS, generates diagsession files |
| **coverlet.collector** | 6.0.2 (existing) | Code coverage collection | Already in test project, generates Cobertura/OpenCover reports |
| **ReportGenerator** | 5.x (global tool) | Coverage report generation | HTML reports with risk hotspot analysis, badge generation, CI/CD integration |
| **SonarAnalyzer.CSharp** | 10.x | Enhanced static analysis | Security, reliability, and performance rules beyond built-in analyzers |

### Static Analysis (SDK-Built-In)

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| **.NET 8 SDK Analyzers** | Built-in | Core code quality | Already enabled (EnableNETAnalyzers), no NuGet needed, auto-updates with SDK |
| **EditorConfig** | .editorconfig | Rule configuration | Granular rule control, team synchronization, standard in .NET 5+ |

### Documentation

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| **DocFX** | 2.x (global tool) | API documentation generation | .NET-focused, generates static HTML from XML comments, GitHub Pages integration |
| **XML Documentation** | `<GenerateDocumentationFile>true</GenerateDocumentationFile>` | Compiler-validated comments | Built-in compiler validation, integrates with DocFX |

### Performance & Memory

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| **dotnet-trace** | CLI tool | Performance tracing | Cross-platform, production-safe, generates .nettrace files |
| **dotnet-counters** | CLI tool | Real-time monitoring | GC/memory/CPU metrics, minimal overhead |
| **PerfView** | 6.x (portable) | ETW analysis | Microsoft tool, GC pressure analysis, no installation required |

## Installation

### Testing & Quality

```bash
# UI automation (test project only)
cd src/WsusManager.Tests
dotnet add package FlaUI.UIA3 --version 4.0.0
dotnet add package FlaUI.Core --version 4.0.0

# Performance benchmarking (separate console project or test project)
dotnet add package BenchmarkDotNet --version 0.14.*

# Static analysis (existing test project - already has coverlet.collector)
dotnet add package SonarAnalyzer.CSharp --version 10.10.* --private-assets all

# Code coverage reporting (global tool)
dotnet tool install -g dotnet-reportgenerator-globaltool --version 5.*
```

### Documentation

```bash
# DocFX CLI (global tool)
dotnet tool install -g docfx --version 2.*

# Enable XML documentation in each csproj:
# <GenerateDocumentationFile>true</GenerateDocumentationFile>
# <NoWarn>$(NoWarn);1591</NoWarn>  # Optional: suppress missing XML comment warnings
```

### Performance & Memory

```bash
# dotnet-trace and dotnet-counters (included with .NET SDK)
# No installation required - use via: dotnet-trace, dotnet-counters

# PerfView (download portable executable)
# https://github.com/Microsoft/perfview/releases
```

## Project Configuration

### Enable .NET 8 SDK Analyzers

```xml
<!-- Already in src/Directory.Build.props or individual csproj -->
<PropertyGroup>
  <EnableNETAnalyzers>true</EnableNETAnalyzers>
  <AnalysisLevel>latest</AnalysisLevel>
  <EnforceCodeStyleInBuild>true</EnforceCodeStyleInBuild>
  <TreatWarningsAsErrors>false</TreatWarningsAsErrors>
</PropertyGroup>
```

### EditorConfig for Rule Customization

```ini
# .editorconfig (place in solution root)
[*.cs]

# Security rules as errors
dotnet_analyzer_diagnostic.category-Security.severity = error

# Performance rules as warnings
dotnet_analyzer_diagnostic.category-Performance.severity = warning

# Reliability rules as errors
dotnet_analyzer_diagnostic.category-Reliability.severity = error

# Specific rule overrides
dotnet_diagnostic.CA1062.severity = none  # Null validation - may be too noisy for legacy code
```

### Enable XML Documentation

```xml
<!-- Add to each .csproj that needs API docs -->
<PropertyGroup>
  <GenerateDocumentationFile>true</GenerateDocumentationFile>
  <NoWarn>$(NoWarn);1591</NoWarn>  # Suppress missing XML comments initially
</PropertyGroup>
```

### Code Coverage Configuration

```xml
<!-- Add to WsusManager.Tests.csproj -->
<ItemGroup>
  <PackageReference Include="coverlet.msbuild" Version="6.*" />
  <PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.12.*" />
</ItemGroup>

# Or use existing coverlet.collector with dotnet test --collect:"XPlat Code Coverage"
```

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| **UI Automation** | FlaUI.UIA3 | WinAppDriver | Deprecated, less reliable, Windows-only binary requirements |
| **UI Automation** | FlaUI.UIA3 | Playwright | Web-focused, overkill for desktop, requires browser context |
| **Performance** | BenchmarkDotNet | dotTrace/dotMemory | Commercial (JetBrains), adds cost, overkill for simple benchmarks |
| **Static Analysis** | SDK Analyzers | Microsoft.CodeAnalysis.NetAnalyzers | Redundant for .NET 5+, SDK version is preferred |
| **Documentation** | DocFX | Sandcastle | No longer maintained, limited output formats |
| **Documentation** | DocFX | Wyam | Steep learning curve, less .NET-focused |
| **Code Coverage** | Coverlet | OpenCover | Legacy, .NET Core support is secondary |

## Integration with Existing CI/CD

### GitHub Actions Updates

```yaml
# Add to .github/workflows/build-csharp.yml

- name: Run tests with coverage
  run: |
    dotnet test src/WsusManager.Tests/WsusManager.Tests.csproj `
      --configuration Release `
      --no-build `
      --verbosity normal `
      --logger "trx;LogFileName=test-results.trx" `
      --collect:"XPlat Code Coverage" `
      -- DataCollectionRunSettings.DataCollectors.DataCollector.Configuration.Format=cobertura

- name: Generate coverage report
  run: |
    dotnet tool run reportgenerator `
      -reports:**/coverage.cobertura.xml `
      -targetdir:coverage-report `
      -reporttypes:Html;Badges

- name: Upload coverage report
  uses: actions/upload-artifact@v4
  with:
    name: coverage-report
    path: coverage-report/

- name: Run benchmarks
  run: |
    dotnet run -c Release --project src/Benchmarks/Benchmarks.csproj

- name: Static analysis
  run: |
    dotnet build src/WsusManager.App/WsusManager.App.csproj `
      --configuration Release `
      /p:RunAnalyzersDuringBuild=true

- name: Generate documentation
  run: |
    docfx docs/docfx.json

- name: Upload documentation
  uses: actions/upload-artifact@v4
  if: success()
  with:
    name: api-documentation
    path: docs/_site/
```

## What NOT to Add

| Tool | Why Avoid |
|------|-----------|
| **SpecFlow** | Overkill for this project, BDD adds complexity without clear benefit |
| **NUnit/MSTest** | Already using xUnit, no reason to add multiple test frameworks |
| **AutoFixture** | May complicate existing Moq tests, use sparingly if needed |
| **StyleCop** | Redundant with SDK analyzers, focused on formatting over quality |
| **resharper** | Commercial license, IDE-specific, not CI-friendly |
| **Polly** | Not needed - no HTTP retry requirements beyond existing WinRM error handling |
| **Flurl** | Not needed - no HTTP client requirements beyond existing WinRM/PowerShell |
| **Dapper** | Not needed - already using Microsoft.Data.SqlClient directly |
| **Entity Framework** | Overkill - already using direct SQL with SqlClient |
| **MediatR** | Overkill - MVVM pattern already handles command/query separation |

## Dependencies on Existing Stack

### Must Keep

- **xUnit** - Existing test framework (336 tests)
- **Moq** - Existing mocking framework
- **CommunityToolkit.Mvvm** - Core MVVM infrastructure
- **Serilog** - Existing logging infrastructure
- **Microsoft.Data.SqlClient** - Database operations
- **System.ServiceProcess.ServiceController** - Service management
- **Microsoft.Extensions.DependencyInjection** - DI container
- **Microsoft.Extensions.Hosting** - Application host

### Version Compatibility

| Package | Existing Version | v4.4 Target | Notes |
|---------|------------------|-------------|-------|
| xUnit | 2.9.2 | 2.9.2 | No change needed |
| Moq | 4.20.* | 4.20.* | No change needed |
| CommunityToolkit.Mvvm | 8.4.0 | 8.4.0 | No change needed |
| Serilog | 4.* | 4.* | No change needed |
| Microsoft.Data.SqlClient | 6.1.4 | 6.1.4 | No change needed |
| .NET SDK | 8.0.x | 8.0.x | Lock to LTS |

## Migration Path

### Phase 1: Static Analysis
1. Add `.editorconfig` to solution root
2. Configure analysis level in `Directory.Build.props`
3. Add `SonarAnalyzer.CSharp` to test project
4. Fix high-confidence warnings

### Phase 2: Code Coverage
1. Ensure `coverlet.collector` is enabled (already in project)
2. Add coverage collection to CI/CD
3. Install `reportgenerator` global tool
4. Generate HTML reports and badges

### Phase 3: Documentation
1. Enable `<GenerateDocumentationFile>` in all csproj
2. Add XML comments to public APIs
3. Configure DocFX (docfx.json)
4. Generate static HTML documentation

### Phase 4: Performance
1. Create separate `WsusManager.Benchmarks` console project
2. Add BenchmarkDotNet
3. Benchmark critical paths (startup, DB operations)
4. Add performance regression tests to CI

### Phase 5: UI Automation
1. Create `WsusManager.UITests` project (xUnit)
2. Add FlaUI.UIA3 package
3. Write tests for critical user workflows
4. Add to CI/CD (requires Windows runner with UI)

## Sources

### Integration Testing
- [FlaUI GitHub Repository](https://github.com/FlaUI/FlaUI) - Official FlaUI documentation
- [FlaUI.UIA3 NuGet Package](https://www.nuget.org/packages/FlaUI.UIA3/) - Package information and version history

### Static Analysis
- [.NET Analyzers Overview](https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/overview) - Microsoft official documentation on .NET 8 analyzers
- [Roslyn Analyzers](https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/roslyn-analyzers-overview) - Built-in analyzer configuration
- [SonarAnalyzer.CSharp](https://www.nuget.org/packages/SonarAnalyzer.CSharp/) - Enhanced static analysis package

### Performance Profiling
- [BenchmarkDotNet](https://benchmarkdotnet.org/) - Official BenchmarkDotNet documentation
- [dotnet-trace Documentation](https://learn.microsoft.com/en-us/dotnet/core/diagnostics/dotnet-trace) - Microsoft CLI profiling tool
- [dotnet-counters Documentation](https://learn.microsoft.com/en-us/dotnet/core/diagnostics/dotnet-counters) - Real-time monitoring tool
- [PerfView](https://github.com/Microsoft/perfview) - Microsoft ETW analysis tool

### Code Coverage
- [Coverlet Documentation](https://github.com/coverlet-coverage/coverlet) - Official coverage collection documentation
- [ReportGenerator](https://github.com/danielpalme/ReportGenerator) - HTML report generation

### Documentation Generation
- [DocFX Documentation](https://dotnet.github.io/docfx/) - Official DocFX documentation
- [XML Documentation Comments](https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/xmldoc/) - C# XML comment reference

### Confidence Levels
| Area | Confidence | Notes |
|------|------------|-------|
| Integration Testing | HIGH | FlaUI is well-established for WPF, active development |
| Static Analysis | HIGH | SDK analyzers are official .NET 8 approach |
| Performance Profiling | HIGH | BenchmarkDotNet is industry standard |
| Code Coverage | HIGH | Coverlet already in use, ReportGenerator mature |
| Documentation | MEDIUM | DocFX is .NET-standard but configuration can be complex |
