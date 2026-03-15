# Gap Closure Plan 19-GAP-02: Bulk Code Reformat

**Created:** 2026-02-21
**Type:** gap_closure
**Gap Reference:** QUAL-03 - .editorconfig defines consistent code style across solution
**Requirements:** QUAL-03

## Gap Definition

**Observed Issue:** Step 5 of Plan 19-02 (bulk reformat with dotnet-format) was skipped due to .NET 9 runtime dependency. Existing code may not conform to .editorconfig style rules.

**Root Cause:**
- dotnet-format v5.1.250801 requires .NET 9 runtime
- WSL environment only has .NET 8.0 SDK
- Tool fails with "You must install .NET to run this application. .NET location: Not found"

**Evidence from 19-VERIFICATION.md:**
> "Bulk reformat (Step 5): Skipped due to .NET 9 runtime dependency (dotnet-format v5.1 requires .NET 9, only .NET 8 available)"

**Impact:**
- IDE auto-format works (VS Code, VS 2022, Rider)
- But existing codebase may have formatting inconsistencies
- New code will be auto-formatted, but old code requires manual reformat

**Workaround Present:**
- `src/.vscode/settings.json` created with `editor.formatOnSave: true`
- CONTRIBUTING.md documents: "All editors auto-format on save when .editorconfig is supported"

## Gap Closure Strategy

**Approach:** Provide three options for completing bulk reformat, with Option A (install .NET 9) being preferred.

**Success Criteria (must_haves):**
1. All existing .cs files conform to .editorconfig style rules
2. Build passes with zero style warnings
3. Code style is consistent across the entire codebase
4. IDE auto-format works for all developers

## Implementation Options

### Option A: Install .NET 9 Runtime (Preferred)

**Step 1: Install .NET 9 Runtime**
```bash
# Download and install .NET 9 runtime
wget https://dot.net/v1/dotnet-install.sh -O dotnet-install.sh
chmod +x dotnet-install.sh
./dotnet-install.sh --channel 9.0 --runtime aspnetcore

# Verify installation
~/.dotnet/dotnet --list-runtimes
```

**Step 2: Run dotnet-format**
```bash
cd /mnt/c/projects/GA-WsusManager/src
~/.dotnet/dotnet format WsusManager.sln --folder --include \
  --exclude **/obj/** --exclude **/bin/**
```

**Step 3: Verify changes**
```bash
git diff --stat
```

**Step 4: Commit changes**
```bash
git add -A
git commit -m "style(19-gap-02): bulk reformat codebase to .editorconfig standards"
```

**Pros:**
- One-time setup
- Automated reformat
- Consistent results

**Cons:**
- Requires .NET 9 installation (may not be available in all environments)

### Option B: IDE Auto-Format (Manual but Safe)

**Step 1: Open Solution in IDE**
- Visual Studio 2022: Open `src/WsusManager.sln`
- VS Code: Open `src/` folder
- Rider: Open `src/WsusManager.sln`

**Step 2: Select All Files**
- VS 2022: Edit → Advanced → Format Document (for each file)
- VS Code: Ctrl+Shift+P → "Format Document" (for each file)
- Rider: Code → Reformat Code (for each file)

**Step 3: Save All Files**
- IDE will auto-format on save (settings.json configured)

**Step 4: Review and Commit**
```bash
git diff
git add -A
git commit -m "style(19-gap-02): bulk reformat via IDE auto-format"
```

**Pros:**
- Works with existing .NET 8 SDK
- No additional installation required
- Preview changes before committing

**Cons:**
- Manual process (tedious for many files)
- May miss files not opened in IDE

### Option C: Accept Incremental Reformat (Lowest Effort)

**Rationale:** IDE auto-format on save will fix files incrementally as they're edited. Existing inconsistencies are acceptable as technical debt.

**Action Items:**
1. Document decision in CONTRIBUTING.md
2. Add note to Phase 19 summary that bulk reformat is deferred
3. Proceed to Phase 20 (XML Documentation)

**Pros:**
- Zero effort
- No blocking changes
- IDE auto-format works for new code

**Cons:**
- Existing code remains inconsistent
- Code reviews may flag style issues
- New contributors may see inconsistent style

## Recommended Approach

**Recommendation:** Option A (Install .NET 9 Runtime)

**Justification:**
- One-time effort for immediate consistency
- Automated reformat ensures all files are covered
- .NET 9 runtime doesn't conflict with .NET 8 SDK
- Future-proofs environment for upcoming .NET 9 release

**Fallback:** If .NET 9 installation fails, use Option B (IDE auto-format) for high-touch files, defer remaining files to incremental reformat.

## Implementation (Option A - Recommended)

### Step 1: Check Current .NET Version
```bash
dotnet --list-sdks
dotnet --list-runtimes
```

### Step 2: Install .NET 9 Runtime
```bash
# Download install script
wget https://dot.net/v1/dotnet-install.sh -O /tmp/dotnet-install.sh
chmod +x /tmp/dotnet-install.sh

# Install .NET 9 runtime (side-by-side with .NET 8)
/tmp/dotnet-install.sh --channel 9.0 --runtime aspnetcore --install-dir ~/.dotnet

# Add to PATH if not already
export PATH="$HOME/.dotnet:$PATH"
echo 'export PATH="$HOME/.dotnet:$PATH"' >> ~/.bashrc
```

