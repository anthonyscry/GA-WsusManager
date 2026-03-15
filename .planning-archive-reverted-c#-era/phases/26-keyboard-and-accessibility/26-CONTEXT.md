# Phase 26: Keyboard & Accessibility - Context

**Gathered:** 2026-02-21
**Status:** Ready for planning

<domain>
## Phase Boundary

Enable complete keyboard-only operation and WCAG 2.1 AA accessibility compliance. Add global keyboard shortcuts, full keyboard navigation support, AutomationId attributes for UI automation testing, color contrast verification, and proper dialog centering behavior.

</domain>

<decisions>
## Implementation Decisions

### Keyboard Shortcuts
- **F1** → Open Help dialog (About window with documentation links)
- **F5** → Refresh dashboard (re-runs health check and data collection)
- **Ctrl+S** → Open Settings dialog
- **Ctrl+Q** → Quit application (with confirmation if operations running)
- **Escape** → Close current dialog or cancel current operation
- Shortcuts are global (application-level) using InputBindings in MainWindow
- Mnemonics (Alt+key) for dialog buttons where appropriate (_S for Save, _C for Cancel)

### Keyboard Navigation Pattern
- **Tab order**: Logical left-to-right, top-to-bottom following visual layout
- **Arrow keys**: Navigate within lists/comboboxes, move between options
- **Enter/Space**: Activate focused button or toggle checkbox
- **Shift+Tab**: Reverse navigation through tab order
- **Focus management**: Set focus to first interactive control when dialog opens
- **Skip links**: Not applicable (single-window admin tool, not web)

### AutomationId Naming Convention
- **PascalCase** matching element purpose: `SaveButton`, `ComputersListBox`, `UpdatesTabItem`
- **Pattern**: `[ElementPurpose][ControlType]` (e.g., `RefreshButton`, `SettingsMenuItem`, `LogOutputTextBox`)
- **Lists** use singular form: `ComputersListBox` (not `ComputerListBox`)
- **Menus**: `FileMenu`, `ViewMenu`, `ToolsMenu`, `HelpMenu`
- **Menu items**: `RefreshDashboardMenuItem`, `OpenSettingsMenuItem`, `QuitApplicationMenuItem`
- **Dialogs**: Dialog root gets `SettingsDialog`, `AboutDialog` as AutomationId
- **Tabs**: `DashboardTabItem`, `ClientToolsTabItem`, `DiagnosticsTabItem`

### WCAG 2.1 AA Compliance Approach
- **Target contrast ratios**: 4.5:1 for normal text, 3:1 for large text (18pt+)
- **Verification method**: Unit test that parses all theme ResourceDictionaries and extracts color pairs
- **Foreground/background pairs**: Check TextBlock.Foreground with Background, Control foreground with container background
- **Tools**: Create automated test using WPF color extraction; manual verification with axe DevTools for UI snapshots if needed
- **Documentation**: Note WCAG compliance status in README.md for each theme

### Dialog Centering Behavior
- **With owner window**: Center horizontally and vertically on the owner window
- **Without owner** (rare, standalone dialogs): Center on primary monitor (use `Screen.PrimaryScreen.WorkingArea`)
- **Multi-monitor**: Use `WindowStartupLocation = CenterOwner` for owned dialogs
- **Settings dialog**: Owned by MainWindow, centers on main window
- **About dialog**: Owned by MainWindow, centers on main window
- **Size limits**: Ensure dialog fits within working area (max height/width validation)

### Claude's Discretion
- Exact tab order sequence (follow visual layout)
- Whether to add mnemonics to all buttons or just primary actions
- AutomationId for decorative elements (skip non-interactive elements)
- Whether to implement SkipLink pattern (deferred as not needed for single-window tool)

</decisions>

<specifics>
## Specific Ideas

- "Standard Windows shortcuts feel natural — F1 for help, F5 for refresh are what admins expect"
- "AutomationId should be descriptive enough for UI tests to find elements without using XAML paths"
- "WCAG compliance matters because some admins may use high-contrast themes or screen magnifiers"
- Follow existing WPF MVVM patterns with CommunityToolkit.Mvvm
- Use InputBindings at window level for global shortcuts
- Use FocusManager.FocusedElement attribute to set initial focus in dialogs

</specifics>

<deferred>
## Deferred Ideas

- Screen reader support (narrator integration) — additional accessibility beyond WCAG contrast
- High-contrast theme variant — separate theme for users with visual impairments
- Keyboard shortcut customization — allow users to remap keys
- Global menu bar (File, Edit, View) — ribbon-style menu navigation

</deferred>

---

*Phase: 26-keyboard-and-accessibility*
*Context gathered: 2026-02-21*
