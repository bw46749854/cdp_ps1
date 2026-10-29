$ErrorActionPreference = "Stop"

Describe 'LastMonthInstallExtract output' {
    BeforeAll {
        $repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
        . (Join-Path $PSScriptRoot 'TestSupport.ps1')
        Import-Module -Name (Join-Path $repositoryRoot 'modules\LastMonthInstallExtract\LastMonthInstallExtract.psm1') -Force
    }

    BeforeEach {
        $script:Directory = Join-Path $TestDrive 'out'
        New-Item -ItemType Directory -Path $script:Directory -Force | Out-Null
    }

    It 'writes installation CSV rows in the fixed header order through FileSystem service checks' {
        $path = Join-Path $script:Directory 'pc_installation.csv'
        $rows = @(
            (InModuleScope LastMonthInstallExtract { New-LastMonthInstallExtractInstallationRow -AssetName 'PCXX-12-345' -ProductName 'A' -Version '1' -InstallDate '2026-05-01' })
        )
        $fileSystem = New-TestFileSystemService -CreateDirectories $true

        $result = InModuleScope LastMonthInstallExtract -Parameters @{ Rows = $rows; Path = $path; FileSystem = $fileSystem } {
            Export-LastMonthInstallExtractInstallationCsv -Rows $Rows -Path $Path -FileSystemService $FileSystem
        }

        $result.Count | Should -Be 1
        (Get-Content -LiteralPath $path -Encoding UTF8)[0] | Should -Be '"端末名","アプリ名","バージョン","導入日"'
        (Get-Content -LiteralPath $path -Raw -Encoding UTF8) | Should -Match 'PCXX-12-345'
        Get-TestCallCount -Calls $fileSystem.Calls -Name 'AssertSafeDirectory' | Should -Be 1
        Get-TestCallCount -Calls $fileSystem.Calls -Name 'TestPathUnderDirectory' | Should -Be 1
    }

    It 'writes only the installation header when there are no installation rows' {
        $path = Join-Path $script:Directory 'pc_installation.csv'
        $fileSystem = New-TestFileSystemService -CreateDirectories $true

        $result = InModuleScope LastMonthInstallExtract -Parameters @{ Path = $path; FileSystem = $fileSystem } {
            Export-LastMonthInstallExtractInstallationCsv -Rows @() -Path $Path -FileSystemService $FileSystem
        }

        $result.Count | Should -Be 0
        (Get-Content -LiteralPath $path -Raw -Encoding UTF8).Trim() | Should -Be '"端末名","アプリ名","バージョン","導入日"'
    }

    It 'writes failure CSV rows in the fixed header order' {
        $path = Join-Path $script:Directory 'pc_installation_failure_list.csv'
        $rows = @(
            (InModuleScope LastMonthInstallExtract { New-LastMonthInstallExtractFailureRow -FileName 'a.csv' -AssetName 'PCXX-12-345' -LineNumber '2' -Reason 'bad' -Timestamp '2026-06-16 12:00:00' })
        )
        $fileSystem = New-TestFileSystemService -CreateDirectories $true

        $result = InModuleScope LastMonthInstallExtract -Parameters @{ Rows = $rows; Path = $path; FileSystem = $fileSystem } {
            Export-LastMonthInstallExtractFailureCsv -FailureRows $Rows -Path $Path -FileSystemService $FileSystem
        }

        $result.Created | Should -BeTrue
        $result.Count | Should -Be 1
        (Get-Content -LiteralPath $path -Encoding UTF8)[0] | Should -Be '"FileName","AssetName","LineNumber","Reason","Timestamp"'
        (Get-Content -LiteralPath $path -Raw -Encoding UTF8) | Should -Match 'PCXX-12-345'
    }

    It 'removes a stale failure CSV when there are no failure rows' {
        $path = Join-Path $script:Directory 'pc_installation_failure_list.csv'
        Set-Content -LiteralPath $path -Value 'old' -Encoding UTF8
        $fileSystem = New-TestFileSystemService -CreateDirectories $true -RemoveFiles $true

        $result = InModuleScope LastMonthInstallExtract -Parameters @{ Path = $path; FileSystem = $fileSystem } {
            Export-LastMonthInstallExtractFailureCsv -FailureRows @() -Path $Path -FileSystemService $FileSystem
        }

        $result.Created | Should -BeFalse
        Test-Path -LiteralPath $path | Should -BeFalse
        Get-TestCallCount -Calls $fileSystem.Calls -Name 'RemoveFileIfExists' | Should -Be 1
    }

    It 'rejects installation CSV output when FileSystem service reports an unsafe path' {
        $path = Join-Path $script:Directory 'pc_installation.csv'
        $fileSystem = New-TestFileSystemService -PathUnderDirectoryResult $false

        InModuleScope LastMonthInstallExtract -Parameters @{ Path = $path; FileSystem = $fileSystem } {
            { Export-LastMonthInstallExtractInstallationCsv -Rows @() -Path $Path -FileSystemService $FileSystem } |
                Should -Throw '*アプリインストールCSV*許可ディレクトリ配下ではありません*'
        }
    }

    It 'rejects failure CSV output when FileSystem service reports an unsafe path' {
        $path = Join-Path $script:Directory 'pc_installation_failure_list.csv'
        $fileSystem = New-TestFileSystemService -PathUnderDirectoryResult $false

        InModuleScope LastMonthInstallExtract -Parameters @{ Path = $path; FileSystem = $fileSystem } {
            { Export-LastMonthInstallExtractFailureCsv -FailureRows @() -Path $Path -FileSystemService $FileSystem } |
                Should -Throw '*アプリ失敗CSV*許可ディレクトリ配下ではありません*'
        }
    }
}
