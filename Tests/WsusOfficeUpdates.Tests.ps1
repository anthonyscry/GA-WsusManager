#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for WsusOfficeUpdates.psm1

.DESCRIPTION
    Unit tests for the Office C2R update management module including:
    - ODT path detection (Get-WsusOfficeOdtPath)
    - XML configuration generation (New-WsusOfficeDownloadConfig)
    - Client update tray config (New-WsusOfficeUpdateTrayConfig)
    - Download operation (Invoke-WsusOfficeDownload)
    - Share access validation (Test-WsusOfficeShareAccess)
    - Download status reporting (Get-WsusOfficeDownloadStatus)
#>

BeforeAll {
    # Import the module under test
    $ModulePath = Join-Path $PSScriptRoot "..\Modules\WsusOfficeUpdates.psm1"
    Import-Module $ModulePath -Force -DisableNameChecking

    # Also import config for Get-WsusOfficeC2RConfig
    $ConfigPath = Join-Path $PSScriptRoot "..\Modules\WsusConfig.psm1"
    if (Test-Path $ConfigPath) {
        Import-Module $ConfigPath -Force -DisableNameChecking -ErrorAction SilentlyContinue
    }
}

AfterAll {
    # Clean up
    Remove-Module WsusOfficeUpdates -ErrorAction SilentlyContinue
}

