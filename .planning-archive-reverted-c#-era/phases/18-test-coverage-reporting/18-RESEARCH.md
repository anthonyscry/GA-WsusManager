# Phase 18 Research: Test Coverage & Reporting

**Researched:** 2026-02-21
**Status:** Complete

## Executive Summary

Coverlet collector v6.0.2 is already installed in the test project. This phase will add ReportGenerator for HTML coverage reports, configure quality gates, integrate coverage artifacts into CI/CD, and add edge case tests for critical paths. The implementation follows best practices for .NET 8 WPF applications.

## Current State

### Existing Infrastructure
- **Coverlet collector v6.0.2**: Already installed in `WsusManager.Tests.csproj`
- **336 xUnit tests**: Passing across unit and integration test suites
- **CI/CD pipeline**: GitHub Actions (`build-csharp.yml`) runs tests on every push/PR
- **Test frameworks**: xUnit 2.9.2, Moq 4.20.*, CommunityToolkit.Mvvm 8.4.0

### Test Coverage Status
- **Unknown baseline**: No coverage reporting currently configured
- **Edge case coverage**: Ad-hoc (no systematic verification)
- **Exception path testing**: Partial (no comprehensive audit)

## Technical Research

### 1. Coverage Collection with Coverlet

**Installation**: Already complete (`coverlet.collector` v6.0.2)

**Running tests with coverage collection**:
```bash
dotnet test --collect:"XPlat Code Coverage" --configuration Release
```

**Output format**: Coverlet generates `coverage.cobertura.xml` in `TestResults/` directory by default.

### 2. HTML Report Generation with ReportGenerator

**Installation as global tool** (recommended for CI consistency):
```bash
dotnet tool install -g dotnet-reportgenerator-globaltool
```

**Report generation command**:
```bash
reportgenerator -reports:./TestResults/**/coverage.cobertura.xml -targetdir:./CoverageReport -reporttypes:HtmlInline
```

**Report types**:
- `HtmlInline` - HTML report with source code highlighting (recommended for local viewing)
- `Html` - Summary-only HTML report (faster loading)
- `HtmlInline_AzurePipelines` - Optimized for Azure DevOps (not applicable for GitHub Actions)

**Key features**:
- Line coverage percentage per class/namespace
- Branch coverage analysis (conditional paths)
- Uncovered lines highlighted in red
- Coverage by assembly breakdown
- Historical trend tracking (if coverage history files maintained)

### 3. Quality Gates and Threshold Enforcement

**Coverlet threshold configuration via MSBuild properties**:

In `.csproj` or `Directory.Build.props`:
```xml
<PropertyGroup>
  <CollectCoverage>true</CollectCoverage>
  <Threshold>70</Threshold>              <!-- Minimum 70% coverage -->
  <ThresholdType>line</ThresholdType>    <!-- Line coverage (or branch, method) -->
  <ThresholdStat>minimum</ThresholdStat> <!-- Each module must meet threshold -->
</PropertyGroup>
```

**Threshold options**:
- `ThresholdType`: `line`, `branch`, `method`
- `ThresholdStat`: `minimum` (each module), `total` (combined), `average` (mean)
- Multiple thresholds: `Threshold="80,70,85"` with `ThresholdType="line,branch,method"`

**Build will fail** if coverage falls below threshold. This provides automated quality gates.

### 4. CI/CD Integration (GitHub Actions)

**Add coverage collection to existing test step**:
```yaml
- name: Run tests with coverage
  run: |
    dotnet test src/WsusManager.Tests/WsusManager.Tests.csproj `
      --configuration Release `
      --no-build `
      --collect:"XPlat Code Coverage" `
      --verbosity normal
```

**Generate HTML report**:
```yaml
- name: Generate coverage report
  run: |
    dotnet tool install -g dotnet-reportgenerator-globaltool
    reportgenerator `
      -reports:./src/WsusManager.Tests/TestResults/**/coverage.cobertura.xml `
      -targetdir:./CoverageReport `
      -reporttypes:HtmlInline
```

**Upload coverage artifact**:
```yaml
- name: Upload coverage report
  uses: actions/upload-artifact@v4
  with:
    name: code-coverage-report
    path: ./CoverageReport/
