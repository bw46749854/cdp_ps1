$ErrorActionPreference = "Stop"

Describe 'LastMonthInstallExtract architecture guards' {
    BeforeAll {
        $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
        function Get-TextFilesUnderLastMonthInstallExtract {
            Get-ChildItem -LiteralPath (Join-Path $script:RepositoryRoot 'modules\LastMonthInstallExtract') -File -Recurse -Filter '*.ps1'
        }
    }
    It 'keeps LastMonthInstallExtract workflow and runner free from direct I/O, direct time, DOM, and CDP primitives' {
        $paths = @(
            (Join-Path $script:RepositoryRoot 'modules\LastMonthInstallExtract\internal\Workflow.ps1')
            (Join-Path $script:RepositoryRoot 'modules\LastMonthInstallExtract\internal\Runner.ps1')
        )
        $patterns = @(
            '(?<![A-Za-z0-9_])(Invoke-WebRequest|ClientWebSocket|Send-CDPCommand|Invoke-CDPJS)(?![A-Za-z0-9_])',
            '(?<![A-Za-z0-9_])(Register-FoundationDomBundle|Invoke-FoundationDomHelperMethod|Wait-FoundationDomHelperMethod)(?![A-Za-z0-9_])',
            '(?<![A-Za-z0-9_])(Get-ChildItem|Import-Csv|Export-Csv|Add-Content|Set-Content|Out-File|Get-Date|Start-Sleep|Write-Host|Write-Warning)(?![A-Za-z0-9_])'
        )

        foreach ($path in $paths) {
            $text = Get-Content -LiteralPath $path -Raw
            foreach ($pattern in $patterns) {
                $text | Should -Not -Match $pattern
            }
        }
    }

    It 'keeps LastMonthInstallExtract policy files independent from I/O, DOM, CDP, console, and direct time' {
        $paths = @(
            (Join-Path $script:RepositoryRoot 'modules\LastMonthInstallExtract\internal\Encoding.ps1')
            (Join-Path $script:RepositoryRoot 'modules\LastMonthInstallExtract\internal\DelimitedText.ps1')
            (Join-Path $script:RepositoryRoot 'modules\LastMonthInstallExtract\internal\Rules.ps1')
            (Join-Path $script:RepositoryRoot 'modules\LastMonthInstallExtract\internal\Models.ps1')
        )
        $pattern = '(?<![A-Za-z0-9_])(Get-ChildItem|Import-Csv|Export-Csv|Add-Content|Set-Content|Out-File|Get-Date|Start-Sleep|Write-Host|Write-Warning|Register-FoundationDomBundle|Invoke-FoundationDomHelperMethod|Invoke-CDPJS|Send-CDPCommand)(?![A-Za-z0-9_])'

        foreach ($path in $paths) {
            (Get-Content -LiteralPath $path -Raw) | Should -Not -Match $pattern
        }
    }

    It 'keeps LastMonthInstallExtract independent from DOM/CDP job modules' {
        foreach ($file in Get-TextFilesUnderLastMonthInstallExtract) {
            $text = Get-Content -LiteralPath $file.FullName -Raw
            $text | Should -Not -Match 'modules\\InstalledAppExport|modules/InstalledAppExport|Invoke-InstalledAppExportJob|modules\\ScanTargetSync|modules/ScanTargetSync|Invoke-ScanTargetSyncJob'
        }
    }
}
