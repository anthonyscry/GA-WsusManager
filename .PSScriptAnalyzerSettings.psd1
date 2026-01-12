# PSScriptAnalyzer Settings for GA-WsusManager
# Apply consistent code quality rules across the entire codebase

@{
    # Severity levels to include
    Severity = @('Error', 'Warning')

    # Rules to exclude (with justification)
    ExcludeRules = @(
        # Write-Host is appropriate for CLI tools with colored feedback
        'PSAvoidUsingWriteHost',
        # GUI internal functions don't need ShouldProcess
        'PSUseShouldProcessForStateChangingFunctions',
        # Singular nouns rule conflicts with Settings/Utilities naming
        'PSUseSingularNouns'
    )

    # Rules to include explicitly (security + quality)
    IncludeRules = @(
        # Security rules
        'PSAvoidUsingPlainTextForPassword',
        'PSAvoidUsingConvertToSecureStringWithPlainText',
        'PSAvoidUsingUserNameAndPasswordParams',
        'PSAvoidUsingInvokeExpression',

        # Best practices
        'PSAvoidUsingCmdletAliases',
        'PSAvoidUsingPositionalParameters',
        'PSUseDeclaredVarsMoreThanAssignments',
        'PSUseApprovedVerbs',
        'PSReservedCmdletChar',
        'PSReservedParams',
        'PSMissingModuleManifestField',
        'PSAvoidDefaultValueSwitchParameter',
        'PSAvoidGlobalVars',
        'PSAvoidUsingEmptyCatchBlock',
        'PSUseCmdletCorrectly',
        'PSUseOutputTypeCorrectly'
    )

    # Custom rule configurations
    Rules = @{
        PSPlaceOpenBrace = @{
            Enable = $true
            OnSameLine = $true
            NewLineAfter = $true
            IgnoreOneLineBlock = $true
        }

        PSPlaceCloseBrace = @{
            Enable = $true
            NewLineAfter = $true
            IgnoreOneLineBlock = $true
            NoEmptyLineBefore = $false
        }

        PSProvideCommentHelp = @{
            Enable = $true
            ExportedOnly = $true
            BlockComment = $true
            VSCodeSnippetCorrection = $false
            Placement = 'begin'
        }
    }
}