```

**Optional: Coverage PR comments** (using third-party actions like `codecov/codecov-action` or `irongut/CodeCoverageSummary`):
- Not required for this phase (can be added later)
- Focus on artifact upload for manual review

### 5. Exclusions Configuration

**Exclude test projects and generated code**:

Via `coverlet.runsettings` file:
```xml
<?xml version="1.0" encoding="utf-8"?>
<RunSettings>
  <DataCollectionRunSettings>
    <DataCollectors>
      <DataCollector friendlyName="XPlat Code Coverage">
        <Configuration>
          <Format>cobertura</Format>
          <Exclude>[*Tests]*</Exclude>
          <ExcludeByAttribute>Obsolete,GeneratedCode,CompilerGenerated</ExcludeByAttribute>
          <ExcludeByFile>**/*.Designer.cs;**/*.g.cs;**/*.g.i.cs</ExcludeByFile>
          <IncludeTestAssembly>false</IncludeTestAssembly>
        </Configuration>
      </DataCollector>
    </DataCollectors>
  </DataCollectionRunSettings>
</RunSettings>
```

**Command line usage**:
```bash
dotnet test --settings coverlet.runsettings --collect:"XPlat Code Coverage"
```

### 6. Edge Case Testing Patterns

**Null inputs**:
```csharp
[Fact]
public async Task MethodName_Throws_When_Input_Is_Null()
{
    await Assert.ThrowsAsync<ArgumentNullException>(
        () => _service.MethodName(null!));
}
```

**Empty collections**:
```csharp
[Fact]
public void MethodName_Returns_Empty_When_Collection_Is_Empty()
{
    var result = _service.MethodName([]);
    Assert.Empty(result);
}
```

**Boundary values**:
```csharp
[Theory]
[InlineData(0)]
[InlineData(1)]
[InlineData(int.MaxValue)]
public void MethodName_Handles_Boundary_Values(int value)
{
    var result = _service.MethodName(value);
    Assert.NotNull(result);
}
```

**Exception paths**:
```csharp
[Fact]
public async Task MethodName_Catches_SqlException_And_Returns_Fail_Result()
{
    _mockDb.Setup(x => x.ExecuteAsync(It.IsAny<string>()))
        .ThrowsAsync(new SqlException("Connection failed", null, 1));

    var result = await _service.MethodName();

    Assert.False(result.IsSuccess);
}
```

### 7. Local Developer Workflow

**One-command coverage report**:
```bash
dotnet test src/WsusManager.Tests/WsusManager.Tests.csproj --collect:"XPlat Code Coverage" && reportgenerator -reports:./src/WsusManager.Tests/TestResults/**/coverage.cobertura.xml -targetdir:./CoverageReport -reporttypes:HtmlInline
```

**Open report automatically** (PowerShell):
```powershell
dotnet test --collect:"XPlat Code Coverage" && reportgenerator -reports:./TestResults/**/coverage.cobertura.xml -targetdir:./CoverageReport -reporttypes:HtmlInline; Start-Process ./CoverageReport/index.html
```

## Decision Points for Planning

### 1. ReportGenerator Version
- Use latest stable from NuGet (currently 5.x)
- Install as global tool for consistent CI/developer experience
- Alternative: Local tool manifest (`.config/dotnet-tools.json`) for project-specific versioning

### 2. Coverage Thresholds
- **Context decision: 70% minimum branch coverage** (from CONTEXT.md)
- Higher threshold (80%) for critical Core services (optional refinement)
- Build fails if below threshold (quality gate)

### 3. Report Storage
- CI: Upload as GitHub Actions artifact (retained 90 days by default)
- Local: Generate in `./CoverageReport/` (gitignored)
- No external hosting required (developers download from CI or generate locally)

### 4. Scope of Coverage
- Cover `WsusManager.Core` (critical business logic)
- Cover `WsusManager.App` (ViewModels, services)
- Exclude test projects, generated code, third-party dependencies
- Focus on production code quality

### 5. Edge Case Testing Strategy
- **Audit existing tests** for missing edge cases (null, empty, boundaries)
- **Add tests for exception paths** (SqlException, IOException, etc.)
- **Prioritize high-risk areas**: Database operations, service management, file I/O
- **Unit tests only** (integration tests excluded from coverage reporting per CONTEXT.md)

## Implementation Considerations

### Platform Compatibility
- ReportGenerator is cross-platform (.NET tool)
- HTML reports viewable in any modern browser
- No Windows-specific dependencies

### Performance Impact
- Coverage collection adds ~10-20% to test execution time
- HTML generation is fast (<5 seconds for typical project)
- No impact on runtime application performance

### Maintenance
- ReportGenerator updates via `dotnet tool update`
- Coverlet updates via NuGet package updates
- Coverage thresholds configured in one place (`Directory.Build.props`)

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Coverage below threshold initially | Set threshold at current baseline + 5%, increment over time |
| Large HTML report files | Use `HtmlInline` for source highlighting; consider `Html` summary only if slow |
| CI timeout with coverage | Coverage collection is fast; add separate step if needed |
| Generated code inflates coverage | Exclude via `[ExcludeByFile]` patterns |

## Success Criteria Alignment

| Success Criterion | Research Finding |
|-------------------|-------------------|
| Developer can run `dotnet test` and generate HTML coverage report | `dotnet test --collect:"XPlat Code Coverage"` + ReportGenerator |
| CI/CD pipeline produces coverage HTML artifact | GitHub Actions artifact upload |
| Coverage report includes line/branch coverage | Coverlet collects both; ReportGenerator displays both |
| Edge cases explicitly tested | Patterns documented; audit existing tests |
| Exception handling paths tested | Exception path patterns documented; audit existing tests |

## Next Steps for Planning

1. **Create 3 plans** (based on natural delivery boundaries):
   - Plan 1: Coverage Infrastructure (Coverlet config, ReportGenerator, CI integration)
   - Plan 2: Edge Case Testing (audit, add missing tests)
   - Plan 3: Exception Path Testing (audit, add missing tests)

2. **Configuration files to create**:
   - `coverlet.runsettings` - Coverage collection configuration
   - Update `Directory.Build.props` - Thresholds and exclusions
   - Update `.github/workflows/build-csharp.yml` - CI coverage steps

3. **Test categories to expand**:
   - Null input handling (especially in public service methods)
   - Empty collection handling (lists, dictionaries, arrays)
   - Boundary value testing (int ranges, string lengths, collection sizes)
   - Exception path testing (SqlException, IOException, WinRM exceptions)

## References and Sources

- [Coverlet GitHub Documentation](https://github.com/coverlet-coverage/coverlet)
- [ReportGenerator Documentation](https://github.com/danielpalme/ReportGenerator)
- [.NET 8 Testing Documentation](https://learn.microsoft.com/en-us/dotnet/core/testing/unit-testing-with-dotnet-test)
- [xUnit Documentation](https://xunit.net/docs/getting-started/netcore/cmdline)

---

*Research complete. Ready for planning phase.*
*Phase: 18-test-coverage-reporting*
