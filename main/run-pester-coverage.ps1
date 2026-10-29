$ScriptDirectory = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $PSScriptRoot
}
elseif ($MyInvocation.MyCommand.Path) {
    Split-Path -Parent $MyInvocation.MyCommand.Path
}
else {
    (Get-Location).Path
}

$repo = (Resolve-Path -LiteralPath $ScriptDirectory).Path
$pester = Join-Path $repo 'vendor\Pester\5.7.1\Pester.psd1'

Remove-Module Pester -Force -ErrorAction SilentlyContinue
Import-Module $pester -Force

Get-Module Pester | Format-List Name, Version, Path

$config = New-PesterConfiguration
$config.Run.Path = Join-Path $repo 'tests\*.Tests.ps1'
$config.Output.Verbosity = 'Detailed'
$config.Run.Exit = $true

$config.CodeCoverage.Enabled = $true
$config.CodeCoverage.Path = @(
    Join-Path $repo 'modules\Foundation'
    Join-Path $repo 'modules\CompositeJobs'
    Join-Path $repo 'modules\InstalledAppExport'
    Join-Path $repo 'modules\ScanTargetSync'
    Join-Path $repo 'modules\LastMonthInstallExtract'
    Join-Path $repo '*.ps1'
)
$config.CodeCoverage.OutputFormat = 'JaCoCo'
$config.CodeCoverage.OutputPath = Join-Path $repo 'coverage.xml'

Invoke-Pester -Configuration $config
