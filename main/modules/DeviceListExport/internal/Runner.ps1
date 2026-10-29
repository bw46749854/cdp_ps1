$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

function Initialize-DeviceListExportOutputDirectories {
    param([Parameter(Mandatory)]$Context)

    $settings = $Context.JobSettings
    $Context.Services.FileSystem.InitializeOutputDirectory.Invoke($settings.TempDirectory, 'DeviceListExport一時ダウンロード') | Out-Null
    $Context.Services.FileSystem.InitializeOutputDirectory.Invoke($settings.DownloadDirectory, 'DeviceListExport最終保存') | Out-Null
    $Context.Services.FileSystem.ClearDirectory.Invoke($settings.TempDirectory, 'DeviceListExport一時ダウンロード')
}

function Open-DeviceListExportBrowserSession {
    param([Parameter(Mandatory)]$Context)

    $commonSettings = $Context.CommonSettings
    $pageIdentityMatcher = New-DeviceListExportPageIdentityMatcher -Context $Context

    $Context.Services.Browser.OpenPageMatchingIdentity.Invoke(
        $commonSettings.DebuggerUrl,
        ([int]$commonSettings.Cdp.ConnectTimeoutSeconds),
        ([int]$commonSettings.Cdp.CommandTimeoutSeconds),
        $pageIdentityMatcher
    ) | Out-Null
}

function Set-DeviceListExportDownloadDirectory {
    param([Parameter(Mandatory)]$Context)

    $Context.Services.Browser.SetDownloadDirectory.Invoke($Context.JobSettings.TempDirectory)
}

function Initialize-DeviceListExportJob {
    param([Parameter(Mandatory)]$Context)

    Initialize-DeviceListExportOutputDirectories -Context $Context
    Open-DeviceListExportBrowserSession -Context $Context
    Set-DeviceListExportDownloadDirectory -Context $Context
}

function Invoke-DeviceListExportJob {
    param([Parameter(Mandatory)]$Context)

    Write-FoundationLog -Logger $Context.Logger -Message '実行内容: センサー / デバイス一覧CSVをエクスポートし、リネームします。'
    Write-FoundationLog -Logger $Context.Logger -Message "一時ダウンロード先: $($Context.JobSettings.TempDirectory)"
    Write-FoundationLog -Logger $Context.Logger -Message "最終保存先        : $($Context.JobSettings.DownloadDirectory)"

    Initialize-DeviceListExportJob -Context $Context
    $result = Invoke-DeviceListExportWorkflow -Context $Context
    Write-DeviceListExportResultSummary -Context $Context -Result $result
    Write-FoundationLog -Logger $Context.Logger -Message 'DeviceListExport の操作が完了しました。'
    return $result
}
