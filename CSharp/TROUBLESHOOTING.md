# WSUS Manager C# - Troubleshooting Guide

**For developers and AI assistants debugging the C# port**

---

## 🏗️ Project Structure

```
CSharp/
├── src/
│   ├── WsusManager.Core/          # Core business logic library
│   │   ├── Database/              # SQL operations
│   │   ├── Health/                # Health checking
│   │   ├── Services/              # Windows service management
│   │   ├── Operations/            # Export/Import operations
│   │   └── Utilities/             # Logging, admin checks
│   │
│   └── WsusManager.Gui/           # WPF GUI application
│       ├── MainWindow.xaml        # UI layout (sidebar nav, dashboard, log panel)
│       ├── ViewModels/            # MVVM view models
│       │   └── MainViewModel.cs   # Main app logic
│       └── Views/                 # Dialog windows
│
└── tests/
    └── WsusManager.Tests/         # xUnit tests
```

---

##Build Errors & Fixes

### Error: "The type or namespace name 'X' could not be found"

**Cause:** Missing using directive or NuGet package

**Fix:**
```csharp
// Add to top of file:
using System.IO;              // For StringWriter
using System.Windows;         // For WPF types
using Ookii.Dialogs.Wpf;      // For VistaFolderBrowserDialog
using Microsoft.Win32;        // For OpenFileDialog
```

**Check NuGet packages in `.csproj`:**
```xml
<PackageReference Include="CommunityToolkit.Mvvm" Version="8.2.2" />
<PackageReference Include="Ookii.Dialogs.Wpf" Version="5.0.1" />
<PackageReference Include="Microsoft.Data.SqlClient" Version="5.1.5" />
```

---

### Error: "Operator '??' cannot be applied to operands of type 'int' and 'int'"

**Cause:** Non-nullable type used with null-coalescing operator

**Fix:**
```csharp
// ❌ WRONG
var result = await ExecuteScalarAsync<int>(query);
return result ?? 0;

// ✅ CORRECT
var result = await ExecuteScalarAsync<int?>(query);
return result ?? 0;
```

---

### Error: "Could not find file 'wsus-icon.ico'"

**Cause:** Icon file missing from project

**Fix:**
```bash
# Copy from PowerShell project root
cp /path/to/repo/wsus-icon.ico CSharp/src/WsusManager.Gui/

# Or remove from .csproj:
<ApplicationIcon>wsus-icon.ico</ApplicationIcon>
```

---

### Error: "GridLength is not defined"

**Cause:** Missing namespace for WPF types

**Fix:**
```csharp
using System.Windows;  // Contains GridLength

// Usage:
[ObservableProperty]
private GridLength _logPanelHeight = new GridLength(250);
```

---

## 🐛 Runtime Errors & Fixes

### Error: "RepairHealthAsync method not found"

**Cause:** Old HealthChecker signature

**Current signature:**
```csharp
public async Task<HealthRepairResult> RepairHealthAsync(string contentPath = @"C:\WSUS")
```

**Fix:**
```csharp
// Call with content path:
var result = await _healthChecker.RepairHealthAsync(_contentPath);
```

---

### Error: "Services property doesn't exist on HealthCheckResult"

**Current HealthCheckResult structure:**
```csharp
public class HealthCheckResult
{
    public string Overall { get; set; }  // "Healthy", "Degraded", "Unhealthy"
    public Dictionary<string, ServiceStatus> Services { get; set; }
    public DatabaseConnectionResult? Database { get; set; }
    public List<string> Issues { get; set; }
}
```

---

### App crashes on startup with "Access Denied"

**Cause:** App must run as Administrator (WSUS operations require admin)

**Fix:**
1. Right-click EXE
2. Select "Run as administrator"

**Or add to `app.manifest`:**
```xml
<requestedExecutionLevel level="requireAdministrator" uiAccess="false" />
```

---

### Dashboard shows "Unknown" for all values

**Cause:** SQL Server not running or connection failed

**Check:**
```powershell
# Verify SQL Server is running
Get-Service MSSQL$SQLEXPRESS

# Test connection
sqlcmd -S .\SQLEXPRESS -E -Q "SELECT @@VERSION"
```

**Fix in code:**
```csharp
// Constructor uses default SQL instance
private string _sqlInstance = @".\SQLEXPRESS";

// Change if using different instance:
private string _sqlInstance = @"localhost\SQLEXPRESS";
```

---

### Button clicks do nothing

**Cause:** Command not wired up in XAML or CanExecute returns false

**Check XAML binding:**
```xml
<Button Content="Health Check"
        Command="{Binding RunHealthCheckCommand}"/>  <!-- Must match [RelayCommand] name -->
```

**Check CanExecute:**
```csharp
[RelayCommand(CanExecute = nameof(CanExecuteOperation))]
private async Task RunHealthCheckAsync() { ... }

private bool CanExecuteOperation() => !IsOperationRunning;  // Returns false when operation running
```

---

### Log panel doesn't expand

