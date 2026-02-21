# Phase 30: Data Export - Context

**Gathered:** 2026-02-21
**Status:** Ready for planning

<domain>
## Phase Boundary

Enable CSV export of dashboard data with UTF-8 BOM for Excel compatibility. Add "Export Computers" button to Computers panel and "Export Updates" button to Updates panel. Show progress dialog during export and open destination folder on completion.

</domain>

<decisions>
## Implementation Decisions

### Export Button Placement
- **Above each panel**: Add "Export" button to filter row (right-aligned after search box)
- **Button style**: Standard Button with icon (document/download icon)
- **Button text**: "Export" (simple, clear)
- **Enabled when**: Panel has data (disabled when empty or loading)

### CSV Format
- **UTF-8 with BOM**: Required for Excel to properly display UTF-8 encoded text
- **BOM sequence**: EF BB BF (three bytes at file start)
- **Comma delimiter**: Standard CSV format
- **Quote character**: Double-quote (") for fields containing commas or quotes
- **Line ending**: CRLF (\r\n) for Windows compatibility
- **Header row**: Column names as first line

### Column Selection
- **Computers export**: Name, IP Address, Status, Last Contact Time, OS Version
- **Updates export**: KB Number, Title, Classification, Approval Status, Size, Released Date
- **Respect filters**: Export only currently visible items (after filtering applied)
- **All columns**: No column selection UI (export fixed set of columns)

### File Naming
- **Pattern**: `WsusManager-{ExportType}-{yyyyMMdd-HHmmss}.csv`
- **ExportType values**: "Computers" or "Updates"
- **Example**: `WsusManager-Computers-20260221-143022.csv`
- **Destination**: User's Documents folder (Environment.SpecialFolder.MyDocuments)
- **No overwrite**: Always create new file with timestamp

### SaveFileDialog
- **No SaveFileDialog**: Always save to Documents with automatic filename
- **User control**: Users can move/rename file after export
- **Rationale**: Faster workflow, consistent destination

### Progress Dialog
- **Modal dialog**: Block UI during export
- **Content**:
  - Title: "Exporting Data"
  - Message: "Exporting {count} {items} to CSV..."
  - ProgressBar: IsIndeterminate="true" (show spinning progress)
  - StatusText: "Writing CSV file..."
  - Cancel button: Enabled (allows cancellation during export)
- **Update interval**: Refresh progress every 100ms

### Export Destination
- **Open folder on completion**: Use Process.Start("explorer.exe", "/select,\"{filepath}\"")
- **File selection**: Explorer opens with file selected (highlighted)
- **Fallback**: If opening explorer fails, show full file path in message box

### Error Handling
- **Directory access denied**: Show error "Cannot access Documents folder. Check permissions."
- **Disk full**: Show error "Not enough disk space to save export."
- **Write failure**: Show error "Failed to write export file: {error message}"
- **Cancellation**: Clean up partial file (delete if export cancelled mid-file)

### Large File Handling
- **Stream writing**: Use StreamWriter (not StringBuilder) for memory efficiency
- **Batch size**: Write 100 rows at a time to Stream
- **Progress updates**: Update progress dialog after each batch
- **No row limit**: Export all visible items (even 2000+ computers)

### Implementation Service
- **ICsvExportService interface**: Methods for ExportComputersAsync and ExportUpdatesAsync
- **CsvExportService implementation**: Handles CSV writing, BOM, streaming
- **DI registration**: Register as singleton in Program.cs
- **Testability**: Interface allows unit testing with mocks

### Export Command Pattern
- **ICommands in MainViewModel**: ExportComputersCommand, ExportUpdatesCommand
- **CanExecute**: Returns true when panel has visible items
- **Async execution**: Uses RunOperationAsync pattern for error handling
- **Progress reporting**: Uses IProgress<string> for status updates

### Claude's Discretion
- Exact icon for Export button
- Progress dialog styling (matches other dialogs)
- Whether to add "Export All" option (ignoring filters) — not in requirements
- Exact message box text for errors
- Animation or sound on completion — not in requirements

</decisions>

<specifics>
## Specific Ideas

- "Excel needs UTF-8 BOM or it displays Unicode characters as garbage"
- "Export should respect filters — admins often want to export filtered subsets"
- "Opening the destination folder is better than opening the file — user sees where it went"
- "Stream writing is important — could be exporting thousands of computers"

</specifics>

<deferred>
## Deferred Ideas

- Export to other formats (Excel .xlsx, JSON) — add to backlog
- Custom column selection in export — future enhancement
- Scheduled automated exports — separate phase
- Export all historical data (not just filtered) — quick workaround: clear filters first
- Email export on completion — not in requirements

</deferred>

---

*Phase: 30-data-export*
*Context gathered: 2026-02-21*
