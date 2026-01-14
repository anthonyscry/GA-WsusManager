# WSUS Manager

**Version:** 3.8.7
**Author:** Tony Tran, ISSO, Classified Computing, GA-ASI

A comprehensive PowerShell-based automation suite for Windows Server Update Services (WSUS) with SQL Server Express 2022. Provides both a modern WPF GUI application and CLI scripts for managing WSUS servers, including support for air-gapped networks.

## Features

- **Modern WPF GUI** - Dark theme dashboard with real-time status monitoring
- **Health Monitoring** - Automated health checks with auto-recovery capabilities
- **Database Maintenance** - Deep cleanup, index optimization, and backup/restore
- **Air-Gap Support** - Export/import operations for offline networks
- **Scheduled Maintenance** - Automated monthly maintenance with configurable profiles
- **HTTPS/SSL Support** - Easy SSL certificate configuration

## Quick Start

### Download Pre-built EXE

1. Go to the [Releases](../../releases) page
2. Download `WsusManager-vX.X.X.zip`
3. Extract to `C:\WSUS\` (recommended) or any folder
4. Run `WsusManager.exe` as Administrator

**Important:** Keep the `Scripts/` and `Modules/` folders in the same directory as the EXE.

### Building from Source

```powershell
# Clone the repository
git clone https://github.com/anthonyscry/GA-WsusManager.git
cd GA-WsusManager

# Run the build script (requires PS2EXE module)
.\build.ps1

# Output will be in dist/WsusManager.exe
```

Build options:
```powershell
.\build.ps1              # Full build with tests and code review
.\build.ps1 -SkipTests   # Build without running tests
.\build.ps1 -TestOnly    # Run tests only (no build)
```

## Requirements

- **Windows Server** 2016, 2019, 2022, or Windows 10/11
- **PowerShell** 5.1 or later
- **Administrator privileges** (required for WSUS operations)
- **SQL Server Express** 2022 (installed by the Install WSUS feature)

## Project Structure

```
GA-WsusManager/
├── Scripts/                 # PowerShell operation scripts
│   ├── WsusManagementGui.ps1       # Main GUI application
│   ├── Invoke-WsusManagement.ps1   # CLI for all operations
│   ├── Invoke-WsusMonthlyMaintenance.ps1
│   ├── Install-WsusWithSqlExpress.ps1
│   ├── Set-WsusHttps.ps1
│   └── Invoke-WsusClientCheckIn.ps1
├── Modules/                 # Reusable PowerShell modules (11 total)
├── Tests/                   # Pester unit tests (323 tests)
├── DomainController/        # GPO deployment scripts
├── build.ps1               # Build script
└── CLAUDE.md               # Development documentation
```

## CLI Usage

```powershell
# Run health check
.\Scripts\Invoke-WsusManagement.ps1 -Health

# Run health check with auto-repair
.\Scripts\Invoke-WsusManagement.ps1 -Health -Repair

# Run deep cleanup
.\Scripts\Invoke-WsusManagement.ps1 -Cleanup

# Export for air-gapped network
.\Scripts\Invoke-WsusManagement.ps1 -Export -DestinationPath "E:\WSUS-Export"

# Schedule monthly maintenance
.\Scripts\Invoke-WsusManagement.ps1 -Schedule -MaintenanceProfile Full
```

## Documentation

- **[CLAUDE.md](CLAUDE.md)** - Comprehensive development documentation
- **[Modules/README.md](Modules/README.md)** - PowerShell module reference
- **[wiki/](wiki/)** - User guides and troubleshooting

## Testing

```powershell
# Run all tests
Invoke-Pester -Path .\Tests -Output Detailed

# Run specific module tests
Invoke-Pester -Path .\Tests\WsusHealth.Tests.ps1

# Run tests with code coverage
Invoke-Pester -Path .\Tests -CodeCoverage .\Modules\*.psm1
```

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Run tests before committing (`.\build.ps1 -TestOnly`)
4. Commit your changes (`git commit -m 'Add amazing feature'`)
5. Push to the branch (`git push origin feature/amazing-feature`)
6. Open a Pull Request

## License

This project is proprietary software developed for GA-ASI internal use.

## Support

- **Issues:** [GitHub Issues](../../issues)
- **Documentation:** See [CLAUDE.md](CLAUDE.md) for detailed development docs
