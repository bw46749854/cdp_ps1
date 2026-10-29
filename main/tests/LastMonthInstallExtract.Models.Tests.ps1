$ErrorActionPreference = "Stop"
$modulePath = Join-Path $PSScriptRoot '..\modules\LastMonthInstallExtract\LastMonthInstallExtract.psm1'
Import-Module -Name $modulePath -Force

InModuleScope LastMonthInstallExtract {
    Describe 'LastMonthInstallExtract models' {
        It 'creates installation rows with the public CSV column names' {
            $row = New-LastMonthInstallExtractInstallationRow -AssetName 'PCXX-12-345' -ProductName 'A' -Version '1.0' -InstallDate '2026-05-01'

            $row.'端末名' | Should -Be 'PCXX-12-345'
            $row.'アプリ名' | Should -Be 'A'
            $row.'バージョン' | Should -Be '1.0'
            $row.'導入日' | Should -Be '2026-05-01'
        }

        It 'creates failure rows for skipped file and row diagnostics' {
            $row = New-LastMonthInstallExtractFailureRow -FileName 'x.csv' -AssetName 'PCXX-12-345' -LineNumber '2' -Reason 'reason' -Timestamp '2026-06-16 12:00:00'

            $row.FileName | Should -Be 'x.csv'
            $row.AssetName | Should -Be 'PCXX-12-345'
            $row.LineNumber | Should -Be '2'
            $row.Reason | Should -Be 'reason'
            $row.Timestamp | Should -Be '2026-06-16 12:00:00'
        }
    }
}
