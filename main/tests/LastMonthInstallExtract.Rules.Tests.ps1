$ErrorActionPreference = "Stop"
$modulePath = Join-Path $PSScriptRoot '..\modules\LastMonthInstallExtract\LastMonthInstallExtract.psm1'
Import-Module -Name $modulePath -Force

InModuleScope LastMonthInstallExtract {
    Describe 'LastMonthInstallExtract rules' {
        It 'extracts asset name from the expected CSV file name' {
            $result = Get-LastMonthInstallExtractAssetNameFromFileName -FileName 'app_list_PCXX-12-345.csv'

            $result.IsValid | Should -Be $true
            $result.AssetName | Should -Be 'PCXX-12-345'
        }

        It 'rejects unexpected CSV file names' {
            $result = Get-LastMonthInstallExtractAssetNameFromFileName -FileName 'app_list_ABC-12-345.csv'

            $result.IsValid | Should -Be $false
            $result.Reason | Should -Match 'ファイル名形式不一致'
        }

        It 'requires exact headers and order' {
            $required = @('アプリ名', 'バージョン', '導入日')

            (Test-LastMonthInstallExtractRequiredHeadersExact -Headers $required -RequiredHeaders $required).IsValid | Should -Be $true
            (Test-LastMonthInstallExtractRequiredHeadersExact -Headers @('バージョン', 'アプリ名', '導入日') -RequiredHeaders $required).IsValid | Should -Be $false
            (Test-LastMonthInstallExtractRequiredHeadersExact -Headers @('アプリ名', 'バージョン') -RequiredHeaders $required).IsValid | Should -Be $false
            (Test-LastMonthInstallExtractRequiredHeadersExact -Headers @('アプリ名', 'バージョン', '導入日', '備考') -RequiredHeaders $required).IsValid | Should -Be $false
        }

        It 'parses supported installation date formats' {
            (ConvertTo-LastMonthInstallExtractInstallDateOrNull -Value '2026-05-01').ToString('yyyy-MM-dd') | Should -Be '2026-05-01'
            (ConvertTo-LastMonthInstallExtractInstallDateOrNull -Value '2026/5/1').ToString('yyyy-MM-dd') | Should -Be '2026-05-01'
            (ConvertTo-LastMonthInstallExtractInstallDateOrNull -Value '2026年5月1日').ToString('yyyy-MM-dd') | Should -Be '2026-05-01'
            ConvertTo-LastMonthInstallExtractInstallDateOrNull -Value 'not-a-date' | Should -Be $null
        }

        It 'builds the previous month range from the injected current date' {
            $range = New-LastMonthInstallExtractMonthlyDateRange -Now ([datetime]'2026-06-16')

            $range.Today.ToString('yyyy-MM-dd') | Should -Be '2026-06-16'
            $range.StartInclusive.ToString('yyyy-MM-dd') | Should -Be '2026-05-01'
            $range.EndExclusive.ToString('yyyy-MM-dd') | Should -Be '2026-06-01'
            Test-LastMonthInstallExtractDateInRange -Date ([datetime]'2026-05-01') -StartInclusive $range.StartInclusive -EndExclusive $range.EndExclusive | Should -Be $true
            Test-LastMonthInstallExtractDateInRange -Date ([datetime]'2026-06-01') -StartInclusive $range.StartInclusive -EndExclusive $range.EndExclusive | Should -Be $false
        }
    }
}
