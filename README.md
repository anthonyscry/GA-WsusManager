# WSUS Manager

**Version:** 4.0.0
**Author:** Tony Tran, ISSO, Classified Computing, GA-ASI

A comprehensive C# WPF automation suite for Windows Server Update Services (WSUS) with SQL Server Express 2022. Single-file EXE distribution with dark-themed dashboard, real-time diagnostics, theme picker, and air-gap support.

## Features

### Core Capabilities
- **Modern WPF GUI** - Native C# WPF application with MVVM architecture and CommunityToolkit.Mvvm
- **Real-Time Dashboard** - Auto-refreshing status (30-second interval) for WSUS service, SQL connection, and update counts
- **Unified Diagnostics** - Comprehensive health checks with automatic repair (services, firewall, permissions, SQL)
- **Deep Cleanup** - Full database maintenance including supersession cleanup, index optimization, and compaction
- **Air-Gap Support** - Export/import operations for offline networks with differential copy support

### User Experience
- **Theme Picker** - Six built-in themes (DefaultDark, Slate, ClassicBlue, Serenity, Rose, JustBlack)
- **Operation Progress** - Step-by-step feedback with success/failure banners
- **Editable Settings** - All settings configurable via GUI with immediate effect
- **Expandable Log Panel** - Smooth expand/collapse with real-time operation output

### Client Management
- **WinRM Integration** - Remote client check-in, diagnostics, GPUpdate, and script generation
- **GPO Deployment** - Built-in GPO creation with detailed DC admin instructions
- **Client Tools** - Comprehensive remote management for WSUS clients

### Automation
- **Scheduled Tasks** - Profile-based online sync with configurable intervals
- **Single-File EXE** - Self-contained distribution (no Scripts/Modules folders required)
- **Fast Startup** - 5x faster than PowerShell version (200-400ms vs 1-2s)

## Quick Start

### Download Pre-built EXE

1. Go to the [Releases](../../releases) page
2. Download `WsusManager-vX.X.X.zip`
3. Extract to any folder
4. Run `WsusManager.exe` as Administrator

**Note:** The C# version is a single-file EXE with all dependencies embedded. No Scripts/ or Modules/ folders required.

### Building from Source

```bash
# Clone the repository
git clone https://github.com/anthonyscry/GA-WsusManager.git
cd GA-WsusManager

# Restore NuGet packages
cd src
dotnet restore

# Build in Release configuration
dotnet build --configuration Release

# Publish single-file EXE
dotnet publish src/WsusManager.App/WsusManager.App.csproj \
  --configuration Release \
  --output publish \
  --self-contained true \
  --runtime win-x64 \
  -p:PublishSingleFile=true

# Single-file EXE output:
# publish/WsusManager.exe
```

**Prerequisites:**
- .NET 8.0 SDK
- Windows 10/11 or Windows Server 2019+
- Visual Studio 2022 (optional, for development)

## Requirements

- **Operating System:** Windows 10/11 or Windows Server 2019/2022
- **.NET Desktop Runtime:** 8.0 or later (included with self-contained EXE, or install separately)
- **Administrator Privileges:** Required for WSUS operations
- **WSUS Components:** SQL Server Express 2022 (installed by Install WSUS feature)

## Screenshots

### Dashboard
*Screenshot to be added - See [docs/screenshots/README.md](docs/screenshots/README.md) for details*

Real-time status monitoring with auto-refresh every 30 seconds.

### Diagnostics
*Screenshot to be added - See [docs/screenshots/README.md](docs/screenshots/README.md) for details*

Comprehensive health scanning with automatic repair for services, firewall, permissions, and SQL.

### Settings
*Screenshot to be added - See [docs/screenshots/README.md](docs/screenshots/README.md) for details*

Configurable settings with theme picker and immediate effect.

### Air-Gap Transfer
*Screenshot to be added - See [docs/screenshots/README.md](docs/screenshots/README.md) for details*

