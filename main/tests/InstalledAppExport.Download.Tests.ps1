$ErrorActionPreference = "Stop"
$modulePath = Join-Path $PSScriptRoot '..\modules\InstalledAppExport\InstalledAppExport.psm1'
Import-Module -Name $modulePath -Force

InModuleScope InstalledAppExport {
    Describe 'InstalledAppExport download helpers' {
        It 'normalizes unsafe file name characters and whitespace' {
            $safe = Convert-ToSafeFileNamePart -Value " PC/001`tA "
            $safe | Should -Match '^PC_001_A$|^PC/001_A$'
        }

        It 'returns the original unique path when it does not exist' {
            $path = Join-Path $TestDrive 'asset.csv'
            Get-UniqueFilePath -Path $path | Should -Be $path
        }

        It 'adds a numeric suffix when a file already exists' {
            $path = Join-Path $TestDrive 'asset.csv'
            Set-Content -LiteralPath $path -Value 'old' -Encoding UTF8
            $unique = Get-UniqueFilePath -Path $path
            [System.IO.Path]::GetFileName($unique) | Should -Be 'asset (1).csv'
        }
    }
}

InModuleScope InstalledAppExport {
    Describe 'Wait-DownloadedCsv' {
        It 'throws when download directory does not exist' {
            $missingDirectory = Join-Path $TestDrive 'missing'
            { Wait-DownloadedCsv -Directory $missingDirectory -Prefix 'asset' -TimeoutSeconds 1 -StableSeconds 0 } | Should -Throw
        }

        It 'returns a stable single CSV matching the prefix' {
            $directory = Join-Path $TestDrive 'downloads-single'
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
            $csvPath = Join-Path $directory 'asset_001.csv'
            Set-Content -LiteralPath $csvPath -Value 'a,b' -Encoding UTF8

            $result = Wait-DownloadedCsv -Directory $directory -Prefix 'asset' -TimeoutSeconds 1 -StableSeconds 0

            $result.Name | Should -Be 'asset_001.csv'
        }

        It 'throws when multiple CSV files match the prefix' {
            $directory = Join-Path $TestDrive 'downloads-multiple'
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $directory 'asset_001.csv') -Value 'a,b' -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $directory 'asset_002.csv') -Value 'a,b' -Encoding UTF8

            { Wait-DownloadedCsv -Directory $directory -Prefix 'asset' -TimeoutSeconds 1 -StableSeconds 0 } | Should -Throw
        }

        It 'waits while partial download files exist and returns the CSV after they disappear' {
            $directory = Join-Path $TestDrive 'downloads-partial'
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
            $csvPath = Join-Path $directory 'asset_001.csv'
            $partialPath = Join-Path $directory 'asset_001.csv.crdownload'
            Set-Content -LiteralPath $csvPath -Value 'a,b' -Encoding UTF8
            Set-Content -LiteralPath $partialPath -Value 'partial' -Encoding UTF8
            $script:InstalledAppExportDownloadPartialPath = $partialPath

            Mock Start-Sleep {
                if (Test-Path -LiteralPath $script:InstalledAppExportDownloadPartialPath) {
                    Remove-Item -LiteralPath $script:InstalledAppExportDownloadPartialPath -Force
                }
            }

            $result = Wait-DownloadedCsv -Directory $directory -Prefix 'asset' -TimeoutSeconds 1 -StableSeconds 0

            $result.Name | Should -Be 'asset_001.csv'
            Should -Invoke -CommandName Start-Sleep -Times 2 -Exactly
        }



        It 'selects partial download files and matching CSV candidates through named helpers' {
            $directory = Join-Path $TestDrive 'downloads-helper-contract'
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $directory 'asset_001.csv') -Value 'a,b' -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $directory 'asset_001.csv.crdownload') -Value 'partial' -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $directory 'other.csv') -Value 'x,y' -Encoding UTF8

            $partials = @(Get-PartialDownloadFiles -Directory $directory)
            $candidates = @(Get-DownloadedCsvCandidates -Directory $directory -Prefix 'asset')
            $candidate = Resolve-SingleDownloadedCsvCandidate -CsvFiles $candidates -Directory $directory

            $partials.Count | Should -Be 1
            $partials[0].Name | Should -Be 'asset_001.csv.crdownload'
            $candidates.Count | Should -Be 1
            $candidate.Name | Should -Be 'asset_001.csv'
        }

        It 'uses an injected wait runtime for timing without calling the real Start-Sleep command' {
            $directory = Join-Path $TestDrive 'downloads-runtime'
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $directory 'asset_001.csv') -Value 'a,b' -Encoding UTF8

            $script:InstalledAppExportDownloadRuntimeNow = [datetime]'2026-01-01T00:00:00'
            $script:InstalledAppExportDownloadRuntimeSleeps = New-Object System.Collections.Generic.List[string]
            $runtime = [pscustomobject]@{
                Now = { $script:InstalledAppExportDownloadRuntimeNow }
                SleepMilliseconds = {
                    param([int]$Milliseconds)
                    [void]$script:InstalledAppExportDownloadRuntimeSleeps.Add("ms:$Milliseconds")
                    $script:InstalledAppExportDownloadRuntimeNow = $script:InstalledAppExportDownloadRuntimeNow.AddMilliseconds($Milliseconds)
                }
                SleepSeconds = {
                    param([int]$Seconds)
                    [void]$script:InstalledAppExportDownloadRuntimeSleeps.Add("s:$Seconds")
                    $script:InstalledAppExportDownloadRuntimeNow = $script:InstalledAppExportDownloadRuntimeNow.AddSeconds($Seconds)
                }
            }

            Mock Start-Sleep { throw 'real Start-Sleep should not be called when Runtime is injected' }

            $result = Wait-DownloadedCsv `
                -Directory $directory `
                -Prefix 'asset' `
                -TimeoutSeconds 1 `
                -StableSeconds 0 `
                -Runtime $runtime

            $result.Name | Should -Be 'asset_001.csv'
            $script:InstalledAppExportDownloadRuntimeSleeps | Should -Contain 's:0'
            Should -Invoke -CommandName Start-Sleep -Times 0 -Exactly
        }

        It 'rejects incomplete download wait runtime contracts before polling' {
            $directory = Join-Path $TestDrive 'downloads-invalid-runtime'
            New-Item -ItemType Directory -Path $directory -Force | Out-Null

            $runtime = [pscustomobject]@{
                Now = { Get-Date }
                SleepMilliseconds = { param([int]$Milliseconds) }
            }

            { Wait-DownloadedCsv -Directory $directory -Prefix 'asset' -TimeoutSeconds 1 -StableSeconds 0 -Runtime $runtime } |
                Should -Throw '*SleepSeconds*'
        }

        It 'Wait-InstalledAppExportDownloadedCsv delegates to the common wait helper' {
            $directory = Join-Path $TestDrive 'downloads-wrapper'
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $directory 'asset_001.csv') -Value 'a,b' -Encoding UTF8

            $result = Wait-InstalledAppExportDownloadedCsv -Directory $directory -Prefix 'asset' -TimeoutSeconds 1 -StableSeconds 0

            $result.Name | Should -Be 'asset_001.csv'
        }
    }
}
