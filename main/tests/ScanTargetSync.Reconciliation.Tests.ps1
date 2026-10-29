$ErrorActionPreference = "Stop"
$modulePath = Join-Path $PSScriptRoot '..\modules\ScanTargetSync\ScanTargetSync.psm1'
Import-Module -Name $modulePath -Force

InModuleScope ScanTargetSync {
    Describe 'ScanTargetSync reconciliation' {
        BeforeAll {
            function New-TestTargetRow {
                param([string]$Endpoint = 'PC-001')
                [pscustomobject]@{
                    Endpoint = $Endpoint
                    User = 'user01'
                    Status = 'Online'
                    LastConnected = '2025-09-10'
                    ScanStarted = '2025-09-01'
                    ScanCompleted = '2025-09-01'
                    ElapsedDays = 9
                    Reason = 'test'
                }
            }

            function New-TestCsvRow {
                param([string]$Endpoint = 'PC-001')
                [pscustomobject]@{
                    'ホスト名' = $Endpoint
                    '利用者' = 'user01'
                    '接続状態' = 'Online'
                    '最終通信日時' = '2025-09-10'
                    '手動スキャンの開始' = '2025-09-01'
                    '手動スキャンの完了' = '2025-09-01'
                }
            }
        }

        It 'creates sync rows for ON and OFF classifications' {
            $rows = Get-ScanTargetSyncSyncRows -OnRows @((New-TestTargetRow -Endpoint 'PC-ON')) -OffRows @((New-TestTargetRow -Endpoint 'PC-OFF'))
            @($rows).Count | Should -Be 2
            $rows[0].DesiredChecked | Should -BeTrue
            $rows[0].DesiredState | Should -Be 'ON'
            $rows[1].DesiredChecked | Should -BeFalse
            $rows[1].DesiredState | Should -Be 'OFF'
        }

        It 'rejects sync row creation when CSV error rows are present' {
            $errorRow = [pscustomobject]@{ Endpoint = 'PC-ERR'; Reason = 'bad input' }
            { Get-ScanTargetSyncSyncRows -OnRows @() -OffRows @() -CsvErrorRows @($errorRow) } | Should -Throw
        }

        It 'detects duplicate endpoints in imported CSV rows' {
            $errors = Get-ScanTargetSyncDuplicateEndpointErrors -CsvRows @((New-TestCsvRow -Endpoint 'PC-001'), (New-TestCsvRow -Endpoint 'PC-001')) -Timestamp '2026-01-01 00:00:00'
            @($errors).Count | Should -Be 2
            $errors[0].Reason | Should -Match '重複'
        }

        It 'throws when sync rows contain duplicate endpoints' {
            $rows = @(
                (New-ScanTargetSyncSyncRow -SourceRow (New-TestTargetRow -Endpoint 'PC-001') -DesiredChecked $true -Classification 'checkedOn'),
                (New-ScanTargetSyncSyncRow -SourceRow (New-TestTargetRow -Endpoint 'PC-001') -DesiredChecked $false -Classification 'checkedOff')
            )
            { Assert-UniqueScanTargetSyncSyncRows -SyncRows $rows } | Should -Throw
        }

        It 'builds an endpoint lookup index for workflow scanning' {
            $rows = Get-ScanTargetSyncSyncRows -OnRows @((New-TestTargetRow -Endpoint 'PC-001')) -OffRows @()
            $index = New-ScanTargetSyncSyncIndex -SyncRows $rows
            $index.SyncEndpointSet.ContainsKey('PC-001') | Should -BeTrue
            $index.SyncRowByEndpoint['PC-001'].DesiredState | Should -Be 'ON'
        }
    }
}
