$ErrorActionPreference = "Stop"
# 合成モジュール: Foundation。internal配下の責務別ファイルを同一モジュールスコープに読み込む。

$script:FoundationModuleRoot = $PSScriptRoot
foreach ($relativePath in @(
    'internal\Config.ps1',
    'internal\JobRegistry.ps1',
    'internal\Logging.ps1',
    'internal\Errors.ps1',
    'internal\FileSystem.ps1',
    'internal\DomContract.ps1',
    'internal\CdpTransport.ps1',
    'internal\CdpSession.ps1',
    'internal\CdpConnection.ps1',
    'internal\CdpCommand.ps1',
    'internal\CdpBrowser.ps1',
    'internal\CdpRuntime.ps1',
    'internal\DomBundle.ps1',
    'internal\DomHelper.ps1',
    'internal\ScrollableList.ps1',
    'internal\RunContext.ps1',
    'internal\Bootstrap.ps1'
)) {
    $path = Join-Path $PSScriptRoot $relativePath
    if (-not (Test-Path -LiteralPath $path)) { throw "Foundation internal file が見つかりません: $path" }
    . $path
}

Export-ModuleMember -Function @(
    'Invoke-FoundationEntrypoint',
    'New-FoundationRunContext',
    'Close-FoundationRunContext',
    'Open-FoundationPage',
    'Open-FoundationPageMatchingIdentity',
    'Invoke-FoundationJavaScript',
    'Wait-FoundationJavaScript',
    'Set-FoundationDownloadDirectory',
    'Register-DomBundle',
    'Register-FoundationDomBundle',
    'Invoke-FoundationDomHelperMethod',
    'Wait-FoundationDomHelperMethod',
    'Wait-FoundationDomHelperMethodResult',
    'Assert-FoundationDomHelperContract',
    'Invoke-ScrollableListWorkflow',
    'Initialize-FoundationOutputDirectory',
    'Clear-DirectoryContentsSafely',
    'Assert-FoundationSafeDirectory',
    'Test-PathUnderDirectory',
    'Remove-FileIfExistsSafely',
    'Write-FoundationLog',
    'Write-FoundationSection',
    'Write-FoundationObject',
    'Test-FoundationFatalError'
)
