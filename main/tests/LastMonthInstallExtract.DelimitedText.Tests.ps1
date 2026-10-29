$ErrorActionPreference = "Stop"
$modulePath = Join-Path $PSScriptRoot '..\modules\LastMonthInstallExtract\LastMonthInstallExtract.psm1'
Import-Module -Name $modulePath -Force

InModuleScope LastMonthInstallExtract {
    Describe 'LastMonthInstallExtract delimited text parser' {
        It 'detects TSV when the first line contains tabs' {
            Get-LastMonthInstallExtractDelimiterFromText -Text "アプリ名`tバージョン`t導入日`nA`t1`t2026-05-01" | Should -Be "`t"
        }

        It 'defaults to comma separated CSV' {
            Get-LastMonthInstallExtractDelimiterFromText -Text "アプリ名,バージョン,導入日`nA,1,2026-05-01" | Should -Be ','
        }

        It 'parses quoted commas, escaped quotes, and quoted newlines' {
            $text = "アプリ名,バージョン,導入日`n`"Product, A`",`"1`"`"2`",`"2026-05-01`nignored text`""
            $csv = Import-LastMonthInstallExtractDelimitedText -Text $text -Delimiter ','

            $csv.Rows.Count | Should -Be 1
            $csv.Rows[0].Data.'アプリ名' | Should -Be 'Product, A'
            $csv.Rows[0].Data.'バージョン' | Should -Be '1"2'
            $csv.Rows[0].Data.'導入日' | Should -Match '2026-05-01'
        }

        It 'marks rows malformed when the column count differs' {
            $csv = Import-LastMonthInstallExtractDelimitedText -Text "アプリ名,バージョン,導入日`nA,1" -Delimiter ','

            $csv.Rows[0].IsMalformed | Should -Be $true
            $csv.Rows[0].MalformedReason | Should -Match 'ヘッダー列数=3'
        }

        It 'throws on unclosed quotes' {
            { Import-LastMonthInstallExtractDelimitedText -Text "アプリ名,バージョン,導入日`n`"A,1,2026-05-01" -Delimiter ',' } | Should -Throw
        }
    }
}
