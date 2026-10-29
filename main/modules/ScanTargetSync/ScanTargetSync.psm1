$ErrorActionPreference = "Stop"
# 合成モジュール: ScanTargetSync。internal配下の責務別ファイルを同一モジュールスコープに読み込む。

$foundationModulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Foundation\Foundation.psm1'
if (-not (Test-Path -LiteralPath $foundationModulePath)) { throw "Foundationモジュールが見つかりません: $foundationModulePath" }
Import-Module -Name $foundationModulePath -DisableNameChecking

foreach ($relativePath in @(
    'internal\CsvInput.ps1',
    'internal\CsvInputFile.ps1',
    'internal\Rules.ps1',
    'internal\Output.ps1',
    'internal\Reconciliation.ps1',
    'internal\DomOperations.ps1',
    'internal\DomAdapter.ps1',
    'internal\Dependencies.ps1',
    'internal\Workflow.Display.ps1',
    'internal\Workflow.State.ps1',
    'internal\Workflow.Export.ps1',
    'internal\Workflow.Fatal.ps1',
    'internal\Workflow.CsvPlan.ps1',
    'internal\Workflow.Page.ps1',
    'internal\Workflow.UiScanState.ps1',
    'internal\Workflow.EndpointSync.ps1',
    'internal\Workflow.UiScan.ps1',
    'internal\Workflow.Result.ps1',
    'internal\Workflow.Orchestration.ps1',
    'internal\Workflow.ps1',
    'internal\Runner.ps1'
)) {
    $path = Join-Path $PSScriptRoot $relativePath
    if (-not (Test-Path -LiteralPath $path)) { throw "ScanTargetSync internal file が見つかりません: $path" }
    . $path
}

Export-ModuleMember -Function @(
    'Invoke-ScanTargetSyncJob'
)
