# Phase 20: XML Documentation & API Reference - Context

**Gathered:** 2026-02-21
**Status:** Ready for implementation

## Phase Boundary

Add XML documentation comments to all public APIs in WsusManager.Core and WsusManager.App libraries. Enable XML documentation generation in .csproj files, ensuring IntelliSense shows descriptive summaries and all public methods document thrown exceptions with `<exception>` tags.

## Implementation Decisions

### Documentation Scope
- **Public APIs only** — Document `public` and `protected` members
- **Skip:** `private`, `internal`, and `private protected` members use clear naming instead
- **Interfaces and abstract classes** — Document all members (implementations inherit documentation)
- **Public fields and properties** — Document with `<summary>` tags
- **Public methods** — Document with `<summary>`, `<param>`, `<returns>`, and `<exception>` tags

**Rationale:** Internal implementation details don't need XML docs — clear naming is sufficient. Public API surface is what users and maintainers need documented.

### Documentation Depth
- **Summary tags:** Concise one-line description of what the member does
- **Param tags:** Brief description of parameter purpose (not type, which IntelliSense shows)
- **Returns tags:** Description of return value (not type, which signature shows)
- **No code examples in XML** — Keep documentation focused, examples go in separate files
- **No remarks sections** — Unless critical behavioral notes needed

**Rationale:** XML docs should be concise for IntelliSense readability. Code examples and detailed guides belong in README or CONTRIBUTING.md.

### Exception Documentation
- **Required:** All `<exception>` tags for exceptions explicitly thrown in method body
- **Format:** `<exception cref="T:System.ExceptionType">Condition when thrown</exception>`
- **Skip:** Exceptions from dependencies that bubble up (document in calling code instead)
- **Async methods:** Document `OperationCanceledException` and `TaskCanceledException` if cancellation token accepted

**Rationale:** Users need to know what exceptions their code must handle. Bubbled exceptions are implementation details.

### Code Example Policy
- **No code examples in XML comments** — Examples make IntelliSense tooltips unwieldy
- **Examples in CONTRIBUTING.md** — Create separate code samples for complex patterns
- **Simple APIs** — Self-explanatory, no examples needed
- **Complex APIs** — Add `<see cref=""/>` references to related documentation

### Claude's Discretion
- Whether to add `<remarks>` sections for APIs with non-obvious behavior
- Whether `<see cref=""/>` references are needed for related APIs
- Specific wording of summaries (aim for clarity and brevity)
- Whether to document enum values (if not self-explanatory)

## Specific Ideas

- Use consistent wording across similar APIs (e.g., "Asynchronously..." for async methods)
- Follow existing XML doc patterns in the codebase (e.g., IHealthService)
- Enable `GenerateDocumentationFile=true` in .csproj for XML doc generation
- Treat missing `<exception>` tags as analyzer warnings (enable CS1591)

## Deferred Ideas

None — discussion stayed within phase scope.

---

*Phase: 20-xml-documentation-api-reference*
*Context gathered: 2026-02-21*
