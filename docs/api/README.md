# API Documentation

This directory contains generated API reference documentation.

## Regenerating Documentation

To regenerate the API documentation after code changes:

```bash
# Install DocFX (first time only)
dotnet tool install -g docfx

# Or use local tool (recommended)
dotnet tool run docfx docfx.json

# Generate documentation
dotnet docfx docfx.json

# View locally (auto-opens browser)
# Note: Run from repository root
dotnet docfx docfx.json --serve
```

## Documentation Source

API documentation is generated from XML documentation comments in the source code. To update API documentation:

1. Edit XML comments in `.cs` files
2. Rebuild the solution
3. Run `dotnet docfx docfx.json`
4. Commit generated changes

## Adding XML Documentation

All public APIs should have XML documentation comments:

```csharp
/// <summary>
/// Brief summary of what this API does.
/// </summary>
/// <param name="paramName">Description of parameter.</param>
/// <returns>Description of return value.</returns>
/// <exception cref="T:System.ExceptionType">Condition when thrown.</exception>
public async Task<Result> MyApiAsync(string paramName, CancellationToken cancellationToken)
{
    // ...
}
```

See Phase 20 (XML Documentation & API Reference) for XML documentation guidelines.

## Hosting

### GitHub Pages (Future)

To host on GitHub Pages:

1. Enable GitHub Pages for repository (Settings → Pages)
2. Set source to `docs/` folder
3. Push to main branch
4. Documentation publishes automatically

### Local Viewing

Open `docs/api/api/index.html` in a web browser to view documentation locally.

## Versioning

API documentation is version-specific. Each release generates documentation for that version:

- v4.4.0: Current stable release
- Older versions: Archived in separate branches if needed
