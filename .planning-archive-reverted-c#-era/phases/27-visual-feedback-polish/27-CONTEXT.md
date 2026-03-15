# Phase 27: Visual Feedback Polish - Context

**Gathered:** 2026-02-21
**Status:** Ready for planning

<domain>
## Phase Boundary

Enhance user feedback during operations with clear progress indicators and actionable guidance. Add estimated time remaining for long-running operations, visual loading indicators on buttons, actionable error messages with specific next steps, consistent success/failure banners, and tooltip help text for all interactive elements.

</domain>

<decisions>
## Implementation Decisions

### Progress Estimation
- **Data source**: Use historical timing data from Phase 22 BenchmarkDotNet benchmarks
- **Display format**: "Step 2/5: [Step Name] - Est. 2m 15s remaining"
- **Calculation**: (average operation time from benchmarks) × (percent complete / 100)
- **Fallback**: If no benchmark data exists, show "Step 2/5: [Step Name] - Working..." (no time estimate)
- **Update frequency**: Update estimate after each step completes, recalculate based on elapsed time

### Loading Indicators
- **Button state**: Set `IsEnabled = false` on operation buttons when operation running
- **Visual indicator**: Add circular progress spinner (System.Windows.Controls.Primitives.ProgressBar with IsIndeterminate=true) on buttons or in status area
- **Location**: Show in status area (StatusMessage block) with spinning icon
- **Implementation**: Use existing StatusMessage property in MainViewModel, add "Loading..." prefix during operations

### Error Messaging
- **Structure**: Three-part format: (1) What failed, (2) Why it matters, (3) Specific action to resolve
- **Pattern**: `"Error: [specific error]\n\nTo fix: [actionable step]"` (displayed in message box or log panel)
- **Examples**:
  - `"Error: Could not connect to SQL Server.\n\nTo fix: 1) Start SQL Server service, 2) Run Repair Health"`
  - `"Error: WinRM connection failed.\n\nTo fix: Check network connectivity and target machine is online"`
- **Actionable language**: Use imperative verbs (Start, Run, Check, Enable, Disable)

### Success/Failure Banners
- **Location**: Display in log output panel (existing infrastructure)
- **Success format**: `"✓ [OperationName] completed successfully"` in TextSecondary color
- **Failure format**: `"✗ [OperationName] failed: [error reason]"` in TextError (red) color
- **Consistent iconography**: Use ✓ (checkmark) for success, ✗ (cross mark) for failure, ⚠ (warning) for partial success
- **Background**: Optional colored backgrounds (light green for success, light red for failure) using existing theme brushes

### Tooltip Help
- **Coverage**: All toolbar buttons and quick action buttons in MainWindow
- **Content format**: Short description (5-10 words) of what the button does
- **Examples**:
  - Refresh: "Refresh dashboard health status and data"
  - Settings: "Open application settings configuration"
  - Cleanup: "Run WSUS cleanup and database optimization"
  - Export: "Export WSUS metadata to external media"
- **Implementation**: Add `ToolTip="[Help text]"` attribute to Button elements
- **Scope**: Focus on buttons without obvious labels; navigation tabs can omit tooltips

### Claude's Discretion
- Exact timing of progress updates (every step, every N seconds)
- Visual style of spinner (size, color, animation speed)
- Whether to add colored backgrounds to banners or just icons
- Which buttons get tooltips if most are obvious from labels

</decisions>

<specifics>
## Specific Ideas

- "Progress estimation should build on Phase 22 BenchmarkDotNet infrastructure - we already have timing data"
- "Loading indicators should reuse existing StatusMessage property - don't duplicate display mechanisms"
- "Error messages should always end with a specific action the user can take - no generic 'contact support'"
- "Success/failure banners in the log panel are sufficient - no need for separate notification overlay"
- Follow existing WPF ToolTip patterns - set ToolTipService.ShowDuration to Infinity (or leave default)

</specifics>

<deferred>
## Deferred Ideas

- Toast notifications for operation completion (overlap with log panel output)
- Sound notifications for operation completion
- Progress bar percentage display (step-based is clearer for multi-step operations)
- Help button with in-app documentation viewer (F1=Help covers this)
- Animated success/failure icons (static icons are sufficient)

</deferred>

---

*Phase: 27-visual-feedback-polish*
*Context gathered: 2026-02-21*
