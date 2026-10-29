$ErrorActionPreference = "Stop"
Describe 'InstalledAppExport output' {
    BeforeAll {
        $repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
        . (Join-Path $PSScriptRoot 'TestSupport.ps1')
        Import-Module -Name (Join-Path $repositoryRoot 'modules\InstalledAppExport\InstalledAppExport.psm1') -Force
    }

    It 'removes stale InstalledAppExport failure CSV output through FileSystem service when there are no failures' {
        $path = Join-Path $TestDrive 'installed_app_export_failures.csv'
        Set-Content -LiteralPath $path -Value 'old' -Encoding UTF8
        $fileSystem = New-TestFileSystemService -CreateDirectories $true -RemoveFiles $true

        $result = InModuleScope InstalledAppExport -Parameters @{ Path = $path; FileSystem = $fileSystem } {
            Export-InstalledAppExportFailureCsv -FailureResults @() -Path $Path -FileSystemService $FileSystem
        }

        $result | Should -Be $null
        Test-Path -LiteralPath $path | Should -BeFalse
        Get-TestCallCount -Calls $fileSystem.Calls -Name 'AssertSafeDirectory' | Should -Be 1
        Get-TestCallCount -Calls $fileSystem.Calls -Name 'TestPathUnderDirectory' | Should -Be 1
        Get-TestCallCount -Calls $fileSystem.Calls -Name 'RemoveFileIfExists' | Should -Be 1
    }

    It 'rejects failure CSV output when FileSystem service reports an unsafe path' {
        $path = Join-Path $TestDrive 'installed_app_export_failures.csv'
        $fileSystem = New-TestFileSystemService -PathUnderDirectoryResult $false

        InModuleScope InstalledAppExport -Parameters @{ Path = $path; FileSystem = $fileSystem } {
            { Export-InstalledAppExportFailureCsv -FailureResults @() -Path $Path -FileSystemService $FileSystem } |
                Should -Throw 'InstalledAppExport失敗CSVの出力先が許可ディレクトリ配下ではありません*'
        }
    }
}
