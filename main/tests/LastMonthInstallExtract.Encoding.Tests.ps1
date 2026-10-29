$ErrorActionPreference = "Stop"
$modulePath = Join-Path $PSScriptRoot '..\modules\LastMonthInstallExtract\LastMonthInstallExtract.psm1'
Import-Module -Name $modulePath -Force

InModuleScope LastMonthInstallExtract {
    Describe 'LastMonthInstallExtract encoding reader' {
        It 'reads UTF-8 without BOM strictly' {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes('アプリ名,バージョン,導入日')

            $result = ConvertFrom-LastMonthInstallExtractSupportedBytes -Bytes $bytes

            $result.EncodingName | Should -Be 'UTF-8 BOMなし'
            $result.Text | Should -Match 'アプリ名'
        }

        It 'reads UTF-8 with BOM and strips the BOM bytes' {
            $body = [System.Text.Encoding]::UTF8.GetBytes('アプリ名')
            $bytes = [byte[]]@(0xEF, 0xBB, 0xBF) + $body

            $result = ConvertFrom-LastMonthInstallExtractSupportedBytes -Bytes $bytes

            $result.EncodingName | Should -Be 'UTF-8 BOM付き'
            $result.Text | Should -Be 'アプリ名'
        }

        It 'reads UTF-16 LE with BOM' {
            $encoding = New-Object System.Text.UnicodeEncoding($false, $true)
            $bytes = [byte[]]@(0xFF, 0xFE) + $encoding.GetBytes('アプリ名')

            $result = ConvertFrom-LastMonthInstallExtractSupportedBytes -Bytes $bytes

            $result.EncodingName | Should -Be 'UTF-16 LE BOM付き'
            $result.Text | Should -Be 'アプリ名'
        }



        It 'reads UTF-16 BE with BOM' {
            $encoding = New-Object System.Text.UnicodeEncoding($true, $true)
            $bytes = [byte[]]@(0xFE, 0xFF) + $encoding.GetBytes('アプリ名')

            $result = ConvertFrom-LastMonthInstallExtractSupportedBytes -Bytes $bytes

            $result.EncodingName | Should -Be 'UTF-16 BE BOM付き'
            $result.Text | Should -Be 'アプリ名'
        }

        It 'reads UTF-32 LE with BOM' {
            $encoding = New-Object System.Text.UTF32Encoding($false, $true)
            $bytes = [byte[]]@(0xFF, 0xFE, 0x00, 0x00) + $encoding.GetBytes('アプリ名')

            $result = ConvertFrom-LastMonthInstallExtractSupportedBytes -Bytes $bytes

            $result.EncodingName | Should -Be 'UTF-32 LE BOM付き'
            $result.Text | Should -Be 'アプリ名'
        }

        It 'reads UTF-32 BE with BOM' {
            $encoding = New-Object System.Text.UTF32Encoding($true, $true)
            $bytes = [byte[]]@(0x00, 0x00, 0xFE, 0xFF) + $encoding.GetBytes('アプリ名')

            $result = ConvertFrom-LastMonthInstallExtractSupportedBytes -Bytes $bytes

            $result.EncodingName | Should -Be 'UTF-32 BE BOM付き'
            $result.Text | Should -Be 'アプリ名'
        }

        It 'reports an encoding guess when bytes cannot be decoded as supported text' {
            $bytes = [byte[]]@(0x80, 0x80, 0x80)

            { ConvertFrom-LastMonthInstallExtractSupportedBytes -Bytes $bytes } |
                Should -Throw '*推定文字コード*'
        }

        It 'rejects empty files' {
            { ConvertFrom-LastMonthInstallExtractSupportedBytes -Bytes ([byte[]]@()) } | Should -Throw
        }
    }
}
