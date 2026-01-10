# CI/CD Security Review Report

**Date**: 2026-01-10
**Reviewer**: Claude (Automated Security Analysis)
**Pipeline**: `.github/workflows/dotnet-desktop.yml`
**Status**: Review Complete - Action Required

---

## Executive Summary

The WSUS-SQL CI/CD pipeline is well-structured with good PowerShell security scanning. However, several security improvements are recommended, primarily around permissions hardening, dependency pinning, and caching for performance.

| Severity | Count | Status |
|----------|-------|--------|
| Critical | 1 | Needs Fix |
| High | 2 | Needs Fix |
| Medium | 3 | Recommended |
| Low | 2 | Optional |

---

## Detailed Findings

### CRITICAL-001: Missing Permissions Block

**Location**: Workflow file root level (lines 1-18)
**Risk**: Workflows run with default `write-all` permissions, allowing any compromised action to modify repository contents, create releases, or access secrets.

**Current State**:
```yaml
name: WSUS-SQL CI/CD
on:
  push:
    branches: [ "main" ]
  # No permissions block
```

**Recommendation**:
```yaml
name: WSUS-SQL CI/CD

permissions:
  contents: read
  actions: read

on:
  push:
    branches: [ "main" ]
```

For jobs that need write access (like uploading artifacts), use job-level permissions:
```yaml
jobs:
  build-gui:
    permissions:
      contents: read
      actions: write  # For artifact upload
```

---

### HIGH-001: Unpinned Action Versions

**Location**: Lines 31, 165, 213, 267, 373, 379, 439
**Risk**: Using `@v4` without SHA pinning means malicious updates to actions could inject code into your pipeline.

**Current State**:
```yaml
- uses: actions/checkout@v4
- uses: actions/upload-artifact@v4
- uses: actions/setup-dotnet@v4
```

**Recommendation**: Pin to specific commit SHAs:
```yaml
- uses: actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11 # v4.1.1
- uses: actions/upload-artifact@5d5d22a31266ced268874388b861e4b58bb5c2f3 # v4.3.1
- uses: actions/setup-dotnet@4d6c8fcf3c8f7a60068d26b594648e99df24cee3 # v4.0.0
```

---

### HIGH-002: Overly Broad Artifact Upload

**Location**: Lines 163-171
**Risk**: Uploading all `.ps1` and `.psm1` files may expose sensitive scripts or internal logic.

**Current State**:
```yaml
- name: Upload Analysis Results
  uses: actions/upload-artifact@v4
  with:
    name: powershell-analysis-results
    path: |
      **/*.ps1
      **/*.psm1
```

**Recommendation**: Only upload analysis output, not source code:
```yaml
- name: Upload Analysis Results
  uses: actions/upload-artifact@v4
  with:
    name: powershell-analysis-results
    path: ./analysis-report.json
    retention-days: 7
```

Or generate a structured report:
```powershell
$results | ConvertTo-Json -Depth 10 | Out-File './analysis-report.json'
```

---

### MEDIUM-001: No SARIF Upload for Security Findings

**Location**: Lines 65-85 (Security Rules step)
**Risk**: Security findings are logged but not integrated with GitHub Security tab.

**Recommendation**: Export PSScriptAnalyzer results as SARIF:
```yaml
- name: Run PSScriptAnalyzer - Security Rules
  shell: pwsh
  run: |
    $results = Invoke-ScriptAnalyzer -Path . -Recurse -IncludeRule $securityRules

    # Convert to SARIF format
    $sarif = @{
      '$schema' = 'https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json'
      version = '2.1.0'
      runs = @(@{
        tool = @{ driver = @{ name = 'PSScriptAnalyzer'; version = '1.21.0' } }
        results = $results | ForEach-Object {
          @{ ruleId = $_.RuleName; message = @{ text = $_.Message } }
        }
      })
    }
    $sarif | ConvertTo-Json -Depth 10 | Out-File 'security-results.sarif'

- name: Upload SARIF
  uses: github/codeql-action/upload-sarif@v3
  with:
    sarif_file: security-results.sarif
```

