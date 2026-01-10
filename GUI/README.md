# WSUS Manager GUI

A modern WPF graphical interface for managing Windows Server Update Services (WSUS).

## Features

- **Dashboard** - Real-time service status, database statistics, and disk space monitoring
- **Services** - Start, stop, and restart WSUS, SQL Server, and IIS services
- **Database** - View stats, restore backups, optimize indexes, and shrink database
- **Health Check** - Comprehensive health diagnostics with auto-repair capability
- **Maintenance** - Deep cleanup and content reset operations
- **Media Transfer** - Import/export for air-gapped environments with archive browser
- **Settings** - Configure paths, SQL instance, and SSL settings

## Requirements

- Windows 10/11 or Windows Server 2016+
- .NET 6.0 Runtime
- PowerShell 7.3+
- WSUS role installed (for full functionality)
- SQL Server Express 2022 (for database operations)

## Building

```bash
cd GUI
dotnet build
```

## Running

```bash
dotnet run
```

Or run the compiled executable:

```bash
.\bin\Debug\net6.0-windows\WsusManager.exe
```

## Architecture

The application follows the MVVM (Model-View-ViewModel) pattern:

```
GUI/
├── Converters/          # Value converters for XAML bindings
├── Helpers/             # Base classes (ViewModelBase, RelayCommand)
├── Models/              # Data models (ServiceStatus, DatabaseStats, etc.)
├── Resources/           # Styles, colors, and assets
├── Services/            # PowerShell interop and WSUS service layer
├── ViewModels/          # View logic and state management
├── Views/               # XAML UI definitions
├── App.xaml             # Application entry point
└── MainWindow.xaml      # Main window with tab navigation
```

### Key Components

**PowerShellService** - Executes PowerShell commands and loads WSUS modules from the parent project's `Modules/` directory.

**WsusService** - High-level wrapper providing typed methods for:
- Service management (start/stop/status)
- Health checks and repairs
- Database operations
- Import/export functionality
- Configuration management

## Integration with PowerShell Modules

The GUI leverages the existing PowerShell modules in `/Modules/`:

- `WsusUtilities.psm1` - Core utilities and logging
- `WsusDatabase.psm1` - Database operations
- `WsusServices.psm1` - Service management
- `WsusHealth.psm1` - Health checking
- `WsusExport.psm1` - Export/import operations
- `WsusFirewall.psm1` - Firewall rules
- `WsusPermissions.psm1` - NTFS permissions
- `WsusConfig.psm1` - Configuration

## Development

### Adding a New Feature

1. Create a ViewModel in `ViewModels/`
2. Create a View (XAML) in `Views/`
3. Add the tab to `MainWindow.xaml`
4. Register the ViewModel in `MainViewModel.cs`

### Styling

Global styles are defined in:
- `Resources/Colors.xaml` - Color palette
- `Resources/Styles.xaml` - Button, text, and control styles

Use the predefined styles:
- `PrimaryButtonStyle` - Blue action buttons
- `SecondaryButtonStyle` - Outlined buttons
- `DangerButtonStyle` - Red destructive action buttons
- `SuccessButtonStyle` - Green confirmation buttons
- `CardStyle` - White card containers with shadow

## License

Same license as the parent WSUS-SQL project.