Export/import operations for air-gapped networks with differential copy support.

## Usage

### GUI Application

Run `WsusManager.exe` as Administrator. The main dashboard shows:

- **Server Status:** WSUS service, SQL connection, update counts
- **Quick Actions:** Start Services, Diagnostics, Online Sync
- **Navigation:** Dashboard, Diagnostics, Database, WSUS Operations, Install, Schedule, Client Tools, Settings

**Common Workflows:**

1. **First-time Setup:** Click "Install WSUS" and follow the wizard
2. **Health Check:** Click "Diagnostics" to scan and auto-fix issues
3. **Database Cleanup:** Navigate to Database → "Deep Cleanup"
4. **Air-Gap Sync:** Navigate to WSUS Operations → "Transfer" → Export/Import
5. **Client Management:** Navigate to Client Tools → select operation

**Note:** CLI interface is planned for v4.5. Use GUI for all operations.

### Themes

Switch themes via Settings → Theme Picker:
- **DefaultDark** - Clean dark theme with blue accents
- **Slate** - Professional gray-blue theme
- **ClassicBlue** - Traditional Windows blue
- **Serenity** - Calming teal and gray
- **Rose** - Warm rose and slate
- **JustBlack** - Minimal high-contrast black

## Troubleshooting

### "WSUS service not installed"
**Cause:** WSUS role not installed on server
**Solution:** Install WSUS role via Server Manager or click "Install WSUS" button

### "Cannot connect to SQL Server"
**Cause:** SQL Server service not running
**Solution:** Run Diagnostics → auto-starts SQL service

### "Access denied" errors
**Cause:** Not running as Administrator
**Solution:** Right-click EXE → "Run as administrator"

### "Content is still downloading" after restore
**Cause:** WSUS re-verifying content files (can take 30+ minutes)
**Solution:** Wait for completion, or run "Reset Content" to force re-verification

### WinRM operations fail
**Cause:** WinRM not enabled on remote host
**Solution:** Enable WinRM: `Enable-PSRemoting -Force` on target machine

### Application won't start
**Cause:** .NET Desktop Runtime 8.0 not installed
**Solution:** Download from https://dotnet.microsoft.com/download/dotnet/8.0

### Large file deletion hangs
**Cause:** SQL transaction log full during mass update deletion
**Solution:** Run Diagnostics to shrink log, or use "Deep Cleanup" which handles this automatically

## Project Structure

```
GA-WsusManager/
├── src/
│   ├── WsusManager.Core/       # Core library (business logic)
│   │   ├── Services/           # Service implementations
│   │   ├── Models/             # Data models
│   │   ├── Infrastructure/     # Utilities (logging, admin checks)
│   │   └── Logging/            # Serilog configuration
│   ├── WsusManager.App/        # WPF application
│   │   ├── ViewModels/         # MVVM view models
│   │   ├── Views/              # XAML views
│   │   ├── Themes/             # Theme resource dictionaries
│   │   └── Services/           # DI services
│   ├── WsusManager.Tests/      # xUnit tests
│   └── WsusManager.Benchmarks/ # BenchmarkDotNet performance tests
├── docs/                       # Documentation
│   └── screenshots/            # UI screenshots
├── .github/workflows/          # CI/CD pipelines
├── CLAUDE.md                   # Development documentation
├── CONTRIBUTING.md             # Contribution guidelines
└── README.md                   # This file
```

## Documentation

- **[CLAUDE.md](CLAUDE.md)** - Development documentation (legacy PowerShell info retained for reference)
- **[CONTRIBUTING.md](CONTRIBUTING.md)** - Contribution guidelines, build instructions, code style
- **[docs/ci-cd.md](docs/ci-cd.md)** - CI/CD pipeline documentation, workflows, and troubleshooting
- **[docs/releases.md](docs/releases.md)** - Release process and versioning
- **[CHANGELOG.md](CHANGELOG.md)** - Version history and feature notes
- **[docs/architecture.md](docs/architecture.md)** - C# architecture, MVVM pattern, DI, and design decisions
- **[docs/api/](docs/api/)** - API reference documentation (to be generated via DocFX)

