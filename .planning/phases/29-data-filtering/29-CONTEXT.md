# Phase 29: Data Filtering - Context

**Gathered:** 2026-02-21
**Status:** Ready for planning

<domain>
## Phase Boundary

Add real-time filtering to dashboard panels: Computers panel gets status filter (Online/Offline/Error), Updates panel gets approval status filter (Approved/Not Approved/Declined) and classification filter (Critical/Security/Definition/Updates), and both panels get real-time search box with 300ms debounce for instant filtering as user types.

</domain>

<decisions>
## Implementation Decisions

### Filter UI Placement
- **Above each data panel**: Filters placed in toolbar area above Computers ListBox and Updates ListView
- **Layout**: Horizontal row of filter controls with labels
- **Spacing**: 8px margin between filter controls
- **Search box**: Right-aligned in filter row for easy access

### Filter Control Types
- **ComboBox for status filters** (All/Online/Offline/Error for computers, All/Approved/Not Approved/Declined for updates)
- **ComboBox for classification filter** (All/Critical/Security/Definition/Updates)
- **TextBox for search** with search icon placeholder (magnifying glass)
- **ComboBox width**: Auto width to fit longest option text
- **Search box width**: 200px fixed (expandable)

### Filter Behavior
- **ComboBox filters**: Select item → immediately filter CollectionView (no apply button needed)
- **"All" option**: Shows all items (no filtering applied)
- **Multiple filters**: Combined with AND logic (e.g., "Approved" AND "Critical" shows only approved critical updates)
- **Search filters**: Case-insensitive substring match on display text
- **Real-time**: Filter updates immediately on selection change (no search button)

### Search Debounce
- **300ms debounce** as specified (use DispatcherTimer)
- **Reset timer** on each keystroke
- **Filter applied** when timer fires
- **UX indicator**: Show "(filtering...)" text in status bar during debounce
- **Clear search**: When TextBox empty, remove search filter

### Filter Persistence
- **Save to AppSettings**: Last selected filter values
- **Properties**: ComputerStatusFilter, UpdateApprovalFilter, UpdateClassificationFilter, ComputerSearchText, UpdateSearchText
- **Restore on startup**: Apply saved filters when dashboard loads
- **No persistence**: Temporary filters cleared on application restart (save choice: persist = better UX)

### Empty State Handling
- **No matching items**: Show TextBlock "No items match your current filters" in panel center
- **Clear filters button**: Show only when filters active (not "All" or search not empty)
- **Visual feedback**: Gray out empty panels to distinguish from loading state

### CollectionView Filtering
- **Use CollectionView.GetDefaultView()** for existing ListBoxes/ListView
- **Filter property**: Lambda expression based on current filter values
- **Refresh() call**: Triggered when any filter changes
- **Performance**: Filter is O(n) where n is visible items (acceptable for <2000 items)

### Search Scope
- **Computers panel**: Search matches computer name, IP address, status text
- **Updates panel**: Search matches KB number, title, classification, approval status
- **Partial matches**: Substring match (not word-boundary)
- **Case insensitive**: Use StringComparison.OrdinalIgnoreCase

### Filter Reset
- **Clear filters button**: Resets all ComboBox to "All" and clears search TextBox
- **Button visibility**: Only show when filters active (any filter not "All" or search text)
- **Keyboard shortcut**: Esc key clears search text (keep filter dropdowns)

### Visual Feedback
- **Active filter indicator**: Bold text on ComboBox when filter is active (not "All")
- **Search box focus**: Select all text on focus for easy replacement
- **Filter count**: Show "X of Y items visible" in status bar when filtering
- **No progress indicator**: Filtering is instant (<50ms for 2000 items)

### Claude's Discretion
- Exact spacing and margins for filter controls
- Whether to add filter icons to ComboBox headers
- Search placeholder text ("Search..." vs "Filter by name...")
- Exact empty state message wording
- Animation/fade effects for filter changes

</decisions>

<specifics>
## Specific Ideas

- "Filters should be immediately above the data panel, not in a separate toolbar"
- "No 'Apply' button — filters should work instantly like Excel autofilter"
- "Search should feel responsive — 300ms debounce prevents flickering while typing"
- "Empty state should clearly indicate it's due to filters, not missing data"

</specifics>

<deferred>
## Deferred Ideas

- Saved filter presets (named filter combinations) — add to backlog
- Advanced query syntax (AND/OR operators in search) — future enhancement
- Filter by multiple selections (e.g., "Critical OR Security") — separate phase
- Export filtered data (CSV export uses active filters) — Phase 30 handles this

</deferred>

---

*Phase: 29-data-filtering*
*Context gathered: 2026-02-21*