### Step 3: Verify .NET 9 Installation
```bash
~/.dotnet/dotnet --list-runtimes | grep "9\.0"
```

Expected output:
```
Microsoft.AspNetCore.App 9.0.0 [...]
Microsoft.NETCore.App 9.0.0 [...]
```

### Step 4: Run Bulk Reformat
```bash
cd /mnt/c/projects/GA-WsusManager/src

# Run dotnet-format on entire solution
~/.dotnet/dotnet format WsusManager.sln --folder --include \
  --exclude **/obj/** --exclude **/bin/** --verbosity diagnostic
```

**What dotnet-format does:**
- Applies all .editorconfig rules to all .cs files
- Fixes indentation (4 spaces)
- Fixes brace style (K&R)
- Sorts using directives
- Adds final newlines
- Fixes line endings (CRLF)

### Step 5: Review Changes
```bash
cd /mnt/c/projects/GA-WsusManager

# Show changed files
git diff --name-only

# Show line changes
git diff --stat

# Show sample changes
git diff src/WsusManager.Core/Services/HealthService.cs | head -50
```

### Step 6: Verify Build Still Passes
```bash
dotnet build src/WsusManager.sln --configuration Release
```

Expected: `Build succeeded. 0 Warning(s) 0 Error(s)`

### Step 7: Run Tests
```bash
dotnet test src/WsusManager.sln --configuration Release
```

Expected: All 455 tests pass

### Step 8: Commit Changes
```bash
git add -A
git commit -m "style(19-gap-02): bulk reformat codebase to .editorconfig standards

- Applied dotnet-format to all .cs files
- All files now conform to .editorconfig style rules
- 4-space indentation, K&R braces, sorted using directives
- Fixed via .NET 9 runtime with dotnet-format v5.1

Gap closure for QUAL-03: .editorconfig defines consistent code style"
```

### Step 9: Update Documentation

**Update CONTRIBUTING.md:**
```markdown
## Code Style

All code conforms to the .editorconfig configuration at `src/.editorconfig`.

### Bulk Reformat (Completed 2026-02-21)

All existing code was reformatted using dotnet-format v5.1 with .NET 9 runtime.
New code will be auto-formatted by your IDE on save.

### Style Rules

- Indentation: 4 spaces (no tabs)
- Braces: K&R style (opening brace on same line)
- Using directives: System first, then Microsoft, then third-party
- Naming: PascalCase for public members, _camelCase for private fields
```

**Update 19-02-SUMMARY.md:**
```markdown
### Gap Closure (19-GAP-02)

Step 5 (bulk reformat) was completed via 19-GAP-02:
- Installed .NET 9 runtime
- Ran dotnet-format v5.1 on entire solution
- All .cs files now conform to .editorconfig standards
- Committed in separate gap closure plan
```

## Verification

**Pre-Implementation:**
- [x] .editorconfig exists with comprehensive rules (verified in 19-02)
- [x] IDE auto-format configured (verified in 19-02)
- [x] Bulk reformat skipped due to .NET 9 dependency (verified in 19-VERIFICATION)

**Post-Implementation:**
- [ ] All .cs files conform to .editorconfig rules
- [ ] `git diff` shows formatting changes only (no logic changes)
- [ ] Build passes with zero warnings
- [ ] All tests pass
- [ ] CONTRIBUTING.md updated with completion note

## Risk Mitigation

| Risk | Impact | Mitigation |
|------|--------|------------|
| .NET 9 installation fails | Medium | Fallback to Option B (IDE auto-format) |
| dotnet-format breaks code | Low | Review git diff before committing, run tests |
| Git diff is huge (cosmetic) | Low | Commit in single isolated commit for easy revert |
| .NET 9 conflicts with .NET 8 SDK | Low | Runtimes install side-by-side, no conflict |

## Dependencies

- **Plan 19-01:** Provides .editorconfig (already complete)
- **Plan 19-02:** Provides VS Code settings (already complete)
- **Plan 19-03:** Zero compiler warnings (already complete)

## Time Estimate

- Option A (.NET 9 + dotnet-format): 20-30 minutes
- Option B (IDE manual reformat): 2-3 hours (tedious)
- Option C (defer): 0 minutes (accept technical debt)

## Alternative: Partial Reformat

If full reformat is too disruptive, reformat only:
1. High-touch files (ViewModels, Services)
2. Files changed in Phase 20-24
3. New files as they're added

**Command for selective reformat:**
```bash
~/.dotnet/dotnet format src/WsusManager.Core/**/*.cs --folder
~/.dotnet/dotnet format src/WsusManager.App/ViewModels/*.cs --folder
```

## References

- [.NET 9 Install Script](https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-install-script)
- [dotnet-format Documentation](https://learn.microsoft.com/en-us/dotnet/core/formatting/)
- [.editorconfig Documentation](https://learn.microsoft.com/en-us/visualstudio/ide/editorconfig-code-style-settings-reference)

---

*Plan: 19-GAP-02 - Bulk Code Reformat*
*Type: gap_closure*
*Gap Reference: QUAL-03*
*Status: Ready for implementation*
*Recommendation: Option A (Install .NET 9 Runtime)*
