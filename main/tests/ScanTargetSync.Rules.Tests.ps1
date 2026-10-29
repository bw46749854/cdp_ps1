$ErrorActionPreference = "Stop"
$modulePath = Join-Path $PSScriptRoot '..\modules\ScanTargetSync\ScanTargetSync.psm1'
Import-Module -Name $modulePath -Force

InModuleScope ScanTargetSync {
    Describe 'ScanTargetSync target rules' {
        BeforeAll {
            function New-TestDeviceCsvRow {
                param(
                    [string]$Endpoint = 'PC-001',
                    [string]$LastConnected = '2025-09-10',
                    [string]$ScanCompleted = '2025-09-01'
                )
                [pscustomobject]@{
                    'ホスト名' = $Endpoint
                    '利用者' = 'user01'
                    '接続状態' = 'Online'
                    '最終通信日時' = $LastConnected
                    '手動スキャンの開始' = '2025-09-01'
                    '手動スキャンの完了' = $ScanCompleted
                }
            }
        }

        It 'returns stable evaluation objects through named result factories' {
            $cases = @(
                @{
                    ScanCompleted = '-'
                    LastConnected = '2025-09-10'
                    ExpectedIsTarget = $true
                    ExpectedIsCsvError = $false
                    ExpectedElapsedDays = $null
                    ExpectedReason = '手動スキャンの完了なし'
                    ExpectedErrorReason = $null
                },
                @{
                    ScanCompleted = 'bad-date'
                    LastConnected = '2025-09-10'
                    ExpectedIsTarget = $false
                    ExpectedIsCsvError = $true
                    ExpectedElapsedDays = $null
                    ExpectedReason = $null
                    ExpectedErrorReason = '手動スキャンの完了が日付として解釈不可'
                },
                @{
                    ScanCompleted = '2025-09-01'
                    LastConnected = 'bad-date'
                    ExpectedIsTarget = $false
                    ExpectedIsCsvError = $true
                    ExpectedElapsedDays = $null
                    ExpectedReason = $null
                    ExpectedErrorReason = '手動スキャンの完了は日付だが、最終通信日時が日付として解釈不可'
                },
                @{
                    ScanCompleted = '2025-09-10'
                    LastConnected = '2025-09-09'
                    ExpectedIsTarget = $false
                    ExpectedIsCsvError = $true
                    ExpectedElapsedDays = -1
                    ExpectedReason = $null
                    ExpectedErrorReason = '最終通信日時が手動スキャンの完了より古く、日付関係が不整合'
                },
                @{
                    ScanCompleted = '2025-09-01'
                    LastConnected = '2025-09-10'
                    ExpectedIsTarget = $true
                    ExpectedIsCsvError = $false
                    ExpectedElapsedDays = 9
                    ExpectedReason = '最終通信日時との差が 9 日'
                    ExpectedErrorReason = $null
                },
                @{
                    ScanCompleted = '2025-09-05'
                    LastConnected = '2025-09-10'
                    ExpectedIsTarget = $false
                    ExpectedIsCsvError = $false
                    ExpectedElapsedDays = 5
                    ExpectedReason = '最終通信日時との差が 5 日のため対象外'
                    ExpectedErrorReason = $null
                }
            )

            foreach ($case in $cases) {
                $evaluation = Get-ScanTargetSyncEvaluation `
                    -ScanCompletedRaw $case.ScanCompleted `
                    -LastConnectedRaw $case.LastConnected `
                    -DaysThreshold 7

                $evaluationPropertyNames = @($evaluation.PSObject.Properties.Name)
                ($evaluationPropertyNames -join ',') | Should -Be 'IsTarget,IsCsvError,ElapsedDays,Reason,ErrorReason'
                $evaluation.IsTarget | Should -Be $case.ExpectedIsTarget
                $evaluation.IsCsvError | Should -Be $case.ExpectedIsCsvError
                $evaluation.ElapsedDays | Should -Be $case.ExpectedElapsedDays
                $evaluation.Reason | Should -Be $case.ExpectedReason
                $evaluation.ErrorReason | Should -Be $case.ExpectedErrorReason
            }
        }

        It 'targets rows whose scan completion is blank or hyphen' {
            $evaluation = Get-ScanTargetSyncEvaluation -ScanCompletedRaw '-' -LastConnectedRaw '2025-09-10' -DaysThreshold 7
            $evaluation.IsTarget | Should -BeTrue
            $evaluation.IsCsvError | Should -BeFalse
            $evaluation.Reason | Should -Be '手動スキャンの完了なし'
        }

        It 'targets rows when elapsed days are greater than or equal to the threshold' {
            $evaluation = Get-ScanTargetSyncEvaluation -ScanCompletedRaw '2025-09-01' -LastConnectedRaw '2025-09-10' -DaysThreshold 7
            $evaluation.IsTarget | Should -BeTrue
            $evaluation.ElapsedDays | Should -Be 9
        }

        It 'classifies rows below the threshold as OFF targets' {
            $evaluation = Get-ScanTargetSyncEvaluation -ScanCompletedRaw '2025-09-05' -LastConnectedRaw '2025-09-10' -DaysThreshold 7
            $evaluation.IsTarget | Should -BeFalse
            $evaluation.IsCsvError | Should -BeFalse
            $evaluation.ElapsedDays | Should -Be 5
        }

        It 'marks invalid scan completion dates as CSV errors' {
            $evaluation = Get-ScanTargetSyncEvaluation -ScanCompletedRaw 'bad-date' -LastConnectedRaw '2025-09-10' -DaysThreshold 7
            $evaluation.IsCsvError | Should -BeTrue
            $evaluation.ErrorReason | Should -Be '手動スキャンの完了が日付として解釈不可'
        }

        It 'marks negative elapsed days as CSV errors' {
            $evaluation = Get-ScanTargetSyncEvaluation -ScanCompletedRaw '2025-09-10' -LastConnectedRaw '2025-09-09' -DaysThreshold 7
            $evaluation.IsCsvError | Should -BeTrue
            $evaluation.ElapsedDays | Should -Be -1
        }

        It 'extracts ON rows, OFF rows, and CSV error rows in one pass' {
            $rows = @(
                (New-TestDeviceCsvRow -Endpoint 'PC-ON' -LastConnected '2025-09-10' -ScanCompleted '2025-09-01'),
                (New-TestDeviceCsvRow -Endpoint 'PC-OFF' -LastConnected '2025-09-10' -ScanCompleted '2025-09-08'),
                (New-TestDeviceCsvRow -Endpoint '' -LastConnected '2025-09-10' -ScanCompleted '2025-09-01')
            )
            $result = Get-ScanTargetSyncTargetExtraction -CsvRows $rows -DaysThreshold 7 -Timestamp '2026-01-01 00:00:00'
            @($result.OnRows).Count | Should -Be 1
            @($result.OffRows).Count | Should -Be 1
            @($result.CsvErrorRows).Count | Should -Be 1
            $result.OnRows[0].Endpoint | Should -Be 'PC-ON'
            $result.OffRows[0].Endpoint | Should -Be 'PC-OFF'
        }
    }
}
