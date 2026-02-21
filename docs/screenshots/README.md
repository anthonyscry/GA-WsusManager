# Screenshots

This directory contains UI screenshots for the WSUS Manager documentation.

## Placeholder Status

Currently, these screenshots are placeholders. To generate actual screenshots:

1. Build the application: `dotnet publish src/WsusManager.App/WsusManager.App.csproj --configuration Release`
2. Run the application as Administrator
3. Navigate to each view:
   - **Dashboard** - Main window on startup
   - **Diagnostics** - After running Diagnostics operation
   - **Settings** - Settings dialog with theme picker
   - **Transfer** - Transfer dialog for air-gap operations
4. Use Windows Snipping Tool (Win+Shift+S) or similar
5. Save as PNG files in this directory

## Required Screenshots

- `dashboard.png` - Main dashboard with all cards
- `diagnostics.png` - Diagnostics panel with results
- `settings.png` - Settings dialog with theme picker
- `transfer.png` - Transfer dialog for air-gap operations

## Guidelines

- Resolution: 1920x1080 recommended
- Format: PNG
- Use dark theme for consistency
- Capture full application window
- Ensure text is readable