**Cause:** IsLogPanelExpanded binding or GridLength not updating

**Check bindings:**
```xml
<RowDefinition Height="{Binding LogPanelHeight}"/>  <!-- Must be GridLength type -->

<ScrollViewer Visibility="{Binding IsLogPanelExpanded, Converter={StaticResource BoolToVis}}">
```

**Ensure BooleanToVisibilityConverter is defined:**
```xml
<Window.Resources>
    <BooleanToVisibilityConverter x:Key="BoolToVis"/>
</Window.Resources>
```

---

### Operations appear to run but no output in log

**Cause:** Console output not captured or AppendLog not called

**Verify pattern:**
```csharp
await RunOperationAsync("Operation Name", async () =>
{
    AppendLog("=== Starting Operation ===");  // This shows in log

    // Capture console output:
    var originalOut = Console.Out;
    using var writer = new StringWriter();
    Console.SetOut(writer);

    try
    {
        // ... operation code that writes to Console ...
        var output = writer.ToString();
        AppendLog(output);  // Append captured output
        return true;
    }
    finally
    {
        Console.SetOut(originalOut);  // Restore original
    }
});
```

---

## 🎨 UI Issues & Fixes

### Sidebar buttons not highlighting on hover

**Cause:** Missing NavBtn style triggers

**Check XAML:**
```xml
<Style x:Key="NavBtn" TargetType="Button">
    <Setter Property="Background" Value="Transparent"/>
    <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
            <Setter Property="Background" Value="{StaticResource BgCard}"/>
            <Setter Property="Foreground" Value="{StaticResource Text1}"/>
        </Trigger>
    </Style.Triggers>
</Style>
```

---

### Colors don't match PowerShell app

**PowerShell colors (from v3.8.3):**
```xml
<SolidColorBrush x:Key="BgMain" Color="#0D1117"/>      <!-- Main background -->
<SolidColorBrush x:Key="BgSidebar" Color="#161B22"/>   <!-- Sidebar -->
<SolidColorBrush x:Key="BgCard" Color="#21262D"/>      <!-- Cards -->
<SolidColorBrush x:Key="Text1" Color="#E6EDF3"/>       <!-- Primary text -->
<SolidColorBrush x:Key="Text2" Color="#8B949E"/>       <!-- Secondary text -->
<SolidColorBrush x:Key="Blue" Color="#58A6FF"/>        <!-- Accent -->
<SolidColorBrush x:Key="Green" Color="#3FB950"/>       <!-- Success -->
<SolidColorBrush x:Key="Red" Color="#F85149"/>         <!-- Error -->
```

---

### Dashboard cards not responsive to service status

**Cause:** DataTriggers not updating or binding path incorrect

**Example card binding:**
```xml
<TextBlock Text="{Binding ServicesStatus}">  <!-- e.g., "3/3 Running" -->
    <TextBlock.Style>
        <Style TargetType="TextBlock">
            <Style.Triggers>
                <DataTrigger Binding="{Binding AllServicesRunning}" Value="True">
                    <Setter Property="Foreground" Value="{StaticResource Green}"/>
                </DataTrigger>
                <DataTrigger Binding="{Binding AllServicesRunning}" Value="False">
                    <Setter Property="Foreground" Value="{StaticResource Red}"/>
                </DataTrigger>
            </Style.Triggers>
        </Style>
    </TextBlock.Style>
</TextBlock>
```

**ViewModel must update properties:**
```csharp
ServicesStatus = $"{running}/{total} Running";  // Updates text
AllServicesRunning = (running == total);        // Updates color trigger
```

---

## 🔧 Common Development Tasks

### Adding a new operation

1. **Add command to ViewModel:**
```csharp
[RelayCommand(CanExecute = nameof(CanExecuteOperation))]
private async Task MyOperationAsync()
{
    await RunOperationAsync("My Operation", async () =>
    {
        AppendLog("=== Starting My Operation ===");
        // ... operation logic ...
        return true;  // or false if failed
    });
}
```

2. **Add button to XAML:**
```xml
<Button Content="🔧 My Operation"
        Style="{StaticResource NavBtn}"
        Command="{Binding MyOperationCommand}"/>
```

3. **Operation will automatically:**
   - Disable other buttons
   - Expand log panel
   - Show progress in status bar
   - Handle errors with message box
   - Re-enable buttons on completion

---

### Adding a dialog

**Simple approach (inline):**
```csharp
var dialog = new Window
{
    Title = "My Dialog",
    Width = 400,
    Height = 300,
    WindowStartupLocation = WindowStartupLocation.CenterOwner,
    Owner = Application.Current.MainWindow
};

var panel = new StackPanel { Margin = new Thickness(20) };
// ... add controls ...
dialog.Content = panel;

if (dialog.ShowDialog() == true)
{
    // User clicked OK
}
```

**Complex approach (separate file):**
```csharp
// Create Views/MyDialog.xaml and Views/MyDialog.xaml.cs
var dialog = new MyDialog { Owner = Application.Current.MainWindow };
if (dialog.ShowDialog() == true)
{
    var result = dialog.SelectedValue;
    // ... use result ...
}
```

