$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

function Initialize-InstalledAppExportOutputDirectories {
    param([Parameter(Mandatory)]$Context)

    $settings = $Context.JobSettings

    $Context.Services.FileSystem.InitializeOutputDirectory.Invoke($settings.TempDirectory, "一時ダウンロード") | Out-Null
    $Context.Services.FileSystem.InitializeOutputDirectory.Invoke($settings.DownloadDirectory, "最終保存") | Out-Null
    $Context.Services.FileSystem.ClearDirectory.Invoke($settings.TempDirectory, "一時ダウンロード")
}

function Open-InstalledAppExportBrowserSession {
    param([Parameter(Mandatory)]$Context)

    $commonSettings = $Context.CommonSettings

    $pageIdentityMatcher = New-InstalledAppExportPageIdentityMatcher -Context $Context

    $Context.Services.Browser.OpenPageMatchingIdentity.Invoke(
        $commonSettings.DebuggerUrl,
        ([int]$commonSettings.Cdp.ConnectTimeoutSeconds),
        ([int]$commonSettings.Cdp.CommandTimeoutSeconds),
        $pageIdentityMatcher
    ) | Out-Null
}

function Set-InstalledAppExportDownloadDirectory {
    param([Parameter(Mandatory)]$Context)

    $Context.Services.Browser.SetDownloadDirectory.Invoke($Context.JobSettings.TempDirectory)
}

function Assert-InstalledAppExportInitialPageContract {
    param([Parameter(Mandatory)]$Context)

    Register-InstalledAppExportDomAdapter -Context $Context
    Assert-InstalledAppExportPage | Out-Null
    Assert-InstalledAppExportList | Out-Null
}

function Get-InstalledAppExportInitialTotalCount {
    param([Parameter(Mandatory)]$Context)

    $totalCount = Get-InstalledAppExportListTotalCount

    if ($null -eq $totalCount) {
        throw "DOM契約違反: 一覧件数を取得できません。"
    }

    return [int]$totalCount
}

function Reset-InstalledAppExportInitialListPosition {
    param([Parameter(Mandatory)]$Context)

    Close-InstalledAppExportDetailPanelSafely -Context $Context
    Scroll-InstalledAppExportListToTop
    $Context.Services.Timing.SleepMilliseconds.Invoke(500)
}

function Initialize-InstalledAppExportJob {
    param([Parameter(Mandatory)]$Context)

    Initialize-InstalledAppExportOutputDirectories -Context $Context
    Open-InstalledAppExportBrowserSession -Context $Context
    Set-InstalledAppExportDownloadDirectory -Context $Context
    Assert-InstalledAppExportInitialPageContract -Context $Context

    $totalCount = Get-InstalledAppExportInitialTotalCount -Context $Context

    Reset-InstalledAppExportInitialListPosition -Context $Context

    return $totalCount
}

function Export-InstalledAppExportJobResults {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$WorkflowResult
    )

    $settings = $Context.JobSettings
    $failureCsvPath = Join-Path $settings.DownloadDirectory $settings.FailureCsvFileName
    $failureCsv = Export-InstalledAppExportFailureCsv `
        -FailureResults $WorkflowResult.FailureResults `
        -Path $failureCsvPath `
        -FileSystemService $Context.Services.FileSystem

    return [pscustomobject]@{
        FailureCsvPath = $failureCsvPath
        FailureCsv = $failureCsv
    }
}

function Write-InstalledAppExportWorkflowSummary {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$WorkflowResult,
        [Parameter(Mandatory)]$ExportResult
    )

    Write-FoundationSection -Logger $Context.Logger -Title "処理結果"
    Write-FoundationLog -Logger $Context.Logger -Message "処理済み: $($WorkflowResult.ScanResult.ProcessedCount) 件"
    Write-FoundationLog -Logger $Context.Logger -Message "成功    : $($WorkflowResult.SuccessResults.Count) 件"
    Write-FoundationLog -Logger $Context.Logger -Message "失敗    : $($WorkflowResult.FailureResults.Count) 件"

    if ($ExportResult.FailureCsv) {
        Write-FoundationLog -Logger $Context.Logger -Level Warning -Message "失敗一覧CSVを出力しました: $($ExportResult.FailureCsv.FullName)"
    }
    else {
        Write-FoundationLog -Logger $Context.Logger -Message "失敗一覧CSVはありません。既存ファイルがあれば削除済みです: $($ExportResult.FailureCsvPath)"
    }
}

function Assert-InstalledAppExportProcessedAllRows {
    param(
        [Parameter(Mandatory)]$WorkflowResult,
        [Parameter(Mandatory)][int]$TotalCount
    )

    if ($WorkflowResult.ScanResult.ProcessedCount -lt $TotalCount) {
        throw "DOM契約違反: 一覧件数 $TotalCount 件に対して、処理済みは $($WorkflowResult.ScanResult.ProcessedCount) 件です。"
    }
}

function Assert-InstalledAppExportHasNoFailures {
    param(
        [Parameter(Mandatory)]$WorkflowResult,
        [Parameter(Mandatory)]$ExportResult
    )

    if ($WorkflowResult.FailureResults.Count -gt 0) {
        throw "処理失敗が $($WorkflowResult.FailureResults.Count) 件あります。詳細は失敗一覧CSVを確認してください: $($ExportResult.FailureCsvPath)"
    }
}

function Complete-InstalledAppExportJob {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$WorkflowResult,
        [int]$TotalCount
    )

    $exportResult = Export-InstalledAppExportJobResults `
        -Context $Context `
        -WorkflowResult $WorkflowResult

    Write-InstalledAppExportWorkflowSummary `
        -Context $Context `
        -WorkflowResult $WorkflowResult `
        -ExportResult $exportResult

    Assert-InstalledAppExportProcessedAllRows `
        -WorkflowResult $WorkflowResult `
        -TotalCount $TotalCount

    Assert-InstalledAppExportHasNoFailures `
        -WorkflowResult $WorkflowResult `
        -ExportResult $exportResult
}

function Invoke-InstalledAppExportJob {
    param([Parameter(Mandatory)]$Context)

    $totalCount = Initialize-InstalledAppExportJob -Context $Context

    Write-FoundationLog -Logger $Context.Logger -Message "一覧件数: $totalCount"

    $workflowResult = Invoke-InstalledAppExportCsvWorkflow `
        -Context $Context `
        -TotalCount $totalCount

    Complete-InstalledAppExportJob `
        -Context $Context `
        -WorkflowResult $workflowResult `
        -TotalCount $totalCount

    Write-FoundationLog -Logger $Context.Logger -Message "一連の操作が完了しました。"
}
