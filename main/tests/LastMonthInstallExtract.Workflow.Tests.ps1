$ErrorActionPreference = "Stop"

Describe 'LastMonthInstallExtract workflow' {
    BeforeAll {
        $repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
        . (Join-Path $PSScriptRoot 'TestSupport.ps1')
        Import-Module -Name (Join-Path $repositoryRoot 'modules\LastMonthInstallExtract\LastMonthInstallExtract.psm1') -Force

        function New-TestLastMonthInstallExtractWorkflowFixture {
            param(
                [object[]]$Files = @(
                    [pscustomobject]@{ Name = 'app_list_PCXX-12-345.csv'; FullName = 'file1' },
                    [pscustomobject]@{ Name = 'unexpected.csv'; FullName = 'file2' }
                ),
                [AllowNull()]$JobSettings = $null
            )

            $fileContents = @{}
            $inputCalls = New-TestCallList
            $logger = New-TestLoggerPort
            $timing = New-TestTimingService

            $input = [pscustomobject]@{
                Calls = $inputCalls
                GetTargetCsvFiles = {
                    param(
                        [string]$TargetDirectory,
                        [string]$OutputCsvFileName,
                        [string]$FailureCsvFileName
                    )

                    [void]$inputCalls.Add([pscustomobject]@{
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

                    [void]$inputCalls.Add([pscustomobject]@{
                        Name = 'ReadAllBytes'
                        Arguments = @{ Path = $Path }
                    })
                    if (-not $fileContents.ContainsKey($Path)) {
                        throw "テスト入力CSVが未定義です: $Path"
                    }

                    $content = $fileContents[$Path]
                    if ($content -is [byte[]]) { return $content }
                    return [System.Text.Encoding]::UTF8.GetBytes([string]$content)
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
                DateRange = [pscustomobject]@{
                    Today = [datetime]'2026-06-16'
                    StartInclusive = [datetime]'2026-05-01'
                    EndExclusive = [datetime]'2026-06-01'
                }
                Dependencies = [pscustomobject]@{
                    Input = $input
                    Logger = $logger
                    Timing = $timing
                }
                FileContents = $fileContents
                Input = $input
                Logger = $logger
                Timing = $timing
            }
        }
    }

    It 'extracts only previous-month installation rows and records skipped files' {
        $fixture = New-TestLastMonthInstallExtractWorkflowFixture
        $fixture.FileContents['file1'] = "アプリ名,バージョン,導入日`nA,1,2026-05-01`nB,2,2026-06-01`nC,3,invalid"

        $result = InModuleScope LastMonthInstallExtract -Parameters @{
            Context = $fixture.Context
            DateRange = $fixture.DateRange
            Dependencies = $fixture.Dependencies
        } {
            Invoke-LastMonthInstallExtractInstallationWorkflow -Context $Context -DateRange $DateRange -Dependencies $Dependencies
        }

        $result.InputFileCount | Should -Be 2
        $result.ProcessedFileCount | Should -Be 1
        $result.SkippedFileCount | Should -Be 1
        $result.ReadRowCount | Should -Be 3
        $result.MatchedRowCount | Should -Be 1
        $result.InstallationRows.Count | Should -Be 1
        $result.InstallationRows[0].'端末名' | Should -Be 'PCXX-12-345'
        $result.InstallationRows[0].'アプリ名' | Should -Be 'A'
        $result.InstallationRows[0].'バージョン' | Should -Be '1'
        $result.InstallationRows[0].'導入日' | Should -Be '2026-05-01'
        $result.FailureRows.Count | Should -Be 2
        (($result.FailureRows | ForEach-Object { $_.Reason }) -join "`n") | Should -Match '導入日を日付として解釈できない'
        (($result.FailureRows | ForEach-Object { $_.Reason }) -join "`n") | Should -Match 'ファイル名形式不一致'
        Get-TestCallCount -Calls $fixture.Logger.Calls -Name 'WriteWarning' | Should -Be 2
    }

    It 'skips files with invalid headers without stopping the workflow' {
        $fixture = New-TestLastMonthInstallExtractWorkflowFixture -Files @(
            [pscustomobject]@{ Name = 'app_list_PCXX-12-345.csv'; FullName = 'file1' }
        )
        $fixture.FileContents['file1'] = "アプリ名,導入日,バージョン`nA,2026-05-01,1"

        $result = InModuleScope LastMonthInstallExtract -Parameters @{
            Context = $fixture.Context
            DateRange = $fixture.DateRange
            Dependencies = $fixture.Dependencies
        } {
            Invoke-LastMonthInstallExtractInstallationWorkflow -Context $Context -DateRange $DateRange -Dependencies $Dependencies
        }

        $result.InstallationRows.Count | Should -Be 0
        $result.FailureRows.Count | Should -Be 1
        $result.SkippedFileCount | Should -Be 1
        $result.ProcessedFileCount | Should -Be 0
        $result.FailureRows[0].Reason | Should -Match 'カラム不一致'
    }

    It 'processes TSV files through the same workflow boundary' {
        $fixture = New-TestLastMonthInstallExtractWorkflowFixture -Files @(
            [pscustomobject]@{ Name = 'app_list_PCXX-12-345.csv'; FullName = 'file1' }
        )
        $fixture.FileContents['file1'] = "アプリ名`tバージョン`t導入日`nA`t1`t2026-05-20"

        $result = InModuleScope LastMonthInstallExtract -Parameters @{
            Context = $fixture.Context
            DateRange = $fixture.DateRange
            Dependencies = $fixture.Dependencies
        } {
            Invoke-LastMonthInstallExtractInstallationWorkflow -Context $Context -DateRange $DateRange -Dependencies $Dependencies
        }

        $result.ProcessedFileCount | Should -Be 1
        $result.SkippedFileCount | Should -Be 0
        $result.InstallationRows.Count | Should -Be 1
        $result.FailureRows.Count | Should -Be 0
    }

    It 'records malformed rows as row failures while continuing the file' {
        $fixture = New-TestLastMonthInstallExtractWorkflowFixture -Files @(
            [pscustomobject]@{ Name = 'app_list_PCXX-12-345.csv'; FullName = 'file1' }
        )
        $fixture.FileContents['file1'] = "アプリ名,バージョン,導入日`nA,1,2026-05-20`nBroken,1"

        $result = InModuleScope LastMonthInstallExtract -Parameters @{
            Context = $fixture.Context
            DateRange = $fixture.DateRange
            Dependencies = $fixture.Dependencies
        } {
            Invoke-LastMonthInstallExtractInstallationWorkflow -Context $Context -DateRange $DateRange -Dependencies $Dependencies
        }

        $result.ProcessedFileCount | Should -Be 1
        $result.SkippedFileCount | Should -Be 0
        $result.ReadRowCount | Should -Be 2
        $result.MatchedRowCount | Should -Be 1
        $result.InstallationRows.Count | Should -Be 1
        $result.FailureRows.Count | Should -Be 1
        $result.FailureRows[0].LineNumber | Should -Be '3'
        $result.FailureRows[0].Reason | Should -Match 'CSV行スキップ'
    }

    It 'uses workflow-only dependencies and passes configured input parameters' {
        $settings = [pscustomobject]@{
            TargetDirectory = 'C:\custom\Downloads'
            OutputCsvFileName = 'custom_installation.csv'
            FailureCsvFileName = 'custom_failures.csv'
            FileNamePattern = '^.+_(PCXX-\d{2}-\d{3})\.csv$'
            RequiredHeaders = @('アプリ名', 'バージョン', '導入日')
        }
        $fixture = New-TestLastMonthInstallExtractWorkflowFixture -Files @() -JobSettings $settings

        $result = InModuleScope LastMonthInstallExtract -Parameters @{
            Context = $fixture.Context
            DateRange = $fixture.DateRange
            Dependencies = $fixture.Dependencies
        } {
            Invoke-LastMonthInstallExtractInstallationWorkflow -Context $Context -DateRange $DateRange -Dependencies $Dependencies
        }

        $result.InputFileCount | Should -Be 0
        $fixture.Input.Calls[0].Arguments.TargetDirectory | Should -Be 'C:\custom\Downloads'
        $fixture.Input.Calls[0].Arguments.OutputCsvFileName | Should -Be 'custom_installation.csv'
        $fixture.Input.Calls[0].Arguments.FailureCsvFileName | Should -Be 'custom_failures.csv'
    }
}