Describe "WsusOfficeUpdates Module" {
    Context "Module Loading" {
        It "Should import the module successfully" {
            Get-Module WsusOfficeUpdates | Should -Not -BeNullOrEmpty
        }

        It "Should export Get-WsusOfficeOdtPath function" {
            Get-Command Get-WsusOfficeOdtPath -Module WsusOfficeUpdates | Should -Not -BeNullOrEmpty
        }

        It "Should export New-WsusOfficeDownloadConfig function" {
            Get-Command New-WsusOfficeDownloadConfig -Module WsusOfficeUpdates | Should -Not -BeNullOrEmpty
        }

        It "Should export New-WsusOfficeUpdateTrayConfig function" {
            Get-Command New-WsusOfficeUpdateTrayConfig -Module WsusOfficeUpdates | Should -Not -BeNullOrEmpty
        }

        It "Should export Invoke-WsusOfficeDownload function" {
            Get-Command Invoke-WsusOfficeDownload -Module WsusOfficeUpdates | Should -Not -BeNullOrEmpty
        }

        It "Should export Test-WsusOfficeShareAccess function" {
            Get-Command Test-WsusOfficeShareAccess -Module WsusOfficeUpdates | Should -Not -BeNullOrEmpty
        }

        It "Should export Get-WsusOfficeDownloadStatus function" {
            Get-Command Get-WsusOfficeDownloadStatus -Module WsusOfficeUpdates | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "Get-WsusOfficeOdtPath" {
    Context "With custom valid path" {
        It "Should return the custom path when it exists" {
            $tempFile = Join-Path $env:TEMP "setup.exe"
            try {
                # Create a temp file to simulate ODT
                '' | Set-Content -Path $tempFile -Force
                $result = Get-WsusOfficeOdtPath -CustomPath $tempFile
                $result | Should -Be (Resolve-Path $tempFile).Path
            } finally {
                Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context "With non-existent custom path" {
        It "Should return null for non-existent path" {
            $result = Get-WsusOfficeOdtPath -CustomPath "C:\NonExistentOdtPath12345\setup.exe"
            $result | Should -BeNullOrEmpty
        }
    }

    Context "With null custom path" {
        It "Should not throw when custom path is null or empty" {
            { Get-WsusOfficeOdtPath -CustomPath "" | Out-Null } | Should -Not -Throw
            { Get-WsusOfficeOdtPath | Out-Null } | Should -Not -Throw
        }
    }
}

Describe "New-WsusOfficeDownloadConfig" {
    Context "LTSC channel for Office LTSC 2024" {
        It "Should generate valid XML for Office LTSC 2024" {
            $xml = New-WsusOfficeDownloadConfig -SourcePath "\\SERVER\Share" -Channel LTSC -ProductId OfficeLTSC2024
            $xml | Should -Not -BeNullOrEmpty
            $xml | Should -Match '<\?xml version="1.0" encoding="UTF-8"\?>'
            $xml | Should -Match '<Configuration>'
            $xml | Should -Match '</Configuration>'
        }

        It "Should use PerpetualVL2024 channel for LTSC" {
            $xml = New-WsusOfficeDownloadConfig -SourcePath "\\SERVER\Share" -Channel LTSC -ProductId OfficeLTSC2024
            $xml | Should -Match 'Channel="PerpetualVL2024"'
        }

        It "Should use ProPlus2024Volume product ID for Office LTSC 2024" {
            $xml = New-WsusOfficeDownloadConfig -SourcePath "\\SERVER\Share" -Channel LTSC -ProductId OfficeLTSC2024
            $xml | Should -Match 'Product ID="ProPlus2024Volume"'
        }

        It "Should include DWNtCurrentChannels for LTSC" {
            $xml = New-WsusOfficeDownloadConfig -SourcePath "\\SERVER\Share" -Channel LTSC -ProductId OfficeLTSC2024
            $xml | Should -Match 'DWNtCurrentChannels'
        }
    }

    Context "Monthly Enterprise channel for M365 Apps" {
        It "Should generate valid XML for M365 Apps" {
            $xml = New-WsusOfficeDownloadConfig -SourcePath "\\SERVER\Share" -Channel MonthlyEnterprise -ProductId M365Apps
            $xml | Should -Not -BeNullOrEmpty
            $xml | Should -Match '<\?xml version="1.0" encoding="UTF-8"\?>'
        }

        It "Should use Monthly Enterprise Channel name" {
            $xml = New-WsusOfficeDownloadConfig -SourcePath "\\SERVER\Share" -Channel MonthlyEnterprise -ProductId M365Apps
            $xml | Should -Match 'Channel="Monthly Enterprise Channel"'
        }

        It "Should use O365ProPlusRetail product ID for M365 Apps" {
            $xml = New-WsusOfficeDownloadConfig -SourcePath "\\SERVER\Share" -Channel MonthlyEnterprise -ProductId M365Apps
            $xml | Should -Match 'Product ID="O365ProPlusRetail"'
        }
    }

    Context "Visio LTSC 2024" {
        It "Should use VisioPro2024Volume product ID" {
            $xml = New-WsusOfficeDownloadConfig -SourcePath "\\SERVER\Share" -Channel LTSC -ProductId VisioLTSC2024
            $xml | Should -Match 'Product ID="VisioPro2024Volume"'
        }
    }

    Context "Project LTSC 2024" {
        It "Should use ProjectPro2024Volume product ID" {
            $xml = New-WsusOfficeDownloadConfig -SourcePath "\\SERVER\Share" -Channel LTSC -ProductId ProjectLTSC2024
            $xml | Should -Match 'Product ID="ProjectPro2024Volume"'
        }
    }

    Context "Language and architecture" {
        It "Should include specified language" {
            $xml = New-WsusOfficeDownloadConfig -SourcePath "\\SERVER\Share" -Channel MonthlyEnterprise -ProductId M365Apps -Language "fr-fr"
            $xml | Should -Match 'Language ID="fr-fr"'
        }

        It "Should include specified architecture" {
            $xml = New-WsusOfficeDownloadConfig -SourcePath "\\SERVER\Share" -Channel MonthlyEnterprise -ProductId M365Apps -OfficeClientEdition "32"
            $xml | Should -Match 'OfficeClientEdition="32"'
        }

        It "Should default to 64-bit" {
            $xml = New-WsusOfficeDownloadConfig -SourcePath "\\SERVER\Share" -Channel MonthlyEnterprise -ProductId M365Apps
            $xml | Should -Match 'OfficeClientEdition="64"'
        }
    }

    Context "SourcePath handling" {
        It "Should include SourcePath attribute" {
            $xml = New-WsusOfficeDownloadConfig -SourcePath "\\SERVER\Share" -Channel MonthlyEnterprise -ProductId M365Apps
            $xml | Should -Match 'SourcePath="\\\\SERVER\\Share"'
        }
    }
}

Describe "New-WsusOfficeUpdateTrayConfig" {
    Context "Basic XML generation" {
        It "Should generate valid update configuration XML" {
            $xml = New-WsusOfficeUpdateTrayConfig -UpdatePath "\\SERVER\Share\MonthlyEnterprise" -Channel MonthlyEnterprise
            $xml | Should -Not -BeNullOrEmpty
            $xml | Should -Match '<\?xml version="1.0" encoding="UTF-8"\?>'
            $xml | Should -Match '<Configuration>'
            $xml | Should -Match '</Configuration>'
        }

        It "Should include Enabled='True' for Updates" {
            $xml = New-WsusOfficeUpdateTrayConfig -UpdatePath "\\SERVER\Share" -Channel MonthlyEnterprise
            $xml | Should -Match 'Enabled="True"'
        }

        It "Should include UpdatePath attribute" {
            $xml = New-WsusOfficeUpdateTrayConfig -UpdatePath "\\SERVER\Share\MonthlyEnterprise" -Channel MonthlyEnterprise
            $xml | Should -Match 'UpdatePath="\\\\SERVER\\Share\\MonthlyEnterprise"'
        }

        It "Should include UpdateChannel attribute" {
            $xml = New-WsusOfficeUpdateTrayConfig -UpdatePath "\\SERVER\Share" -Channel MonthlyEnterprise
            $xml | Should -Match 'UpdateChannel="Monthly Enterprise Channel"'
        }
    }

    Context "Channel mapping" {
        It "Should map LTSC to PerpetualVL2024" {
            $xml = New-WsusOfficeUpdateTrayConfig -UpdatePath "\\SERVER\Share" -Channel LTSC
            $xml | Should -Match 'UpdateChannel="PerpetualVL2024"'
        }

        It "Should map Current to Current Channel" {
            $xml = New-WsusOfficeUpdateTrayConfig -UpdatePath "\\SERVER\Share" -Channel Current
            $xml | Should -Match 'UpdateChannel="Current Channel"'
        }
    }
}

Describe "Test-WsusOfficeShareAccess" {
    Context "With non-existent path" {
        It "Should return Accessible=false for non-existent path" {
            $result = Test-WsusOfficeShareAccess -Path "\\NONEXISTENT\Share12345"
            $result.Accessible | Should -Be $false
            $result.Message | Should -Not -BeNullOrEmpty
        }
    }

    Context "With null or empty path" {
        It "Should throw for null path" {
            { Test-WsusOfficeShareAccess -Path "" } | Should -Throw
        }
    }

    Context "With existing local path" {
        It "Should detect local path type" {
            $testDir = Join-Path $env:TEMP "OfficeC2RTest_$(Get-Random)"
            try {
                New-Item -Path $testDir -ItemType Directory -Force | Out-Null
                New-Item -Path (Join-Path $testDir "Office") -ItemType Directory -Force | Out-Null
                $result = Test-WsusOfficeShareAccess -Path $testDir
                $result.Accessible | Should -Be $true
                $result.PathType | Should -Be "Local"
            } finally {
                Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should report existing files when Office folder exists" {
            $testDir = Join-Path $env:TEMP "OfficeC2RTest_$(Get-Random)"
            try {
                New-Item -Path $testDir -ItemType Directory -Force | Out-Null
                $officeDir = Join-Path $testDir "Office\Data"
                New-Item -Path $officeDir -ItemType Directory -Force | Out-Null
                '' | Set-Content -Path (Join-Path $officeDir "v64.cab") -Force
                '' | Set-Content -Path (Join-Path $officeDir "v64.2.cab") -Force
                $result = Test-WsusOfficeShareAccess -Path $testDir
                $result.ExistingFiles | Should -Be 2
                $result.Accessible | Should -Be $true
            } finally {
                Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe "Get-WsusOfficeDownloadStatus" {
    Context "With non-existent path" {
        It "Should return empty array for non-existent path" {
            $result = Get-WsusOfficeDownloadStatus -Path "\\NONEXISTENT\Share12345"
            $result | Should -BeNullOrEmpty
        }
    }
    Context "With empty path" {
        It "Should throw for empty path (mandatory parameter)" {
            { Get-WsusOfficeDownloadStatus -Path "" } | Should -Throw
        }
    }

    Context "With existing path containing channel folders" {
        It "Should detect channel folders" {
            $testDir = Join-Path $env:TEMP "OfficeC2RTest_$(Get-Random)"
            try {
                # Create MonthlyEnterprise channel with Office data
                # PS 5.1 requires creating parent directories explicitly
                $channelDir = [System.IO.Path]::Combine($testDir, "MonthlyEnterprise", "Office", "Data")
                $null = New-Item -Path $channelDir -ItemType Directory -Force -ErrorAction Stop
                '' | Set-Content -Path ([System.IO.Path]::Combine($channelDir, "v64.cab")) -Force
                '' | Set-Content -Path ([System.IO.Path]::Combine($channelDir, "v64.2.cab")) -Force

                $results = Get-WsusOfficeDownloadStatus -Path $testDir
                $results | Should -Not -BeNullOrEmpty
                $channelResult = $results | Where-Object { $_.ChannelName -eq "MonthlyEnterprise" }
                $channelResult | Should -Not -BeNullOrEmpty
                $channelResult.HasData | Should -Be $true
            } finally {
                Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context "With root-level Office data" {
        It "Should detect Office data at root" {
            $testDir = Join-Path $env:TEMP "OfficeC2RTest_$(Get-Random)"
            try {
                $officeDir = Join-Path $testDir "Office"
                New-Item -Path $officeDir -ItemType Directory -Force | Out-Null
                '' | Set-Content -Path (Join-Path $officeDir "v64.cab") -Force

                $results = Get-WsusOfficeDownloadStatus -Path $testDir
                $hasRoot = $results | Where-Object { $_.ChannelName -eq "(root)" }
                $hasRoot | Should -Not -BeNullOrEmpty
            } finally {
                Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe "Invoke-WsusOfficeDownload" {
    Context "When ODT not found" {
        It "Should return failure with message about missing ODT" {
            $result = Invoke-WsusOfficeDownload -SourcePath "C:\Temp" -OdtPath "C:\NonExistentOdt\setup.exe"
            $result.Success | Should -Be $false
            $result.OdtFound | Should -Be $false
            $result.Message | Should -Match 'Office Deployment Tool'
        }
    }

    Context "When target path is inaccessible" {
        It "Should return failure with message about target directory" {
            $result = Invoke-WsusOfficeDownload -SourcePath "Z:\NonExistentDrive\OfficeC2R" -OdtPath "C:\NonExistentOdt\setup.exe"
            $result.Success | Should -Be $false
        }
    }
}

Describe "Get-WsusOfficeC2RConfig (if WsusConfig available)" {
    Context "Configuration defaults" {
        It "Should return configuration hashtable" -Skip:(-not (Get-Command Get-WsusOfficeC2RConfig -ErrorAction SilentlyContinue)) {
            $config = Get-WsusOfficeC2RConfig
            $config | Should -Not -BeNullOrEmpty
            $config.DefaultProduct | Should -Be "OfficeLTSC2024"
            $config.DefaultChannel | Should -Be "MonthlyEnterprise"
            $config.DefaultOfficeClientEdition | Should -Be "64"
            $config.DefaultLanguage | Should -Be "en-us"
        }
    }
}
