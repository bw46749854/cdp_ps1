$ErrorActionPreference = "Stop"
$modulePath = Join-Path $PSScriptRoot '..\modules\LastMonthInstallExtract\LastMonthInstallExtract.psm1'
Import-Module -Name $modulePath -Force

InModuleScope LastMonthInstallExtract {
    Describe 'LastMonthInstallExtract input' {
        It 'lists CSV files while excluding generated output files' {
            $dir = Join-Path $TestDrive 'Downloads'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $dir 'a_PCXX-12-345.csv') -Value 'x' -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $dir 'pc_installation.csv') -Value 'x' -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $dir 'pc_installation_failure_list.csv') -Value 'x' -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $dir 'not_csv.txt') -Value 'x' -Encoding UTF8

            $files = @(Get-LastMonthInstallExtractTargetCsvFileInfos -TargetDirectory $dir -OutputCsvFileName 'pc_installation.csv' -FailureCsvFileName 'pc_installation_failure_list.csv')

            $files.Count | Should -Be 1
            $files[0].Name | Should -Be 'a_PCXX-12-345.csv'
        }


        It 'excludes generated output files case-insensitively on Windows-style names' {
            $dir = Join-Path $TestDrive 'DownloadsCase'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $dir 'a_PCXX-12-345.csv') -Value 'x' -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $dir 'PC_INSTALLATION.CSV') -Value 'x' -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $dir 'PC_INSTALLATION_FAILURE_LIST.CSV') -Value 'x' -Encoding UTF8

            $files = @(Get-LastMonthInstallExtractTargetCsvFileInfos -TargetDirectory $dir -OutputCsvFileName 'pc_installation.csv' -FailureCsvFileName 'pc_installation_failure_list.csv')

            $files.Count | Should -Be 1
            $files[0].Name | Should -Be 'a_PCXX-12-345.csv'
        }

        It 'throws when the target directory is missing' {
            { Get-LastMonthInstallExtractTargetCsvFileInfos -TargetDirectory (Join-Path $TestDrive 'missing') -OutputCsvFileName 'pc_installation.csv' } | Should -Throw
        }
    }
}
