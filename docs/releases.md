# Release Process

This document describes the release process for WSUS Manager, including versioning, changelog maintenance, and publishing steps.

## Versioning

WSUS Manager uses [Semantic Versioning](https://semver.org/):

```
MAJOR.MINOR.PATCH

Examples:
- 4.0.0 - Initial C# release
- 4.1.0 - New features (backward compatible)
- 4.1.1 - Bug fix (backward compatible)
- 5.0.0 - Breaking changes
```

### Version Number Components

- **MAJOR:** Incompatible API changes or major rewrite
- **MINOR:** New functionality (backward compatible)
- **PATCH:** Bug fixes (backward compatible)

### Pre-release Versions

Pre-release versions use suffixes:

```
4.4.0-alpha.1   - First alpha release
4.4.0-beta.1    - First beta release
4.4.0-rc.1      - First release candidate
4.4.0           - Stable release
```

### Version Location

Version is stored in:
- **Source:** `src/Directory.Build.props` (`<Version>` element)
- **Product:** EXE properties (File Version, Product Version)
- **Git tag:** Annotated tag matching version (e.g., `v4.4.0`)

**Important:** Keep version in `src/Directory.Build.props` as single source of truth.

## Changelog

WSUS Manager follows [Keep a Changelog](https://keepachangelog.com/) format.

### Changelog Format

**File:** `CHANGELOG.md`

**Structure:**
```markdown
# Changelog

All notable changes to WSUS Manager will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- New feature under development

### Changed
- Modified existing feature

### Deprecated
- Feature that will be removed in future

### Removed
- Feature removed in this version

### Fixed
- Bug fix

### Security
- Security vulnerability fix

## [4.4.0] - 2026-02-21

### Added
- XML documentation comments for all public APIs
- API reference documentation via DocFX
- CI/CD pipeline documentation
- Release process documentation (this file)
- Architecture documentation with MVVM pattern

### Changed
- README.md updated to reflect C# application
- CONTRIBUTING.md expanded with testing patterns
- Documentation organized in docs/ directory

### Fixed
- Fixed broken links in documentation
```

### Changelog Guidelines

- **Categorize changes:** Added, Changed, Deprecated, Removed, Fixed, Security
- **ISO dates:** Use YYYY-MM-DD format for release dates
- **Link commits:** Add commit SHA or PR link in parentheses for significant changes
- **User-facing focus:** Document what users care about (not internal refactoring)
- **Unreleased section:** Add upcoming features to Unreleased, move to version on release

## Release Checklist

Use this checklist for every release to ensure no steps are missed.

### Pre-Release

- [ ] **Verify all tests pass**
  ```bash
  dotnet test --configuration Release
  ```

- [ ] **Verify build succeeds**
  ```bash
  dotnet build --configuration Release
  ```

- [ ] **Verify zero compiler warnings**
  - Check build output for warnings
  - Fix or justify any warnings

- [ ] **Update version number**
  - Edit `src/Directory.Build.props`
  - Update `<Version>` element to new version

- [ ] **Update CHANGELOG.md**
  - Move items from `[Unreleased]` to new version section
  - Add release date (YYYY-MM-DD)
  - Remove empty categories
  - Update version comparison links at bottom

- [ ] **Update README.md version**
  - Change version in header to match new version

- [ ] **Run full smoke tests**
  - Install and run EXE
  - Test all major operations (Diagnostics, Cleanup, Sync, Export/Import)
  - Verify no crashes or obvious bugs

- [ ] **Test upgrade scenario**
  - Install previous version
  - Install new version over it
  - Verify settings preserved
  - Verify application launches

### Release

- [ ] **Commit changes**
  ```bash
  git add .
  git commit -m "chore: release v4.4.0"
  ```

- [ ] **Push to main**
  ```bash
  git push origin main
  ```

- [ ] **Wait for CI/CD to pass**
  - Check Actions tab for workflow run
  - Verify all checks pass
  - Download and test EXE from artifacts

- [ ] **Create git tag**
  ```bash
  git tag v4.4.0
  git push origin v4.4.0
  ```

- [ ] **Wait for release workflow**
  - Release workflow triggers automatically
  - Check Actions tab for `release-csharp.yml` run
  - Verify release created on GitHub

- [ ] **Verify GitHub release**
  - Navigate to https://github.com/anthonyscry/GA-WsusManager/releases
  - Verify release created with correct tag
  - Verify EXE asset attached
  - Verify release notes populated (from CHANGELOG.md)

### Post-Release

- [ ] **Test downloaded EXE**
  - Download EXE from GitHub release
  - Install and run
  - Verify version number is correct
  - Test major operations

- [ ] **Update documentation**
  - Update version references in docs
  - Update screenshots if UI changed
  - Add new features to feature list

- [ ] **Archive release notes**
  - Copy release notes to project wiki (if applicable)
  - Announce release to stakeholders

- [ ] **Create Unreleased section**
  - Add empty `[Unreleased]` section to CHANGELOG.md
  - Ready for next release

## Release Workflow

### Automated Release (Recommended)

The GitHub Actions workflow automatically creates releases when you push a version tag:

1. **Update version and changelog** (see Pre-Release checklist)
2. **Commit and push** changes to main
3. **Create and push tag**
   ```bash
   git tag v4.4.0
   git push origin v4.4.0
   ```
4. **Workflow runs automatically**
   - Builds solution
   - Runs tests
   - Publishes EXE
   - Creates GitHub release
   - Uploads EXE as asset

### Manual Release (Fallback)

If automated workflow fails, create release manually:

1. **Follow Pre-Release checklist**
2. **Build EXE locally**
   ```bash
   dotnet publish src/WsusManager.App/WsusManager.App.csproj \
     --configuration Release \
     --runtime win-x64 \
     --self-contained true \
     --output publish \
     -p:PublishSingleFile=true
   ```
3. **Create ZIP archive**
   ```bash
   Compress-Archive -Path publish/WsusManager.exe -DestinationPath WsusManager-v4.4.0.zip
   ```
4. **Create GitHub release**
   - Go to https://github.com/anthonyscry/GA-WsusManager/releases/new
   - Choose tag (must exist)
   - Release title: `v4.4.0`
   - Description: Copy from CHANGELOG.md
   - Attach `WsusManager-v4.4.0.zip`
   - Publish release

## Hotfix Releases

For critical bugs requiring immediate release:

1. **Create hotfix branch** from release tag
   ```bash
   git checkout v4.4.0
   git checkout -b hotfix/v4.4.1
   ```

2. **Fix bug** and test thoroughly

3. **Update version** to patch version (e.g., 4.4.1)

4. **Update CHANGELOG.md** with fix description

5. **Commit and push** hotfix branch

6. **Create PR** to main branch

7. **Merge PR** after review

8. **Create tag** and release as normal

9. **Merge hotfix back** to main branch for next release

## Branching Strategy

WSUS Manager uses simplified Git flow:

```
main (4.4.0) ────────?
                    ?
  ????????????????????
  ?
  ├─ feature/new-feature (PR ? main)
  ├─ fix/bug-fix (PR ? main)
  └─ hotfix/v4.4.1 (PR ? main, tag v4.4.1)

Tags:
- v4.4.0 (release)
- v4.4.1 (hotfix)
```

**Rules:**
- All development happens on `main` branch
- Feature branches for PRs
- Hotfix branches for urgent fixes
- Tags only on `main` branch

## Rollback Procedure

If critical issue found after release:

1. **Yank release** (GitHub ? Releases ? Edit ? Delete release, keep tag)
2. **Fix issue** in hotfix branch
3. **Release patch version** (e.g., 4.4.1 if 4.4.0 was bad)
4. **Announce issue** and recommend upgrade

**Note:** Don't delete git tags - they're part of Git history.

## Version Bump Examples

### Major Version Bump (5.0.0)

Breaking changes or major rewrite:
- Incompatible API changes
- Removed features
- Major architecture change

### Minor Version Bump (4.5.0)

New features (backward compatible):
- New operations or panels
- New features in existing operations
- Performance improvements (user-visible)

### Patch Version Bump (4.4.1)

Bug fixes (backward compatible):
- Crash fixes
- Data loss bugs
- Security vulnerabilities
- UI glitches

## Related Documentation

- **[CHANGELOG.md](../CHANGELOG.md)** - Version history
- **[docs/ci-cd.md](ci-cd.md)** - CI/CD pipeline documentation
- **[CONTRIBUTING.md](../CONTRIBUTING.md)** - Contribution guidelines

---

*Last updated: 2026-02-21*
*Follow this process for all releases to ensure consistency.*
