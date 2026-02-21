# WSUS Manager API Reference

Welcome to the WSUS Manager API documentation. This site provides comprehensive reference documentation for all public APIs in WsusManager.Core and WsusManager.App.

## Getting Started

- **WsusManager.Core** - Core library with business logic, services, and models
- **WsusManager.App** - WPF application with ViewModels and Views

## Key Namespaces

### WsusManager.Core.Services

Service interfaces and implementations for WSUS operations:

- **IHealthService** - Health check and diagnostics
- **ISqlService** - SQL Server operations (cleanup, restore)
- **ISyncService** - WSUS synchronization operations
- **IWindowsServiceManager** - Windows service management
- **IFirewallService** - Firewall rule management
- **IClientService** - WinRM client operations
- **IDatabaseBackupService** - Database backup and restore
- **IDeepCleanupService** - Deep database cleanup and optimization
- **IExportService** - Export operations for air-gap transfers
- **IImportService** - Import operations for air-gap transfers

### WsusManager.Core.Models

Data models for WSUS entities:

- **OperationResult** - Standard operation result
- **ProcessResult** - Process execution result
- **DashboardData** - Dashboard information
- **AppSettings** - Application settings
- **DiagnosticCheckResult** - Individual diagnostic check result
- **DiagnosticReport** - Complete diagnostic report
- **ExportOptions** - Export operation options
- **ImportOptions** - Import operation options
- **SyncProfile** - Sync configuration profiles
- **SyncResult** - Synchronization result

### WsusManager.App.ViewModels

MVVM view models for UI logic:

- **MainViewModel** - Main application view model
- **SettingsViewModel** - Settings dialog view model
- **DiagnosticsViewModel** - Diagnostics panel view model

## Architecture

WSUS Manager follows the MVVM pattern with CommunityToolkit.Mvvm:

1. **Models** (WsusManager.Core) - Business entities
2. **Services** (WsusManager.Core) - Business logic and external operations
3. **ViewModels** (WsusManager.App) - UI state and commands
4. **Views** (WsusManager.App) - XAML UI definition

## Version

Current API documentation is for **WSUS Manager v4.4.0**.

## License

This project is proprietary software developed for GA-ASI internal use.
