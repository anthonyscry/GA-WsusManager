# Requirements: GA-WsusManager

**Defined:** 2026-02-20
**Core Value:** Rock-solid stability — zero crashes, no threading bugs, no UI freezes — so administrators trust it to manage critical WSUS infrastructure.

## v4.3 Requirements

Requirements for the Themes milestone. Each maps to roadmap phases.

### Theme Infrastructure

- [ ] **INFRA-01**: App splits DarkTheme.xaml into shared styles (permanent) and color tokens (swappable)
- [ ] **INFRA-02**: All XAML color/brush references use DynamicResource instead of StaticResource
- [ ] **INFRA-03**: All hardcoded hex color values in XAML are extracted to named theme resource keys
- [ ] **INFRA-04**: ViewModel hardcoded Color.FromRgb() brushes use theme-aware resource lookup
- [ ] **INFRA-05**: ThemeService can swap color dictionaries at runtime without app restart

### Theme Content

- [ ] **THEME-01**: App ships 6 built-in color themes: Default Dark, Just Black, Slate, Serenity, Rose, Classic Blue
- [ ] **THEME-02**: Every theme file defines all required resource keys (no missing keys)
- [ ] **THEME-03**: All 6 themes meet WCAG 2.1 AA contrast ratio (4.5:1 for text)

### Theme Picker

- [ ] **PICK-01**: User can select a theme from the Settings dialog Appearance section
- [ ] **PICK-02**: Theme picker shows color swatches with theme names for each option
- [ ] **PICK-03**: Currently active theme is visually indicated in the picker
- [ ] **PICK-04**: Theme applies live when user clicks a swatch (preview before Save)
- [ ] **PICK-05**: Clicking Cancel reverts to the theme active when Settings was opened
- [ ] **PICK-06**: Selected theme persists to settings.json and restores on app startup

## Future Requirements

Deferred to future release. Tracked but not in current roadmap.

### Polish

- **POLSH-01**: Smooth fade transition (150ms) on theme switch
- **POLSH-02**: High-contrast accessibility theme

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Custom color editor / theme builder | Huge scope; 6 curated themes cover preference range |
| External theme file import | Code injection vector via arbitrary XAML; conflicts with single-EXE deployment |
| Light themes | Server admin tool used in data centers; dark-family themes only |
| Per-section theming | Visual incoherence; themes must apply globally |
| Font size / font family picker | DPI awareness handles scale; fixed fonts maintain layout integrity |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| INFRA-01 | Phase 16 | Pending |
| INFRA-02 | Phase 16 | Pending |
| INFRA-03 | Phase 16 | Pending |
| INFRA-04 | Phase 16 | Pending |
| INFRA-05 | Phase 16 | Pending |
| THEME-01 | Phase 17 | Pending |
| THEME-02 | Phase 17 | Pending |
| THEME-03 | Phase 17 | Pending |
| PICK-01 | Phase 17 | Pending |
| PICK-02 | Phase 17 | Pending |
| PICK-03 | Phase 17 | Pending |
| PICK-04 | Phase 17 | Pending |
| PICK-05 | Phase 17 | Pending |
| PICK-06 | Phase 17 | Pending |

**Coverage:**
- v4.3 requirements: 14 total
- Mapped to phases: 14
- Unmapped: 0

---
*Requirements defined: 2026-02-20*
*Last updated: 2026-02-20 after roadmap creation*
