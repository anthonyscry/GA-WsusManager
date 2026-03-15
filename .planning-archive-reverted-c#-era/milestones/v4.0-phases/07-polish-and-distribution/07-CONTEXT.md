# Phase 7: Polish and Distribution - Context

**Gathered:** 2026-02-20
**Status:** Ready for planning

<domain>
## Phase Boundary

Comprehensive xUnit test suite covering all service and ViewModel logic, a GitHub Actions CI/CD pipeline that builds the single-file C# EXE and creates GitHub releases automatically, EXE validation (PE header, 64-bit, version info), and publish validation on Windows Server 2019. This phase does NOT add new features — it validates and packages existing work from Phases 1-6.

</domain>

<decisions>
## Implementation Decisions

### Test Suite Strategy
- Expand existing xUnit test suite (currently ~214 tests) to cover any gaps in service and ViewModel logic
- Target: equivalent coverage to the 323 Pester tests the C# version replaces
- Test structure: `WsusManager.Tests/Services/`, `WsusManager.Tests/ViewModels/`, `WsusManager.Tests/Foundation/`, `WsusManager.Tests/Integration/`
- All tests must pass on Windows (GitHub Actions `windows-latest`) since WPF and Windows APIs are required
- Use Moq for mocking interfaces (already established pattern in existing tests)
- Add EXE validation tests as a separate test class that runs post-build (PE header, 64-bit architecture, version info embedding)

### CI/CD Pipeline
- Create a NEW workflow file `build-csharp.yml` — do NOT modify the existing `build.yml` which handles the PowerShell version
- Trigger on push to `main` branch when `src/**` files change
- Jobs: restore → build → test → publish → validate-exe → create-release
- Use `dotnet publish` with `--self-contained true -r win-x64 -p:PublishSingleFile=true`
- Windows runner required for build (WPF) — use `windows-latest`
- Release job uses `ubuntu-latest` (just creating GitHub release from artifact)

### EXE Metadata and Validation
- Embed version info via MSBuild properties in `.csproj`: `AssemblyVersion`, `FileVersion`, `Product` ("WSUS Manager"), `Company` ("GA-ASI"), `Copyright` ("Tony Tran, ISSO - GA-ASI")
- Version sourced from `Directory.Build.props` or `Version` property in the App `.csproj`
- Post-build validation: PE header (MZ + PE signature), 64-bit architecture (PE32+), version info present, file size reasonable (< 100MB)
- Startup validation: EXE launches without crashing (quick smoke test with timeout)

### Release Automation
- Tag-based releases: pushing a tag like `v4.0.0` triggers release creation
- Also support `workflow_dispatch` with manual version input (matching existing PowerShell workflow pattern)
- Release artifact: single zip containing the self-contained EXE + DomainController/ folder + README
- No Scripts/ or Modules/ folders needed (unlike PowerShell version — single-file EXE is self-contained)
- Release notes template includes: version, what's new summary, download table, requirements (Windows Server 2019+, admin privileges), installation instructions (extract + run)

### Distribution Package Contents
- `WsusManager.exe` — single-file self-contained EXE (no .NET runtime needed)
- `DomainController/` — GPO deployment scripts (still PowerShell, used on Domain Controller)
- `README.md` — Quick start guide
- No `Scripts/` or `Modules/` folders (major simplification over PowerShell version)

### Claude's Discretion
- Exact test count target (aim for 250+ covering all services)
- Whether to add code coverage reporting (Coverlet) to CI
- Whether to include a startup benchmark step in CI
- Exact release notes wording
- Whether to keep the PowerShell `build.yml` or mark it as legacy

</decisions>

<specifics>
## Specific Ideas

- The existing PowerShell `build.yml` triggers on `Scripts/**` and `Modules/**` paths — the new C# workflow should trigger on `src/**` to avoid conflicts
- Existing test files already cover Phases 1-6 services — Phase 7 should audit for gaps and add missing coverage rather than rewriting
- The PowerShell version requires Scripts/ and Modules/ alongside the EXE — the C# version eliminates this deployment complexity entirely
- Version should start at `4.0.0` to clearly distinguish from the PowerShell `3.8.x` lineage

</specifics>

<deferred>
## Deferred Ideas

- None — discussion stayed within phase scope

</deferred>

---

*Phase: 07-polish-and-distribution*
*Context gathered: 2026-02-20*
