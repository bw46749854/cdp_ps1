$ErrorActionPreference = "Stop"

Describe 'CompositeJobs orchestration' {
    BeforeAll {
        $script:RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
        $script:CompositeJobsModulePath = Join-Path $script:RepositoryRoot 'modules\CompositeJobs\CompositeJobs.psm1'
        . (Join-Path $PSScriptRoot 'TestSupport.ps1')
        Import-Module -Name $script:CompositeJobsModulePath -Force

        function New-TestCompositeJobFixture {
            param(
                [hashtable]$ResultsByJob = @{},
                [string[]]$ExistingPaths = @(),
                [hashtable]$FilesByDirectory = @{},
                [hashtable]$Config = $null,
                [hashtable]$JobSettings = $null,
                [string]$RunTimestamp = '20260618_123456',
                [string]$RootPath = 'C:\repo\main',
                [string]$ConfigPath = 'C:\custom\foundation.config.psd1',
                [string]$JobRegistryPath = 'C:\custom\foundation.jobs.psd1'
            )

            $calls = New-TestCallList

            if ($null -eq $Config) {
                $Config = @{
                    Jobs = @{
                        InstalledAppExport = @{
                            DownloadFilePrefix = 'app_list_'
                        }
                    }
                }
            }

            if ($null -eq $JobSettings) {
                $JobSettings = @{
                    RunRootDirectory = 'C:\work\monthly\runs'
                }
            }

            $invokeJob = {
                param(
                    [string]$RootPath,
                    [string]$ConfigPath,
                    [string]$JobName,
                    [string]$JobRegistryPath,
                    [AllowNull()][hashtable]$JobSettingsOverrides = $null
                )

                [void]$calls.Add([pscustomobject]@{
                    Name = 'InvokeJob'
                    Arguments = @{
                        RootPath = $RootPath
                        ConfigPath = $ConfigPath
                        JobName = $JobName
                        JobRegistryPath = $JobRegistryPath
                        JobSettingsOverrides = $JobSettingsOverrides
                    }
                })

                if ($ResultsByJob.ContainsKey($JobName)) {
                    return $ResultsByJob[$JobName]
                }

                return $null
            }.GetNewClosure()

            $testPath = {
                param([string]$Path)
                [void]$calls.Add([pscustomobject]@{
                    Name = 'TestPath'
                    Arguments = @{ Path = $Path }
                })
                return (@($ExistingPaths) -contains $Path)
            }.GetNewClosure()

            $initializeDirectory = {
                param([string]$Directory, [string]$Purpose = 'CompositeJob')
                [void]$calls.Add([pscustomobject]@{
                    Name = 'InitializeDirectory'
                    Arguments = @{ Directory = $Directory; Purpose = $Purpose }
                })
                return $Directory
            }.GetNewClosure()

            $getFiles = {
                param([string]$Directory, [string]$Filter)
                [void]$calls.Add([pscustomobject]@{
                    Name = 'GetFiles'
                    Arguments = @{ Directory = $Directory; Filter = $Filter }
                })

                $files = @()
                if ($FilesByDirectory.ContainsKey($Directory)) {
                    $files = @($FilesByDirectory[$Directory])
                }

                return @($files | Where-Object { $_.Name -like $Filter })
            }.GetNewClosure()

            $runTimestampScript = {
                [void]$calls.Add([pscustomobject]@{
                    Name = 'RunTimestamp'
                    Arguments = @{}
                })
                return $RunTimestamp
            }.GetNewClosure()

            return [pscustomobject]@{
                Context = [pscustomobject]@{
                    RootPath = $RootPath
                    ConfigPath = $ConfigPath
                    JobRegistryPath = $JobRegistryPath
                    Config = $Config
                    JobSettings = $JobSettings
                }
                Dependencies = [pscustomobject]@{
                    Foundation = [pscustomobject]@{ InvokeJob = $invokeJob }
                    FileSystem = [pscustomobject]@{
                        TestPath = $testPath
                        InitializeDirectory = $initializeDirectory
                        GetFiles = $getFiles
                    }
                    Timing = [pscustomobject]@{ RunTimestamp = $runTimestampScript }
                }
                Calls = $calls
            }
        }

        function Get-TestCompositeChildJobCall {
            param(
                [Parameter(Mandatory)]$Calls,
                [Parameter(Mandatory)][string]$JobName
            )

            return @($Calls | Where-Object { $_.Name -eq 'InvokeJob' -and $_.Arguments.JobName -eq $JobName })
        }
    }

    Context 'WeeklyScanTargetSync' {
        It 'passes DeviceListExport ExportedCsvPath to ScanTargetSync InputCsvPath' {
            $exportedCsvPath = 'C:\work\weekly\Downloads\device_list.csv'
            $fixture = New-TestCompositeJobFixture `
                -ExistingPaths @($exportedCsvPath) `
                -ResultsByJob @{
                    DeviceListExport = [pscustomobject]@{
                        Ok = $true
                        Feature = 'DeviceListExport'
                        ExportedCsvPath = $exportedCsvPath
                    }
                    ScanTargetSync = [pscustomobject]@{
                        Feature = 'ScanTargetSync'
                    }
                }

            $result = InModuleScope CompositeJobs -Parameters @{ Context = $fixture.Context; Dependencies = $fixture.Dependencies } {
                Invoke-WeeklyScanTargetSyncJob -Context $Context -Dependencies $Dependencies
            }

            $selectCall = @(Get-TestCompositeChildJobCall -Calls $fixture.Calls -JobName 'ScanTargetSync')
            $selectCall.Count | Should -Be 1
            $selectCall[0].Arguments.JobSettingsOverrides.InputCsvPath | Should -Be $exportedCsvPath
            $result.InputCsvPath | Should -Be $exportedCsvPath
        }

        It 'does not execute ScanTargetSync when DeviceListExport returns a failed result' {
            $fixture = New-TestCompositeJobFixture -ResultsByJob @{
                DeviceListExport = [pscustomobject]@{
                    Ok = $false
                    Feature = 'DeviceListExport'
                    ExportedCsvPath = 'C:\work\device_list.csv'
                }
            }

            InModuleScope CompositeJobs -Parameters @{ Context = $fixture.Context; Dependencies = $fixture.Dependencies } {
                { Invoke-WeeklyScanTargetSyncJob -Context $Context -Dependencies $Dependencies } | Should -Throw '*DeviceListExport*成功結果*'
            }

            (Get-TestCompositeChildJobCall -Calls $fixture.Calls -JobName 'ScanTargetSync').Count | Should -Be 0
        }

        It 'fails safely when DeviceListExport ExportedCsvPath is empty' {
            $fixture = New-TestCompositeJobFixture -ResultsByJob @{
                DeviceListExport = [pscustomobject]@{
                    Ok = $true
                    Feature = 'DeviceListExport'
                    ExportedCsvPath = ''
                }
            }

            InModuleScope CompositeJobs -Parameters @{ Context = $fixture.Context; Dependencies = $fixture.Dependencies } {
                { Invoke-WeeklyScanTargetSyncJob -Context $Context -Dependencies $Dependencies } | Should -Throw '*ExportedCsvPath*空*'
            }

            (Get-TestCompositeChildJobCall -Calls $fixture.Calls -JobName 'ScanTargetSync').Count | Should -Be 0
        }

        It 'fails safely when DeviceListExport ExportedCsvPath does not exist' {
            $fixture = New-TestCompositeJobFixture -ResultsByJob @{
                DeviceListExport = [pscustomobject]@{
                    Ok = $true
                    Feature = 'DeviceListExport'
                    ExportedCsvPath = 'C:\work\missing.csv'
                }
            }

            InModuleScope CompositeJobs -Parameters @{ Context = $fixture.Context; Dependencies = $fixture.Dependencies } {
                { Invoke-WeeklyScanTargetSyncJob -Context $Context -Dependencies $Dependencies } | Should -Throw '*CSVが見つかりません*'
            }

            (Get-TestCompositeChildJobCall -Calls $fixture.Calls -JobName 'ScanTargetSync').Count | Should -Be 0
        }

        It 'passes custom ConfigPath and JobRegistryPath to child jobs' {
            $exportedCsvPath = 'C:\work\weekly\Downloads\device_list.csv'
            $fixture = New-TestCompositeJobFixture `
                -ConfigPath 'C:\other\custom.config.psd1' `
                -JobRegistryPath 'C:\other\custom.jobs.psd1' `
                -ExistingPaths @($exportedCsvPath) `
                -ResultsByJob @{
                    DeviceListExport = [pscustomobject]@{
                        Ok = $true
                        Feature = 'DeviceListExport'
                        ExportedCsvPath = $exportedCsvPath
                    }
                    ScanTargetSync = [pscustomobject]@{
                        Feature = 'ScanTargetSync'
                    }
                }

            InModuleScope CompositeJobs -Parameters @{ Context = $fixture.Context; Dependencies = $fixture.Dependencies } {
                Invoke-WeeklyScanTargetSyncJob -Context $Context -Dependencies $Dependencies | Out-Null
            }

            foreach ($call in @($fixture.Calls | Where-Object { $_.Name -eq 'InvokeJob' })) {
                $call.Arguments.ConfigPath | Should -Be 'C:\other\custom.config.psd1'
                $call.Arguments.JobRegistryPath | Should -Be 'C:\other\custom.jobs.psd1'
            }
        }
    }

    Context 'MonthlyInstallReport' {
        It 'creates a yyyyMMdd_HHmmss run directory and passes InstalledAppExport overrides' {
            $downloadDirectory = 'C:\work\monthly\runs\20260618_123456\installed_app_export_downloads'
            $fixture = New-TestCompositeJobFixture `
                -FilesByDirectory @{
                    $downloadDirectory = @([pscustomobject]@{
                        Name = 'app_list_20260618_PCXX-12-345.csv'
                        FullName = (Join-Path $downloadDirectory 'app_list_20260618_PCXX-12-345.csv')
                    })
                } `
                -ResultsByJob @{
                    InstalledAppExport = $null
                    LastMonthInstallExtract = [pscustomobject]@{ Feature = 'LastMonthInstallExtract' }
                }

            $result = InModuleScope CompositeJobs -Parameters @{ Context = $fixture.Context; Dependencies = $fixture.Dependencies } {
                Invoke-MonthlyInstallReportJob -Context $Context -Dependencies $Dependencies
            }

            $result.RunTimestamp | Should -Be '20260618_123456'
            $result.RunDirectory | Should -Be 'C:\work\monthly\runs\20260618_123456'
            @($fixture.Calls | Where-Object { $_.Name -eq 'InitializeDirectory' }).Count | Should -Be 3

            $installedAppExportCall = (Get-TestCompositeChildJobCall -Calls $fixture.Calls -JobName 'InstalledAppExport')[0]
            $installedAppExportCall.Arguments.JobSettingsOverrides.TempDirectory | Should -Be 'C:\work\monthly\runs\20260618_123456\installed_app_export_tmp'
            $installedAppExportCall.Arguments.JobSettingsOverrides.DownloadDirectory | Should -Be $downloadDirectory
        }

        It 'passes LastMonthInstallExtract TargetDirectory override equal to InstalledAppExport DownloadDirectory' {
            $downloadDirectory = 'C:\work\monthly\runs\20260618_123456\installed_app_export_downloads'
            $fixture = New-TestCompositeJobFixture `
                -FilesByDirectory @{
                    $downloadDirectory = @([pscustomobject]@{
                        Name = 'app_list_20260618_PCXX-12-345.csv'
                        FullName = (Join-Path $downloadDirectory 'app_list_20260618_PCXX-12-345.csv')
                    })
                }

            $result = InModuleScope CompositeJobs -Parameters @{ Context = $fixture.Context; Dependencies = $fixture.Dependencies } {
                Invoke-MonthlyInstallReportJob -Context $Context -Dependencies $Dependencies
            }

            $lastMonthInstallExtractCall = (Get-TestCompositeChildJobCall -Calls $fixture.Calls -JobName 'LastMonthInstallExtract')[0]
            $lastMonthInstallExtractCall.Arguments.JobSettingsOverrides.TargetDirectory | Should -Be $downloadDirectory
            $lastMonthInstallExtractCall.Arguments.JobSettingsOverrides.TargetDirectory | Should -Be $result.InstalledAppExportDownloadDirectory
            $result.TargetDirectory | Should -Be $downloadDirectory
        }

        It 'does not execute LastMonthInstallExtract when InstalledAppExport returns a failed result' {
            $fixture = New-TestCompositeJobFixture -ResultsByJob @{
                InstalledAppExport = [pscustomobject]@{ Ok = $false; Feature = 'InstalledAppExport' }
            }

            InModuleScope CompositeJobs -Parameters @{ Context = $fixture.Context; Dependencies = $fixture.Dependencies } {
                { Invoke-MonthlyInstallReportJob -Context $Context -Dependencies $Dependencies } | Should -Throw '*InstalledAppExport*失敗結果*'
            }

            (Get-TestCompositeChildJobCall -Calls $fixture.Calls -JobName 'LastMonthInstallExtract').Count | Should -Be 0
            @($fixture.Calls | Where-Object { $_.Name -eq 'GetFiles' }).Count | Should -Be 0
        }

        It 'does not execute LastMonthInstallExtract when InstalledAppExport exports no target CSV' {
            $fixture = New-TestCompositeJobFixture

            InModuleScope CompositeJobs -Parameters @{ Context = $fixture.Context; Dependencies = $fixture.Dependencies } {
                { Invoke-MonthlyInstallReportJob -Context $Context -Dependencies $Dependencies } | Should -Throw '*InstalledAppExport の成果物CSVが存在しません*'
            }

            (Get-TestCompositeChildJobCall -Calls $fixture.Calls -JobName 'LastMonthInstallExtract').Count | Should -Be 0
        }

        It 'does not treat unrelated CSV as InstalledAppExport export artifact' {
            $downloadDirectory = 'C:\work\monthly\runs\20260618_123456\installed_app_export_downloads'
            $fixture = New-TestCompositeJobFixture -FilesByDirectory @{
                $downloadDirectory = @([pscustomobject]@{
                    Name = 'installed_app_export_error_list.csv'
                    FullName = (Join-Path $downloadDirectory 'installed_app_export_error_list.csv')
                })
            }

            InModuleScope CompositeJobs -Parameters @{ Context = $fixture.Context; Dependencies = $fixture.Dependencies } {
                { Invoke-MonthlyInstallReportJob -Context $Context -Dependencies $Dependencies } | Should -Throw '*InstalledAppExport の成果物CSVが存在しません*'
            }

            (Get-TestCompositeChildJobCall -Calls $fixture.Calls -JobName 'LastMonthInstallExtract').Count | Should -Be 0
        }

        It 'uses InstalledAppExport DownloadFilePrefix when detecting exported artifacts' {
            $downloadDirectory = 'C:\work\monthly\runs\20260618_123456\installed_app_export_downloads'
            $fixture = New-TestCompositeJobFixture `
                -Config @{
                    Jobs = @{
                        InstalledAppExport = @{
                            DownloadFilePrefix = 'custom_prefix_'
                        }
                    }
                } `
                -FilesByDirectory @{
                    $downloadDirectory = @([pscustomobject]@{
                        Name = 'custom_prefix_001_PCXX-12-345.csv'
                        FullName = (Join-Path $downloadDirectory 'custom_prefix_001_PCXX-12-345.csv')
                    })
                }

            $result = InModuleScope CompositeJobs -Parameters @{ Context = $fixture.Context; Dependencies = $fixture.Dependencies } {
                Invoke-MonthlyInstallReportJob -Context $Context -Dependencies $Dependencies
            }

            $getFilesCall = @($fixture.Calls | Where-Object { $_.Name -eq 'GetFiles' })[0]
            $getFilesCall.Arguments.Filter | Should -Be 'custom_prefix_*.csv'
            $result.InstalledAppExportExportedCsvPaths[0] | Should -Match 'custom_prefix_001_PCXX-12-345\.csv$'
        }

        It 'fails safely when InstalledAppExport DownloadFilePrefix is empty' {
            $fixture = New-TestCompositeJobFixture -Config @{
                Jobs = @{
                    InstalledAppExport = @{
                        DownloadFilePrefix = ''
                    }
                }
            }

            InModuleScope CompositeJobs -Parameters @{ Context = $fixture.Context; Dependencies = $fixture.Dependencies } {
                { Invoke-MonthlyInstallReportJob -Context $Context -Dependencies $Dependencies } | Should -Throw '*DownloadFilePrefix*空*'
            }

            (Get-TestCompositeChildJobCall -Calls $fixture.Calls -JobName 'LastMonthInstallExtract').Count | Should -Be 0
        }

        It 'passes custom ConfigPath and JobRegistryPath to InstalledAppExport and LastMonthInstallExtract child jobs' {
            $downloadDirectory = 'C:\work\monthly\runs\20260618_123456\installed_app_export_downloads'
            $fixture = New-TestCompositeJobFixture `
                -ConfigPath 'C:\other\custom.config.psd1' `
                -JobRegistryPath 'C:\other\custom.jobs.psd1' `
                -FilesByDirectory @{
                    $downloadDirectory = @([pscustomobject]@{
                        Name = 'app_list_20260618_PCXX-12-345.csv'
                        FullName = (Join-Path $downloadDirectory 'app_list_20260618_PCXX-12-345.csv')
                    })
                }

            InModuleScope CompositeJobs -Parameters @{ Context = $fixture.Context; Dependencies = $fixture.Dependencies } {
                Invoke-MonthlyInstallReportJob -Context $Context -Dependencies $Dependencies | Out-Null
            }

            foreach ($call in @($fixture.Calls | Where-Object { $_.Name -eq 'InvokeJob' })) {
                $call.Arguments.ConfigPath | Should -Be 'C:\other\custom.config.psd1'
                $call.Arguments.JobRegistryPath | Should -Be 'C:\other\custom.jobs.psd1'
            }
        }
    }

    Context 'CompositeJobs source contract' {
        It 'keeps CompositeJobs free from DOM, CDP and CSV parsing responsibilities' {
            $source = Get-Content -LiteralPath ($script:CompositeJobsModulePath) -Raw
            $source | Should -Not -Match 'Invoke-FoundationDomHelperMethod|Wait-FoundationDomHelperMethod|Send-CDPCommand|Receive-CDPMessage|Open-CDPConnection'
            $source | Should -Not -Match '(?<![A-Za-z0-9_])(Import-Csv|ConvertFrom-Csv|Export-Csv)(?![A-Za-z0-9_])'
        }
    }
}
