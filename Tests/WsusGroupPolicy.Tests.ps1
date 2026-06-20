#Requires -Version 5.1
<#
.SYNOPSIS
    Tests for Set-WsusGroupPolicy.ps1 helper functions.
#>

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\Modules\WsusTestHarness.psm1') -Force -DisableNameChecking -WarningAction SilentlyContinue
    $script:RepoRoot = Resolve-WsusTestRepoRoot -StartPath $PSScriptRoot
    $script:ScriptContent = Get-WsusTestFileText -RepoRoot $script:RepoRoot -RelativePath 'DomainController\Set-WsusGroupPolicy.ps1'
    $script:ScriptContent = [regex]::Match($script:ScriptContent, '(?s)function Test-Prerequisites.*').Value
    $script:ScriptContent = $script:ScriptContent -replace '(?ms)#region Main Script.*$', ''
    . ([scriptblock]::Create($script:ScriptContent))
}

Describe 'Get-GpoDefinitions' {
    It 'Returns 4 GPO definitions' {
        $defs = Get-GpoDefinitions -DomainDN 'DC=example,DC=com'
        $defs.Count | Should -Be 4
    }
    It 'Includes WSUS Update Policy - Servers targeting Member Servers' {
        $defs = Get-GpoDefinitions -DomainDN 'DC=example,DC=com'
        ($defs | Where-Object DisplayName -eq 'WSUS Update Policy - Servers').TargetOUPaths[0] | Should -Be 'Member Servers'
        ($defs | Where-Object DisplayName -eq 'WSUS Update Policy - Servers').IncludeDomainControllers | Should -BeTrue
    }
    It 'Includes WSUS Update Policy - Workstations targeting Workstations' {
        $defs = Get-GpoDefinitions -DomainDN 'DC=example,DC=com'
        ($defs | Where-Object DisplayName -eq 'WSUS Update Policy - Workstations').TargetOUPaths[0] | Should -Be 'Workstations'
    }
    It 'Includes WSUS Inbound Allow' {
        (Get-GpoDefinitions -DomainDN 'DC=example,DC=com' | Where-Object DisplayName -eq 'WSUS Inbound Allow').UpdateWsusSettings | Should -BeFalse
    }
    It 'Includes WSUS Outbound Allow with IncludeDomainControllers flag' {
        (Get-GpoDefinitions -DomainDN 'DC=example,DC=com' | Where-Object DisplayName -eq 'WSUS Outbound Allow').IncludeDomainControllers | Should -BeTrue
    }
}

Describe 'Resolve-ExistingOuName' {
    It 'Prefers Member_Servers when that legacy OU exists' {
        Set-Item Function:Get-ADOrganizationalUnit -Value {
            param($Identity)
            if ($Identity -eq 'OU=Member_Servers,DC=example,DC=com') { return [pscustomobject]@{ DistinguishedName = $Identity } }
            throw 'Not found'
        }
        Resolve-ExistingOuName -Name 'Member Servers' -ParentDn 'DC=example,DC=com' | Should -Be 'Member_Servers'
    }
    It 'Returns preferred name when neither variant exists' {
        Set-Item Function:Get-ADOrganizationalUnit -Value { throw 'Not found' }
        Resolve-ExistingOuName -Name 'Member Servers' -ParentDn 'DC=example,DC=com' | Should -Be 'Member Servers'
    }
    It 'Returns preferred name for non-Member-Servers OUs' {
        Set-Item Function:Get-ADOrganizationalUnit -Value { throw 'Not found' }
        Resolve-ExistingOuName -Name 'Workstations' -ParentDn 'DC=example,DC=com' | Should -Be 'Workstations'
    }
    It 'Returns Member Servers when Member_Servers does not exist' {
        Set-Item Function:Get-ADOrganizationalUnit -Value {
            param($Identity) if ($Identity -eq 'OU=Member_Servers,DC=example,DC=com') { throw 'Not found' }
            return [pscustomobject]@{ DistinguishedName = $Identity }
        }
        Resolve-ExistingOuName -Name 'Member Servers' -ParentDn 'DC=example,DC=com' | Should -Be 'Member Servers'
    }
}

Describe 'Assert-OUExists' {
    It 'Skips creation when neither Member Servers variant exists' {
        $script:created = $false
        Set-Item Function:Get-ADOrganizationalUnit -Value { throw 'Not found' }
        Set-Item Function:New-ADOrganizationalUnit -Value { $script:created = $true }
        Assert-OUExists -OUPath 'Member Servers/WSUS Server' -DomainDN 'DC=example,DC=com' | Should -BeNullOrEmpty
        $script:created | Should -BeFalse
    }
    It 'Creates child WSUS Server OU under existing Member_Servers parent' {
        $script:calls = @()
        Set-Item Function:Get-ADOrganizationalUnit -Value {
            param($Identity) if ($Identity -ne 'OU=Member_Servers,DC=example,DC=com') { throw 'Not found' }
            return [pscustomobject]@{ DistinguishedName = $Identity }
        }
        Set-Item Function:New-ADOrganizationalUnit -Value { param($Name, $Path) $script:calls += [pscustomobject]@{ Name = $Name; Path = $Path } }
        Assert-OUExists -OUPath 'Member Servers/WSUS Server' -DomainDN 'DC=example,DC=com' | Should -Be 'OU=WSUS Server,OU=Member_Servers,DC=example,DC=com'
        $script:calls.Count | Should -Be 1
        $script:calls[0].Name | Should -Be 'WSUS Server'
    }
    It 'Returns DN without creating when OU already exists' {
        $script:created = $false
        Set-Item Function:Get-ADOrganizationalUnit -Value { param($Identity) [pscustomobject]@{ DistinguishedName = $Identity } }
        Set-Item Function:New-ADOrganizationalUnit -Value { $script:created = $true }
        Assert-OUExists -OUPath 'Workstations' -DomainDN 'DC=example,DC=com' | Should -Be 'OU=Workstations,DC=example,DC=com'
        $script:created | Should -BeFalse
    }
}