---

### MEDIUM-002: Missing Job Timeouts

**Location**: All jobs
**Risk**: Jobs without timeouts could run indefinitely, consuming resources and blocking runners.

**Recommendation**: Add timeout-minutes to each job:
```yaml
jobs:
  powershell-analysis:
    name: PowerShell Analysis
    runs-on: windows-latest
    timeout-minutes: 15

  pester-tests:
    timeout-minutes: 20

  build-gui:
    timeout-minutes: 30
```

---

### MEDIUM-003: Hardcoded Secret Detection Gaps

**Location**: Lines 90-110
**Risk**: Current regex patterns may miss:
- Base64-encoded secrets
- Secrets in JSON/XML config files
- Environment variable assignments
- AWS/Azure/GCP credential patterns

**Recommendation**: Enhance detection or use dedicated tools:
```yaml
- name: Check for Hardcoded Secrets
  uses: trufflesecurity/trufflehog@main
  with:
    path: ./
    base: ""
    head: ${{ github.sha }}
```

---

### LOW-001: Redundant Configuration

**Location**: Line 282
**Risk**: None - cosmetic issue

```yaml
continue-on-error: false  # This is the default
```

---

### LOW-002: No Concurrency Controls

**Location**: Workflow level
**Risk**: Multiple workflow runs on the same branch could conflict.

**Recommendation**:
```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

---

## Performance Recommendations

### 1. Add NuGet Package Caching

```yaml
- name: Cache NuGet packages
  uses: actions/cache@v4
  with:
    path: ~/.nuget/packages
    key: ${{ runner.os }}-nuget-${{ hashFiles('**/*.csproj') }}
    restore-keys: |
      ${{ runner.os }}-nuget-
```

**Estimated savings**: 30-60 seconds per build

### 2. Add PowerShell Module Caching

```yaml
- name: Cache PowerShell Modules
  id: ps-cache
  uses: actions/cache@v4
  with:
    path: |
      C:\Users\runneradmin\Documents\PowerShell\Modules
    key: ${{ runner.os }}-psmodules-pssa-pester-ps2exe-v1

- name: Install PSScriptAnalyzer
  if: steps.ps-cache.outputs.cache-hit != 'true'
  shell: pwsh
  run: Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser
```

**Estimated savings**: 20-40 seconds per job

### 3. Parallel Job Optimization

Current dependency graph:
```
powershell-analysis ─┬─► pester-tests ─┬─► build-gui
                     └─────────────────┴─► build-powershell-gui
```

`build-powershell-gui` only needs `powershell-analysis`, so it can run in parallel with `pester-tests`.

---

## Compliance Checklist

| Control | Status | Notes |
|---------|--------|-------|
| Least privilege permissions | ❌ | Needs permissions block |
| Pinned dependencies | ❌ | Using @v4 tags |
| Secret scanning | ✅ | Basic patterns implemented |
| Code signing | ❌ | Not implemented |
| Artifact retention policy | ✅ | 7-30 days configured |
| Branch protection | ⚠️ | Not verified in workflow |
| SBOM generation | ❌ | Not implemented |

---

## Implementation Priority

1. **Immediate** (This Week):
   - Add permissions block (CRITICAL-001)
   - Pin action versions (HIGH-001)

2. **Short Term** (This Month):
   - Reduce artifact scope (HIGH-002)
   - Add job timeouts (MEDIUM-002)
   - Add concurrency controls (LOW-002)

3. **Medium Term** (This Quarter):
   - Implement SARIF upload (MEDIUM-001)
   - Add comprehensive secret scanning (MEDIUM-003)
   - Implement caching for performance

---

## Appendix: Improved Workflow Template

See `.github/workflows/dotnet-desktop-secured.yml` for a reference implementation with all security recommendations applied.
