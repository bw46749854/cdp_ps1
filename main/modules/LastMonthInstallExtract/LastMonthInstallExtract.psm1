$ErrorActionPreference = "Stop"
# 合成モジュール: LastMonthInstallExtract。internal配下の責務別ファイルを同一モジュールスコープに読み込む。

$foundationModulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Foundation\Foundation.psm1'
if (-not (Test-Path -LiteralPath $foundationModulePath)) { throw "Foundationモジュールが見つかりません: $foundationModulePath" }
Import-Module -Name $foundationModulePath -DisableNameChecking

foreach ($relativePath in @(
    'internal\Models.ps1',
    'internal\Encoding.ps1',
    'internal\DelimitedText.ps1',
    'internal\Rules.ps1',
    'internal\Input.ps1',
    'internal\Output.ps1',
    'internal\Dependencies.ps1',
    'internal\Workflow.ps1',
    'internal\Runner.ps1'
)) {
    $path = Join-Path $PSScriptRoot $relativePath
    if (-not (Test-Path -LiteralPath $path)) { throw "LastMonthInstallExtract internal file が見つかりません: $path" }
    . $path
}

Export-ModuleMember -Function @(
    'Invoke-LastMonthInstallExtractJob'
)
