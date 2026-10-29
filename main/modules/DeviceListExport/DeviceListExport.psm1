$ErrorActionPreference = "Stop"
# 合成モジュール: DeviceListExport。internal配下の責務別ファイルを同一モジュールスコープに読み込む。

$foundationModulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Foundation\Foundation.psm1'
if (-not (Test-Path -LiteralPath $foundationModulePath)) { throw "Foundationモジュールが見つかりません: $foundationModulePath" }
Import-Module -Name $foundationModulePath -DisableNameChecking

foreach ($relativePath in @(
    'internal\DomOperations.ps1',
    'internal\DomAdapter.ps1',
    'internal\Download.ps1',
    'internal\Output.ps1',
    'internal\Dependencies.ps1',
    'internal\Workflow.ps1',
    'internal\Runner.ps1'
)) {
    $path = Join-Path $PSScriptRoot $relativePath
    if (-not (Test-Path -LiteralPath $path)) { throw "DeviceListExport internal file が見つかりません: $path" }
    . $path
}

Export-ModuleMember -Function @(
    'Invoke-DeviceListExportJob'
)
