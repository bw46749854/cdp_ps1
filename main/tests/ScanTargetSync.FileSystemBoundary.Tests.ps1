$ErrorActionPreference = "Stop"
Describe 'ScanTargetSync FileSystem service boundary' {
    BeforeAll {
        $repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
        . (Join-Path $PSScriptRoot 'TestSupport.ps1')
        Import-Module -Name (Join-Path $repositoryRoot 'modules\ScanTargetSync\ScanTargetSync.psm1') -Force
    }

    BeforeEach {
        $script:ScanTargetSyncFileSystem = New-TestFileSystemService -RemoveFileIfExistsResult $true
        $script:ScanTargetSyncContext = [pscustomobject]@{
            Logger = $null
            JobSettings = [pscustomobject]@{
                OutputDirectory = 'C:\foundation\scan-target-sync'
                InputCsvPath = 'C:\foundation\input.csv'
                DaysThreshold = 30
                CsvErrorFileName = 'csv-errors.csv'
                FailureCsvFileName = 'failures.csv'
            }
            Services = [pscustomobject]@{
                FileSystem = $script:ScanTargetSyncFileSystem
            }
        }
    }

    It 'initializes the job output directory through the resolved FileSystem port' {
        InModuleScope ScanTargetSync -Parameters @{ Context = $script:ScanTargetSyncContext } {
            Initialize-ScanTargetSyncJob -Context $Context
        }

        Get-TestCallCount -Calls $script:ScanTargetSyncFileSystem.Calls -Name 'InitializeOutputDirectory' | Should -Be 1
        $call = @($script:ScanTargetSyncFileSystem.Calls | Where-Object { $_.Name -eq 'InitializeOutputDirectory' })[0]
        $call.Arguments.Directory | Should -Be 'C:\foundation\scan-target-sync'
        $call.Arguments.Purpose | Should -Be '出力'
    }

    It 'initializes workflow output through the injected dependency FileSystem port' {
        $dependencies = [pscustomobject]@{
            FileSystem = $script:ScanTargetSyncFileSystem
        }

        InModuleScope ScanTargetSync -Parameters @{ Context = $script:ScanTargetSyncContext; Dependencies = $dependencies } {
            Initialize-ScanTargetSyncWorkflow -Context $Context -Dependencies $Dependencies
        }

        Get-TestCallCount -Calls $script:ScanTargetSyncFileSystem.Calls -Name 'InitializeOutputDirectory' | Should -Be 1
        $call = @($script:ScanTargetSyncFileSystem.Calls | Where-Object { $_.Name -eq 'InitializeOutputDirectory' })[0]
        $call.Arguments.Directory | Should -Be 'C:\foundation\scan-target-sync'
        $call.Arguments.Purpose | Should -Be '出力'
    }

    It 'passes the injected FileSystem service into end CSV export behavior' {
        $state = [pscustomobject]@{
            CsvErrorRowsForExport = @()
            FailureRows = @()
            EndCsvExportCompleted = $false
        }

        InModuleScope ScanTargetSync -Parameters @{ Context = $script:ScanTargetSyncContext; State = $state; FileSystem = $script:ScanTargetSyncFileSystem } {
            Complete-ScanTargetSyncEndCsvExport -Context $Context -State $State -FileSystemService $FileSystem
        }

        $state.EndCsvExportCompleted | Should -BeTrue
        Get-TestCallCount -Calls $script:ScanTargetSyncFileSystem.Calls -Name 'InitializeOutputDirectory' | Should -Be 2
        Get-TestCallCount -Calls $script:ScanTargetSyncFileSystem.Calls -Name 'TestPathUnderDirectory' | Should -Be 2
        Get-TestCallCount -Calls $script:ScanTargetSyncFileSystem.Calls -Name 'RemoveFileIfExists' | Should -Be 2
    }

    It 'uses FileSystem port safety checks and rejects paths outside the allowed directory' {
        $fileSystem = New-TestFileSystemService -PathUnderDirectoryResult $false

        InModuleScope ScanTargetSync -Parameters @{ FileSystem = $fileSystem } {
            {
                Export-ScanTargetSyncFailureCsv `
                    -FailureRows @() `
                    -OutputDirectory 'C:\foundation\scan-target-sync' `
                    -FailureCsvFileName 'failures.csv' `
                    -FileSystemService $FileSystem
            } | Should -Throw '*許可ディレクトリ配下ではありません*'
        }

        Get-TestCallCount -Calls $fileSystem.Calls -Name 'InitializeOutputDirectory' | Should -Be 1
        Get-TestCallCount -Calls $fileSystem.Calls -Name 'TestPathUnderDirectory' | Should -Be 1
        Get-TestCallCount -Calls $fileSystem.Calls -Name 'RemoveFileIfExists' | Should -Be 0
    }
}
