$ErrorActionPreference = "Stop"
$modulePath = Join-Path $PSScriptRoot '..\modules\ScanTargetSync\ScanTargetSync.psm1'
Import-Module -Name $modulePath -Force

InModuleScope ScanTargetSync {
    Describe 'ScanTargetSync CSV input parsing and contract' {
        BeforeAll {
            function New-TestDeviceCsvRow {
                param(
                    [string]$Endpoint = 'PC-001',
                    [string]$User = 'user01',
                    [string]$Status = 'Online',
                    [string]$LastConnected = '2025-09-10T10:00:00+09:00',
                    [string]$ScanStarted = '2025-09-01T09:00:00+09:00',
                    [string]$ScanCompleted = '2025-09-01T10:00:00+09:00'
                )
                [pscustomobject]@{
                    'ホスト名' = $Endpoint
                    '利用者' = $User
                    '接続状態' = $Status
                    '最終通信日時' = $LastConnected
                    '手動スキャンの開始' = $ScanStarted
                    '手動スキャンの完了' = $ScanCompleted
                }
            }
        }

        It 'accepts a row containing all required Vendor CSV columns' {
            { Assert-ScanTargetSyncInputCsvContract -Rows @(New-TestDeviceCsvRow) } | Should -Not -Throw
        }

        It 'rejects an empty CSV payload' {
            { Assert-ScanTargetSyncInputCsvContract -Rows @() } | Should -Throw
        }

        It 'rejects rows missing required columns' {
            $row = [pscustomobject]@{ 'ホスト名' = 'PC-001' }
            { Assert-ScanTargetSyncInputCsvContract -Rows @($row) } | Should -Throw
        }

        It 'normalizes Vendor date values through specification-named parsing paths' {
            $cases = @(
                @{ Value = '2025-09-07T23:11:04+09:00'; Expected = '2025-09-07'; Reason = 'offset timestamp keeps displayed calendar date' },
                @{ Value = '2025-09-07T23:11:04.1234567+09:00'; Expected = '2025-09-07'; Reason = 'fractional offset timestamp keeps displayed calendar date' },
                @{ Value = '2025-09-07T23:11:04Z'; Expected = '2025-09-07'; Reason = 'Zulu timestamp keeps displayed calendar date' },
                @{ Value = '2025-09-07'; Expected = '2025-09-07'; Reason = 'ISO date-only value is accepted' },
                @{ Value = '2025/9/7 8:30:00'; Expected = '2025-09-07'; Reason = 'slash local timestamp is accepted' },
                @{ Value = '2025年09月07日 08:30:00'; Expected = '2025-09-07'; Reason = 'Japanese timestamp is accepted' },
                @{ Value = '2025-09-07 extra text'; Expected = '2025-09-07'; Reason = 'leading ISO date part is accepted as fallback' },
                @{ Value = '2025年9月7日 extra text'; Expected = '2025-09-07'; Reason = 'leading Japanese date part is accepted as fallback' },
                @{ Value = "  2025-09-07`n08:30:00  "; Expected = '2025-09-07'; Reason = 'whitespace is normalized before parsing' }
            )

            foreach ($case in $cases) {
                $date = Convert-VendorDateOnly -Value $case.Value
                $date.ToString('yyyy-MM-dd') | Should -Be $case.Expected -Because $case.Reason
            }
        }

        It 'parses ISO 8601 offset timestamps as the displayed calendar date' {
            $date = Convert-VendorDateOnly -Value '2025-09-07T23:11:04+09:00'
            $date.ToString('yyyy-MM-dd') | Should -Be '2025-09-07'
        }

        It 'parses Japanese date strings' {
            $date = Convert-VendorDateOnly -Value '2025年09月07日 08:30:00'
            $date.ToString('yyyy-MM-dd') | Should -Be '2025-09-07'
        }

        It 'returns null for blank, hyphen, and unparseable date values' {
            Convert-VendorDateOnly -Value '' | Should -Be $null
            Convert-VendorDateOnly -Value '-' | Should -Be $null
            Convert-VendorDateOnly -Value 'not-a-date' | Should -Be $null
        }
    }
}
