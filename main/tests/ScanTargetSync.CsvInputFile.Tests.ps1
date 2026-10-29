$ErrorActionPreference = "Stop"
$modulePath = Join-Path $PSScriptRoot '..\modules\ScanTargetSync\ScanTargetSync.psm1'
Import-Module -Name $modulePath -Force

InModuleScope ScanTargetSync {
    Describe 'ScanTargetSync CSV input file import' {
        BeforeAll {
            function New-TestCsvInputFilePath {
                param([string]$Name)
                return (Join-Path $TestDrive $Name)
            }
        }

        It 'imports comma-delimited Vendor CSV files' {
            $path = New-TestCsvInputFilePath -Name 'devices.csv'
            Set-Content -LiteralPath $path -Encoding UTF8 -Value @(
                'ホスト名,利用者,接続状態,最終通信日時,手動スキャンの開始,手動スキャンの完了'
                'PC-001,user01,Online,2025-09-10T10:00:00+09:00,2025-09-01T09:00:00+09:00,2025-09-01T10:00:00+09:00'
            )

            $rows = @(Import-VendorDeviceCsv -Path $path)

            $rows.Count | Should -Be 1
            $rows[0].'ホスト名' | Should -Be 'PC-001'
            $rows[0].'利用者' | Should -Be 'user01'
        }

        It 'imports tab-delimited Vendor CSV files by detecting a tab in the header line' {
            $path = New-TestCsvInputFilePath -Name 'devices.tsv'
            Set-Content -LiteralPath $path -Encoding UTF8 -Value @(
                "ホスト名`t利用者`t接続状態`t最終通信日時`t手動スキャンの開始`t手動スキャンの完了"
                "PC-002`tuser02`tOffline`t2025-09-11T10:00:00+09:00`t2025-09-02T09:00:00+09:00`t2025-09-02T10:00:00+09:00"
            )

            $rows = @(Import-VendorDeviceCsv -Path $path)

            $rows.Count | Should -Be 1
            $rows[0].'ホスト名' | Should -Be 'PC-002'
            $rows[0].'接続状態' | Should -Be 'Offline'
        }

        It 'keeps Import-ScanTargetSyncInputCsv as the public alias of the same file importer' {
            $path = New-TestCsvInputFilePath -Name 'scan-target-sync.csv'
            Set-Content -LiteralPath $path -Encoding UTF8 -Value @(
                'ホスト名,利用者,接続状態,最終通信日時,手動スキャンの開始,手動スキャンの完了'
                'PC-003,user03,Online,2025-09-12T10:00:00+09:00,2025-09-03T09:00:00+09:00,2025-09-03T10:00:00+09:00'
            )

            $rows = @(Import-ScanTargetSyncInputCsv -Path $path)

            $rows.Count | Should -Be 1
            $rows[0].'ホスト名' | Should -Be 'PC-003'
        }

        It 'throws when the CSV path is blank' {
            { Import-VendorDeviceCsv -Path '   ' } | Should -Throw
        }

        It 'throws when the CSV file does not exist' {
            $path = New-TestCsvInputFilePath -Name 'missing.csv'
            { Import-VendorDeviceCsv -Path $path } | Should -Throw
        }

        It 'throws when the first line is empty' {
            $path = New-TestCsvInputFilePath -Name 'empty-header.csv'
            Set-Content -LiteralPath $path -Encoding UTF8 -Value @('', 'PC-001,user01')

            { Import-VendorDeviceCsv -Path $path } | Should -Throw
        }
    }
}
