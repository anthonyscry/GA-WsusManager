#Requires -Modules Pester

BeforeAll {
    $script:HarnessPath = Join-Path $PSScriptRoot '..\Modules\WsusTestHarness.psm1'
    Import-Module $script:HarnessPath -Force -DisableNameChecking -WarningAction SilentlyContinue
}

AfterAll {
    Remove-Module WsusTestHarness -ErrorAction SilentlyContinue
}

Describe 'WsusTestHarness shared helpers' {
    It 'Resolves the repository root from the Tests directory' {
        $root = Resolve-WsusTestRepoRoot -StartPath $PSScriptRoot

        Test-Path (Join-Path $root 'Modules') | Should -BeTrue
        Test-Path (Join-Path $root 'Scripts') | Should -BeTrue
    }

    It 'Builds module paths from module names with or without extension' {
        $root = Resolve-WsusTestRepoRoot -StartPath $PSScriptRoot

        Get-WsusTestModulePath -ModuleName 'WsusConfig' -RepoRoot $root | Should -Be (Join-Path (Join-Path $root 'Modules') 'WsusConfig.psm1')
        Get-WsusTestModulePath -ModuleName 'WsusConfig.psm1' -RepoRoot $root | Should -Be (Join-Path (Join-Path $root 'Modules') 'WsusConfig.psm1')
    }

    It 'Creates isolated temporary roots' {
        $first = New-WsusTempHarnessRoot -Prefix 'WsusHarnessTests'
        $second = New-WsusTempHarnessRoot -Prefix 'WsusHarnessTests'
        try {
            Test-Path $first | Should -BeTrue
            Test-Path $second | Should -BeTrue
            $first | Should -Not -Be $second
        } finally {
            Remove-Item $first, $second -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Creates evidence roots and artifact paths' {
        $root = New-WsusTestEvidenceRoot -Prefix 'WsusEvidenceTests'
        try {
            $artifact = New-WsusTestArtifactPath -RootPath $root -FileName 'probe.json'
            Split-Path -Parent $artifact | Should -Be $root
            $artifact | Should -Match 'probe\.json$'
        } finally {
            Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Writes JSON evidence to disk' {
        $root = New-WsusTestEvidenceRoot -Prefix 'WsusEvidenceTests'
        try {
            $artifact = New-WsusTestArtifactPath -RootPath $root -FileName 'probe.json'
            $path = Write-WsusTestJsonEvidence -Path $artifact -InputObject @{ status = 'pass'; count = 1 }
            Test-Path $path | Should -BeTrue
            ((Get-Content $path -Raw) | ConvertFrom-Json).status | Should -Be 'pass'
        } finally {
            Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Reads repository-relative files as raw text' {
        $root = Resolve-WsusTestRepoRoot -StartPath $PSScriptRoot

        Get-WsusTestFileText -RepoRoot $root -RelativePath 'Scripts\WsusManagementGui.ps1' | Should -Match 'WSUS'
    }

    It 'Returns false for a missing FlaUI harness without throwing' {
        $missingPath = Join-Path ([System.IO.Path]::GetTempPath()) "missing-flaui-$([guid]::NewGuid().ToString('N')).psm1"

        Test-WsusFlaUIAssembliesAvailable -HarnessPath $missingPath | Should -BeFalse
    }

    It 'Stops missing test processes without throwing' {
        { Stop-WsusTestProcess -Name "WsusMissingProcess$([guid]::NewGuid().ToString('N'))" -Force } | Should -Not -Throw
    }
}
