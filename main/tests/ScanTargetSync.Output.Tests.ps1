$ErrorActionPreference = "Stop"
Describe 'ScanTargetSync output rows and CSV export' {
    BeforeAll {
        $repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
        . (Join-Path $PSScriptRoot 'TestSupport.ps1')
        Import-Module -Name (Join-Path $repositoryRoot 'modules\ScanTargetSync\ScanTargetSync.psm1') -Force
    }

    It 'creates failure rows with the expected stable columns' {
        $row = InModuleScope ScanTargetSync {
            New-ScanTargetSyncFailureRow -Endpoint 'PC-001' -DataId 'row-1' -User 'user01' -Status 'Online' -LastConnected '2025-09-10' -ScanStarted '2025-09-01' -ScanCompleted '2025-09-01' -Reason 'failed'
        }

        $row.Endpoint | Should -Be 'PC-001'
        $row.DataId | Should -Be 'row-1'
        $row.Reason | Should -Be 'failed'
        $row.PSObject.Properties.Name | Should -Contain 'Timestamp'
    }

    It 'removes stale empty error CSV output through FileSystem service when there are no errors' {
        $path = Join-Path $TestDrive 'csv_errors.csv'
        Set-Content -LiteralPath $path -Value 'old' -Encoding UTF8
        $fileSystem = New-TestFileSystemService -CreateDirectories $true -RemoveFiles $true

        $result = InModuleScope ScanTargetSync -Parameters @{ OutputDirectory = $TestDrive; FileSystem = $fileSystem } {
            Export-ScanTargetSyncCsvErrorCsv `
                -ErrorRows @() `
                -OutputDirectory $OutputDirectory `
                -ErrorCsvFileName 'csv_errors.csv' `
                -FileSystemService $FileSystem
        }

        $result.ErrorCsvCreated | Should -BeFalse
        $result.OldErrorCsvRemoved | Should -BeTrue
        Test-Path -LiteralPath $path | Should -BeFalse
        Get-TestCallCount -Calls $fileSystem.Calls -Name 'InitializeOutputDirectory' | Should -Be 1
        Get-TestCallCount -Calls $fileSystem.Calls -Name 'TestPathUnderDirectory' | Should -Be 1
        Get-TestCallCount -Calls $fileSystem.Calls -Name 'RemoveFileIfExists' | Should -Be 1
    }

    It 'rejects failure CSV output when FileSystem service reports an unsafe path' {
        $fileSystem = New-TestFileSystemService -PathUnderDirectoryResult $false

        InModuleScope ScanTargetSync -Parameters @{ OutputDirectory = $TestDrive; FileSystem = $fileSystem } {
            { Export-ScanTargetSyncFailureCsv -FailureRows @() -OutputDirectory $OutputDirectory -FailureCsvFileName 'failures.csv' -FileSystemService $FileSystem } |
                Should -Throw 'チェック処理失敗CSVの出力先が許可ディレクトリ配下ではありません*'
        }
    }
}
