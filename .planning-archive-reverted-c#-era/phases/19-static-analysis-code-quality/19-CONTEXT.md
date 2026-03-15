# Phase 19: Static Analysis & Code Quality - Context

**Gathered:** 2026-02-21
**Status:** Ready for planning

## Phase Boundary

Establish compiler-level quality gates using Roslyn analyzers to catch code quality issues at compile time. Configure analyzer packages, set warning severity levels, enforce consistent code style via .editorconfig, and implement incremental adoption to avoid warning fatigue. All warnings must be resolved before release.

## Implementation Decisions

### Analyzer Selection
- **.NET SDK Built-in Analyzers** (EnableNETAnalyzers) — Core code analysis rules
- **Roslynator** (v4.12.0) — Refactoring suggestions and additional rules
- **Meziantou.Analyzer** (v2.0.0) — Security and best practices checks
- **StyleCop.Analyzers** (v1.2.0-beta.556) — Style and naming conventions

**Rationale:** Research establishes these as the standard stack for .NET 8 WPF applications. Each serves a specific purpose without overlap.

### Warning Severity Strategy
- **Critical rules treated as errors:** CA2007 (async patterns), CA1062 (null checks), security rules
- **Recommended rules:** Warnings initially, evaluate for elevation after cleanup
- **Style rules:** IDE-only (refactor suggestions), not blocking
- **WarningsAsErrors:** Specific high-impact rules only, not blanket enable

**Rationale:** Prevents warning fatigue by focusing on critical quality issues first.

### Incremental Adoption
- **Start with:** EnableNETAnalyzers + AnalysisMode:Recommended
- **Phase 1a:** SDK analyzers only, fix critical warnings
- **Phase 1b:** Add Roslynator, address new warnings
- **Phase 1c:** Add Meziantou and StyleCop
- **Final phase:** Evaluate all warnings, elevate key rules to errors

**Rationale:** Research warns that enabling all analyzers immediately produces hundreds of warnings, causing teams to disable them entirely.

### Code Style Configuration
- **.editorconfig** for IDE-agnostic style enforcement
- **Consistent naming:** PascalCase for public members, _camelCase for private fields
- **Indentation:** 4 spaces, K&R style braces
- **File headers:** Standard copyright notice (no per-file headers)
- **Using order:** System imports first, then第三方 (alphabetical)

### Claude's Discretion
- Specific editorconfig formatting rules (indent size, brace style, spacing)
- Whether to add Roslynator's code fixes (can be noisy)
- Exact set of warnings to elevate to errors (based on actual warnings encountered)

## Specific Ideas

- Follow .NET 8 WPF project structure with Directory.Build.props for centralized configuration
- Use `<GenerateDocumentationFile>true</GenerateDocumentationFile>` in .csproj
- Analyzer packages should be in Directory.Build.props, not per-project

## Deferred Ideas

None — discussion stayed within phase scope.

---

*Phase: 19-static-analysis-code-quality*
*Context gathered: 2026-02-21*