---

### Debugging dashboard refresh

**Add breakpoints in:**
```csharp
private async Task RefreshDashboardAsync()
{
    try
    {
        var services = ServiceManager.GetWsusServiceStatus();  // ← Breakpoint here

        int running = services.Count(s => s.Value.Running);
        ServicesStatus = $"{running}/{total} Running";  // ← And here

        var dbSize = await _database.GetDatabaseSizeAsync();  // ← And here
        DatabaseSize = $"{dbSize:F2} GB";
    }
    catch (Exception ex)
    {
        StatusMessage = $"Refresh failed: {ex.Message}";  // ← Check exception
    }
}
```

**Manual refresh:**
- Click "Refresh Dashboard" button in header
- Or call from Dev Tools console (if enabled)

---

## 📦 NuGet Package Issues

### "Package 'Ookii.Dialogs.Wpf' not found"

**Fix:**
```bash
dotnet add package Ookii.Dialogs.Wpf --version 5.0.1
```

### "Package restore failed"

**Fix:**
```bash
dotnet restore CSharp/WsusManager.sln
```

### "Version conflict"

**Check all `.csproj` files use same .NET version:**
```xml
<TargetFramework>net8.0-windows</TargetFramework>
```

---

## 🚀 GitHub Actions Build Issues

### Build fails with "dotnet not found"

**Cause:** Missing `setup-dotnet` step

**Fix in `.github/workflows/build-csharp-poc.yml`:**
```yaml
- name: Setup .NET
  uses: actions/setup-dotnet@v4
  with:
    dotnet-version: '8.0.x'
```

### Build succeeds but artifact is empty

**Check publish output path:**
```yaml
- name: Publish GUI
  run: |
    dotnet publish ... --output CSharp/publish/gui

- name: Upload artifacts
  uses: actions/upload-artifact@v4
  with:
    path: CSharp/dist/  # Must match Create distribution step
```

---

## 🧪 Testing

### Running unit tests locally

```bash
cd CSharp
dotnet test --verbosity normal
```

### Running specific test

```bash
dotnet test --filter "FullyQualifiedName~DatabaseOperationsTests"
```

### Debugging tests in Visual Studio

1. Open CSharp/WsusManager.sln
2. Go to Test Explorer
3. Right-click test → Debug

---

## 📖 Key Differences from PowerShell Version

| Feature | PowerShell | C# |
|---------|-----------|-----|
| **Async operations** | `Register-ObjectEvent` + `Dispatcher.Invoke` | `async/await` (native) |
| **Dialogs** | Manually create XAML in code | Ookii.Dialogs or separate .xaml files |
| **Error handling** | `try/catch` with manual logging | Centralized in `RunOperationAsync` |
| **Service status** | Re-query every time | Cached with 30s refresh |
| **Log panel** | Fixed height or hidden | Smooth expand/collapse with GridLength |
| **Settings** | `%APPDATA%\WsusManager\settings.json` | Same (not yet implemented) |
| **Theme** | Embedded XAML string | Resource dictionary in MainWindow.xaml |

---

## 🎯 Quick Fixes Checklist

When app doesn't work:

- [ ] Running as Administrator?
- [ ] SQL Server Express installed and running?
- [ ] SUSDB database exists?
- [ ] All NuGet packages restored?
- [ ] Icon file exists (or reference removed)?
- [ ] XAML bindings match ViewModel property names exactly?
- [ ] `[ObservableProperty]` attributes on all bound properties?
- [ ] Commands have `[RelayCommand]` attribute?
- [ ] CanExecute method exists and returns true?

---

## 📞 Getting Help

**Check logs:**
- Operations log in app (bottom panel)
- Visual Studio Output window
- Event Viewer → Windows Logs → Application

**Common log messages:**
```
"Access Denied" → Run as Administrator
"SQL Server not found" → Check service running
"SUSDB not found" → Database doesn't exist
"Path not found" → Check content path setting
```

---

## 🔍 Debugging Tips

### Enable detailed SQL logging

```csharp
// In SqlHelper.cs, add before ExecuteQueryAsync:
Console.WriteLine($"Executing query: {query}");
```

### Trace property changes

```csharp
// In MainViewModel.cs, add partial method:
partial void OnServicesStatusChanged(string value)
{
    Console.WriteLine($"ServicesStatus changed to: {value}");
}
```

### Monitor dashboard refresh

```csharp
private async void StartAutoRefresh()
{
    while (true)
    {
        await Task.Delay(TimeSpan.FromSeconds(30));
        Console.WriteLine($"Auto-refresh triggered. IsOperationRunning={IsOperationRunning}");

        if (!IsOperationRunning && IsDashboardVisible)
        {
            await RefreshDashboardAsync();
        }
    }
}
```

---

**Last Updated:** 2026-01-12
**C# Version:** 4.0 POC
**Based on PowerShell:** v3.8.3
