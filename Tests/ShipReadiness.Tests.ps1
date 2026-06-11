#Requires -Modules Pester
<#!
.SYNOPSIS
    Static ship-readiness checks for build, CI, and secret handling.
#>

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:BuildContent = Get-Content (Join-Path $script:RepoRoot 'build.ps1') -Raw
    $script:WorkflowContent = Get-Content (Join-Path $script:RepoRoot '.github\workflows\gui-tests.yml') -Raw
    $script:PlanContent = Get-Content (Join-Path $script:RepoRoot 'Modules\WsusOperationPlan.psm1') -Raw
    $script:InstallContent = Get-Content (Join-Path $script:RepoRoot 'Scripts\Install-WsusWithSqlExpress.ps1') -Raw
}

Describe 'CI release gates' {
    It 'does not allow test steps to continue on error' {
        $script:WorkflowContent | Should -Not -Match 'continue-on-error:\s*true'
    }

    It 'builds in CI without git publishing side effects' {
        $script:WorkflowContent | Should -Match '\.\\build\.ps1\s+-SkipTests\s+-SkipCodeReview\s+-NoPush'
    }
}

Describe 'Build script release safety' {
    It 'requires explicit -Push before git commit or push' {
        $script:BuildContent | Should -Match '\[switch\]\$Push'
        $script:BuildContent | Should -Match 'if \(\$Push\s+-and\s+-not\s+\$NoPush\)'
    }

    It 'does not say artifacts were committed when -Push was not requested' {
        $script:BuildContent | Should -Not -Match 'The dist folder has been committed and pushed to git\.'
    }

    It 'captures Pester results so test failures block the build' {
        $script:BuildContent | Should -Match '\$config\.Run\.PassThru\s*=\s*\$true'
        $script:BuildContent | Should -Match '\$testResult\.FailedCount\s*-gt\s*0'
    }
}

Describe 'Installer secret handling' {
    It 'GUI install plan passes the SA password by environment variable name only' {
        $script:PlanContent | Should -Match '-SaPasswordEnvVar WSUS_INSTALL_SA_PASSWORD'
        $script:PlanContent | Should -Not -Match '-SaPassword `\$env:WSUS_INSTALL_SA_PASSWORD'
    }

    It 'non-interactive installer accepts SA password from a named environment variable' {
        $script:InstallContent | Should -Match '\[string\]\$SaPasswordEnvVar'
        $script:InstallContent | Should -Match '\[Environment\]::GetEnvironmentVariable\(\$SaPasswordEnvVar\)'
        $script:InstallContent | Should -Match 'Use -SaPasswordEnvVar or set the named environment variable'
    }
}
