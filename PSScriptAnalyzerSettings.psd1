# PSScriptAnalyzer Settings for WSUS-SQL Project
# Run with: Invoke-ScriptAnalyzer -Path . -Recurse -Settings PSScriptAnalyzerSettings.psd1

@{
    # Severity levels to include
    Severity = @('Error', 'Warning')

    # Rules to exclude
    ExcludeRules = @(
        # We use Write-Host intentionally for colored console output
        'PSAvoidUsingWriteHost',

        # Our functions deal with multiple related items (indexes, services, permissions)
        # Plural nouns accurately describe the operations
        'PSUseSingularNouns',

        # These are utility scripts, not production modules requiring ShouldProcess
        # Adding -WhatIf support to every function would add complexity without benefit
        'PSUseShouldProcessForStateChangingFunctions',

        # Write-Log is our custom logging function, not overwriting the built-in
        # (built-in only exists in PS Core 6.1+, we target PS 5.1+)
        'PSAvoidOverwritingBuiltInCmdlets'
    )

    # Rules to include (all others by default)
    IncludeRules = @(
        'PSAvoidUsingPlainTextForPassword',
        'PSAvoidUsingConvertToSecureStringWithPlainText',
        'PSAvoidUsingUsernameAndPasswordParams',
        'PSUsePSCredentialType',
        'PSAvoidUsingInvokeExpression',
        'PSAvoidAssignmentToAutomaticVariable',
        'PSAvoidUsingEmptyCatchBlock',
        'PSReviewUnusedParameter',
        'PSUseDeclaredVarsMoreThanAssignments',
        'PSPossibleIncorrectComparisonWithNull',
        'PSUseApprovedVerbs'
    )

    # Rule-specific settings
    Rules = @{
        # Allow comparing $null on right side for readability in some cases
        PSPossibleIncorrectComparisonWithNull = @{
            Enable = $true
        }

        # Check for common security issues
        PSAvoidUsingPlainTextForPassword = @{
            Enable = $true
        }
    }
}