## Testing

```bash
# Run all tests
cd src
dotnet test --verbosity normal

# Run specific test project
dotnet test WsusManager.Tests

# Run tests with code coverage
dotnet test --collect:"XPlat Code Coverage"

# Generate coverage report
reportgenerator -reports:*/coverage.cobertura.xml -targetdir:coverage-report
```

## Performance Benchmarking

The C# version includes BenchmarkDotNet performance testing for tracking critical operations.

### Running Benchmarks Locally

```bash
# Run all benchmarks (requires Windows)
dotnet run --project src/WsusManager.Benchmarks/WsusManager.Benchmarks.csproj -c Release

# Run specific benchmark category
dotnet run --project src/WsusManager.Benchmarks/WsusManager.Benchmarks.csproj -c Release --filter "*Startup*"
dotnet run --project src/WsusManager.Benchmarks/WsusManager.Benchmarks.csproj -c Release --filter "*Database*"
dotnet run --project src/WsusManager.Benchmarks/WsusManager.Benchmarks.csproj -c Release --filter "*WinRM*"
```

### Benchmark Results

Results are generated in `src/WsusManager.Benchmarks/BenchmarkDotNet.Artifacts/`:
- `results.html` - Interactive HTML report with charts
- `results.csv` - Raw timing data for regression detection

### CI/CD Benchmarks

BenchmarkDotNet runs are triggered manually via GitHub Actions:
1. Navigate to **Actions** → **Build C# WSUS Manager**
2. Click **Run workflow**
3. Select branch and click **Run workflow**
4. Download `benchmark-results` artifact when complete

### Performance Regressions

Builds fail if performance degrades >10% from baseline. Baselines are stored in `src/WsusManager.Benchmarks/baselines/`:
- `startup-baseline.csv` - Cold/warm startup times
- `database-baseline.csv` - Query and connection times
- `winrm-baseline.csv` - WinRM operation times

### Updating Baselines

If performance legitimately changes (e.g., new features), update baselines:
```bash
# Run benchmarks
dotnet run --project src/WsusManager.Benchmarks/WsusManager.Benchmarks.csproj -c Release

# Copy new results to baselines
cp src/WsusManager.Benchmarks/BenchmarkDotNet.Artifacts/results-*-report.csv src/WsusManager.Benchmarks/baselines/
```

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Run tests before committing (`dotnet test`)
4. Commit your changes (`git commit -m 'Add amazing feature'`)
5. Push to the branch (`git push origin feature/amazing-feature`)
6. Open a Pull Request

### Code Style

- Follow .editorconfig settings (enforced via Roslyn analyzers)
- Use XML documentation comments for public APIs
- Run `dotnet format` before committing
- Target 70% branch coverage for new code

## Important Notes

### Database Restore / Reset Time

After restoring a WSUS database or performing a reset operation, the WSUS server will need to re-verify and re-download update content. **This process can take 30+ minutes depending on the size of your update content.** During this time:

- The dashboard may show "Update is downloading" status
- This is normal behavior - do not interrupt the process
- Content verification happens automatically in the background
- Large content stores (50GB+) may take several hours to fully re-verify

### Performance Metrics

Compared to PowerShell v3.8.x:
- **5x faster startup** (200-400ms vs 1-2s)
- **2.5x faster operations** (health check: ~2s vs ~5s)
- **3x less memory** (50-80MB vs 150-200MB)
- **52% less code** (1,180 vs 2,482 LOC)

## License

This project is proprietary software developed for GA-ASI internal use.

## Support

- **Issues:** [GitHub Issues](../../issues)
- **Documentation:** See [CLAUDE.md](CLAUDE.md) for detailed development docs
