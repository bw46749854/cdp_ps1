$ErrorActionPreference = "Stop"
$modulePath = Join-Path $PSScriptRoot '..\modules\InstalledAppExport\InstalledAppExport.psm1'
Import-Module -Name $modulePath -Force

InModuleScope InstalledAppExport {
    Describe 'InstalledAppExport models' {
        It 'returns visible row keys from data-id and asset name' {
            $row = [pscustomobject]@{ dataId = 'row-001'; assetName = 'PC-001' }
            Get-InstalledAppExportRowKey -Row $row | Should -Be 'row-001|PC-001'
        }

        It 'returns an empty key when identifying fields are missing' {
            $row = [pscustomobject]@{ dataId = ''; assetName = 'PC-001' }
            Get-InstalledAppExportRowKey -Row $row | Should -Be ''
        }

        It 'creates InstalledAppExport failure records with endpoint details and supplied timestamp' {
            $failure = New-InstalledAppExportFailure -AssetName 'PC-001' -DataId 'row-001' -Reason 'failed' -Timestamp '2026-01-02 03:04:05'
            $failure.AssetName | Should -Be 'PC-001'
            $failure.DataId | Should -Be 'row-001'
            $failure.Reason | Should -Be 'failed'
            $failure.Timestamp | Should -Be '2026-01-02 03:04:05'
        }
    }
}
