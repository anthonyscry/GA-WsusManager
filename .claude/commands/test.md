# Run Pester Tests

Run all Pester tests for the GA-WsusManager project and explain any failures.

## Instructions

1. First, check if Pester is installed:
```powershell
Get-Module -ListAvailable Pester
```

2. If not installed, install it:
```powershell
Install-Module -Name Pester -Force -Scope CurrentUser -MinimumVersion 5.0
```

3. Run all tests in the Tests folder:
```powershell
Invoke-Pester -Path ./Tests -Output Detailed -PassThru
```

4. If tests fail:
   - Read the failing test file to understand what's being tested
   - Read the source code being tested
   - Explain WHY the test failed (not just what failed)
   - Suggest specific fixes for both the code OR the test (whichever is wrong)
   - If the test expectation is outdated, update the test
   - If the code has a bug, fix the code

5. For code coverage analysis:
```powershell
Invoke-Pester -Path ./Tests -Output Detailed -CodeCoverage ./Modules/*.psm1
```

## Output Format

Provide a summary like:
- Total tests: X
- Passed: X
- Failed: X
- Skipped: X

For each failure, explain:
1. What the test expected
2. What actually happened
3. Root cause analysis
4. Recommended fix