Describe 'Import-WsusGpo' {
    It 'Removes GPO links before deleting an existing GPO' {
        $script:links = @(); $script:removed = @()
        Set-Item Function:Get-GPO -Value { [pscustomobject]@{ DisplayName = 'WSUS Update Policy' } }
        Set-Item Function:Get-GPInheritance -Value { [pscustomobject]@{ GpoLinks = @([pscustomobject]@{ DisplayName = 'WSUS Update Policy' }) } }
        Set-Item Function:Remove-GPLink -Value { param($Name, $Target) $script:links += "$Name->$Target" }
        Set-Item Function:Remove-GPO -Value { param($Name) $script:removed += $Name }
        Set-Item Function:New-GPO -Value { [pscustomobject]@{ DisplayName = 'WSUS Update Policy' } }
        Set-Item Function:Import-GPO -Value { }
        Set-Item Function:Set-GPRegistryValue -Value { }
        Set-Item Function:Get-GPRegistryValue -Value { $null }
        Set-Item Function:Remove-GPRegistryValue -Value { }
        Set-Item Function:New-GPLink -Value { }
        $gpo = @{ DisplayName = 'WSUS Update Policy'; Description = 'Test'; UpdateWsusSettings = $false; TargetOUs = @('DC=example,DC=com') }
        Import-WsusGpo -GpoDefinition $gpo -Backup ([pscustomobject]@{ Id = '1234'; DisplayName = 'WSUS Update Policy' }) -BackupPath 'C:\Backup' -WsusUrl 'http://WSUS01:8530' -DomainDN 'DC=example,DC=com'
        $script:links.Count | Should -Be 1
        $script:removed | Should -Contain 'WSUS Update Policy'
    }
    It 'Does not delete when no existing GPO' {
        $script:removed = @()
        Set-Item Function:Get-GPO -Value { $null }
        Set-Item Function:Get-GPInheritance -Value { [pscustomobject]@{ GpoLinks = @() } }
        Set-Item Function:New-GPO -Value { [pscustomobject]@{ DisplayName = 'WSUS Update Policy' } }
        Set-Item Function:Import-GPO -Value { [pscustomobject]@{ DisplayName = 'WSUS Update Policy'; Id = [guid]::NewGuid() } }
        Set-Item Function:Get-GPRegistryValue -Value { $null }
        Set-Item Function:Set-GPRegistryValue -Value { }
        Set-Item Function:New-GPLink -Value { }
        Import-WsusGpo -GpoDefinition @{ DisplayName = 'WSUS Update Policy'; Description = 'Test'; UpdateWsusSettings = $true; TargetOUs = @('DC=example,DC=com') } -Backup ([pscustomobject]@{ Id = '1234'; DisplayName = 'WSUS Update Policy' }) -BackupPath 'C:\Backup' -WsusUrl 'http://WSUS01:8530' -DomainDN 'DC=example,DC=com'
        $script:removed.Count | Should -Be 0
    }
}

Describe 'Test-Prerequisites' {
    It 'Throws when GPMC feature install fails' {
        Set-Item Function:Get-Module -Value { $null }
        Set-Item Function:Add-WindowsFeature -Value { [pscustomobject]@{ Success = $false } }
        { Test-Prerequisites -ModuleName 'GroupPolicy' } | Should -Throw
    }
    It 'Succeeds when GPMC installs and module loads' {
        $script:installed = $false
        Set-Item Function:Get-Module -Value { $null }
        Set-Item Function:Add-WindowsFeature -Value { $script:installed = $true; [pscustomobject]@{ Success = $true } }
        Set-Item Function:Import-Module -Value { param($Name) }
        { Test-Prerequisites -ModuleName 'GroupPolicy' } | Should -Not -Throw
        $script:installed | Should -BeTrue
    }
}

Describe 'Get-WsusServerUrl' {
    It 'Returns the URL when provided as a parameter' { Get-WsusServerUrl -Url 'http://WSUS01:8530' | Should -Be 'http://WSUS01:8530' }
    It 'Accepts HTTPS URL' { Get-WsusServerUrl -Url 'https://wsus.domain.local:8531' | Should -Be 'https://wsus.domain.local:8531' }
}
