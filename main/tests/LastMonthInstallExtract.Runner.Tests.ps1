$ErrorActionPreference = "Stop"

Describe 'LastMonthInstallExtract runner' {
    BeforeAll {
        $repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
        . (Join-Path $PSScriptRoot 'TestSupport.ps1')
        Import-Module -Name (Join-Path $repositoryRoot 'modules\LastMonthInstallExtract\LastMonthInstallExtract.psm1') -Force

        function New-TestLastMonthInstallExtractJobFixture {
            param(
                [object[]]$Files = @(),
                [AllowNull()]$JobSettings = $null
            )

            $calls = New-TestCallList
            $fileContents = @{}

            $input = [pscustomobject]@{
                GetTargetCsvFiles = {
                    param(
                        [string]$TargetDirectory,
                        [string]$OutputCsvFileName,
                        [string]$FailureCsvFileName
                    )
                    [void]$calls.Add([pscustomobject]@{
                        Name = 'GetTargetCsvFiles'
                        Arguments = @{
                            TargetDirectory = $TargetDirectory
                            OutputCsvFileName = $OutputCsvFileName
                            FailureCsvFileName = $FailureCsvFileName
                        }
                    })
                    return @($Files)
                }.GetNewClosure()
                ReadAllBytes = {
                    param([string]$Path)
                    [void]$calls.Add([pscustomobject]@{
                        Name = 'ReadAllBytes'
                        Arguments = @{ Path = $Path }
                    })
                    if (-not $fileContents.ContainsKey($Path)) { throw "missing test content: $Path" }
                    return [System.Text.Encoding]::UTF8.GetBytes([string]$fileContents[$Path])
                }.GetNewClosure()
            }

            $output = [pscustomobject]@{
                InitializeOutputDirectory = {
                    param([string]$Directory)
                    [void]$calls.Add([pscustomobject]@{
                        Name = 'InitializeOutputDirectory'
                        Arguments = @{ Directory = $Directory }
                    })
                    return $Directory
                }.GetNewClosure()
                ExportInstallationCsv = {
                    param([object[]]$Rows, [string]$Path)
                    [void]$calls.Add([pscustomobject]@{
                        Name = 'ExportInstallationCsv'
                        Arguments = @{ Path = $Path; Count = @($Rows).Count }
                    })
                    return [pscustomobject]@{ Path = $Path; Count = @($Rows).Count; Created = $true }
                }.GetNewClosure()
                ExportFailureCsv = {
                    param([object[]]$FailureRows, [string]$Path)
                    [void]$calls.Add([pscustomobject]@{
                        Name = 'ExportFailureCsv'
                        Arguments = @{ Path = $Path; Count = @($FailureRows).Count }
                    })
                    return [pscustomobject]@{ Path = $Path; Count = @($FailureRows).Count; Created = (@($FailureRows).Count -gt 0) }
                }.GetNewClosure()
            }

            $logger = [pscustomobject]@{
                WriteInfo = {
                    param([string]$Message)
                    [void]$calls.Add([pscustomobject]@{
                        Name = 'WriteInfo'
                        Arguments = @{ Message = $Message }
                    })
                }.GetNewClosure()
                WriteWarning = {
                    param([string]$Message)
                    [void]$calls.Add([pscustomobject]@{
                        Name = 'WriteWarning'
                        Arguments = @{ Message = $Message }
                    })
                }.GetNewClosure()
                WriteSection = {
                    param([string]$Title)
                    [void]$calls.Add([pscustomobject]@{
                        Name = 'WriteSection'
                        Arguments = @{ Title = $Title }
                    })
                }.GetNewClosure()
            }

            $timing = [pscustomobject]@{
                Now = {
                    [void]$calls.Add([pscustomobject]@{
                        Name = 'Now'
                        Arguments = @{}
                    })
                    return [datetime]'2026-06-16'
                }.GetNewClosure()
                TimestampText = {
                    [void]$calls.Add([pscustomobject]@{
                        Name = 'TimestampText'
                        Arguments = @{}
                    })
                    return '2026-06-16 12:00:00'
                }.GetNewClosure()
            }

            if (-not $JobSettings) {
                $JobSettings = @{
                    TargetDirectory = 'C:\work\Downloads'
                    OutputCsvFileName = 'pc_installation.csv'
                    FailureCsvFileName = 'pc_installation_failure_list.csv'
                    FileNamePattern = '^.+_(PCXX-\d{2}-\d{3})\.csv$'
                    RequiredHeaders = @('アプリ名', 'バージョン', '導入日')
                }
            }

            return [pscustomobject]@{
                Context = [pscustomobject]@{ JobSettings = $JobSettings }
                Dependencies = [pscustomobject]@{
                    Input = $input
                    Output = $output
                    Logger = $logger
                    Timing = $timing
                }
                Calls = $calls
                FileContents = $fileContents
            }
        }
    }

    It 'initializes output before workflow, exports CSVs after workflow, and returns a result object' {
        $fixture = New-TestLastMonthInstallExtractJobFixture

        $result = InModuleScope LastMonthInstallExtract -Parameters @{ Context = $fixture.Context; Dependencies = $fixture.Dependencies } {
            Invoke-LastMonthInstallExtractJob -Context $Context -Dependencies $Dependencies
        }

        $result.DateRange.StartInclusive.ToString('yyyy-MM-dd') | Should -Be '2026-05-01'
        $result.ExportResult.OutputPath | Should -Be 'C:\work\Downloads\pc_installation.csv'
        $result.ExportResult.FailurePath | Should -Be 'C:\work\Downloads\pc_installation_failure_list.csv'

        $names = @($fixture.Calls | ForEach-Object { $_.Name })
        $names[0] | Should -Be 'InitializeOutputDirectory'
        ([array]::IndexOf($names, 'Now') -lt [array]::IndexOf($names, 'GetTargetCsvFiles')) | Should -BeTrue
        ([array]::IndexOf($names, 'GetTargetCsvFiles') -lt [array]::IndexOf($names, 'ExportInstallationCsv')) | Should -BeTrue
        ([array]::IndexOf($names, 'ExportInstallationCsv') -lt [array]::IndexOf($names, 'WriteSection')) | Should -BeTrue
    }


    It 'keeps standalone LastMonthInstallExtract execution using config TargetDirectory' {
        $fixture = New-TestLastMonthInstallExtractJobFixture -JobSettings @{
            TargetDirectory = 'C:\manual\app-target'
            OutputCsvFileName = 'pc_installation.csv'
            FailureCsvFileName = 'pc_installation_failure_list.csv'
            FileNamePattern = '^.+_(PCXX-\d{2}-\d{3})\.csv$'
            RequiredHeaders = @('アプリ名', 'バージョン', '導入日')
        }

        $result = InModuleScope LastMonthInstallExtract -Parameters @{ Context = $fixture.Context; Dependencies = $fixture.Dependencies } {
            Invoke-LastMonthInstallExtractJob -Context $Context -Dependencies $Dependencies
        }

        $getTargetCsvFilesCall = @($fixture.Calls | Where-Object { $_.Name -eq 'GetTargetCsvFiles' })[0]
        $getTargetCsvFilesCall.Arguments.TargetDirectory | Should -Be 'C:\manual\app-target'
        $result.ExportResult.OutputPath | Should -Be 'C:\manual\app-target\pc_installation.csv'
    }

    It 'throws when required job settings are missing' {
        $fixture = New-TestLastMonthInstallExtractJobFixture -JobSettings @{ TargetDirectory = ''; OutputCsvFileName = 'pc_installation.csv' }

        InModuleScope LastMonthInstallExtract -Parameters @{ Context = $fixture.Context; Dependencies = $fixture.Dependencies } {
            { Invoke-LastMonthInstallExtractJob -Context $Context -Dependencies $Dependencies } |
                Should -Throw '*TargetDirectory*'
        }
    }

    It 'uses the default failure CSV file name when the setting is omitted' {
        $fixture = New-TestLastMonthInstallExtractJobFixture -JobSettings @{
            TargetDirectory = 'C:\work\Downloads'
            OutputCsvFileName = 'pc_installation.csv'
        }

        $result = InModuleScope LastMonthInstallExtract -Parameters @{ Context = $fixture.Context; Dependencies = $fixture.Dependencies } {
            Invoke-LastMonthInstallExtractJob -Context $Context -Dependencies $Dependencies
        }

        $result.ExportResult.FailurePath | Should -Be 'C:\work\Downloads\pc_installation_failure_list.csv'
        ($fixture.Calls | Where-Object { $_.Name -eq 'GetTargetCsvFiles' })[0].Arguments.FailureCsvFileName |
            Should -Be 'pc_installation_failure_list.csv'
    }

    It 'writes a warning summary when skipped or failed rows remain' {
        $fixture = New-TestLastMonthInstallExtractJobFixture -Files @(
            [pscustomobject]@{ Name = 'unexpected.csv'; FullName = 'file1' }
        )

        $result = InModuleScope LastMonthInstallExtract -Parameters @{ Context = $fixture.Context; Dependencies = $fixture.Dependencies } {
            Invoke-LastMonthInstallExtractJob -Context $Context -Dependencies $Dependencies
        }

        $result.WorkflowResult.FailureRows.Count | Should -Be 1
        @($fixture.Calls | Where-Object {
            $_.Name -eq 'WriteWarning' -and $_.Arguments.Message -match '失敗/スキップ一覧CSVを出力しました'
        }).Count | Should -Be 1
    }
}
