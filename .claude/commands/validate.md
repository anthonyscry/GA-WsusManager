# Run Local Validation

Run the full local validation suite (same checks as CI/CD) before committing.

## Instructions

1. Run the validation script:
```powershell
.\build\Invoke-LocalValidation.ps1
```

2. For a quick check (skip tests):
```powershell
.\build\Invoke-LocalValidation.ps1 -SkipTests
```

3. The validation runs:
   - **PSScriptAnalyzer**: Code quality checks on all .ps1, .psm1, .psd1 files
   - **XAML Validation**: Checks embedded XAML in GUI script
   - **Pester Tests**: Runs all unit tests in Tests folder

4. Fix any issues before committing:
   - **FAIL** results must be fixed
   - **WARN** results should be reviewed
   - **PASS** means you're good to go

## Output

The script will show:
- Summary for each check (PASS/FAIL/WARN/SKIP)
- Detailed issues with file, line number, and rule name
- Final validation status

## When to Use

- Before every commit
- After making significant changes
- Before creating a pull request
