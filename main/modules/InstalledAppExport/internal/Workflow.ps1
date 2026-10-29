$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

function New-InstalledAppExportRowProcessor {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$SuccessResults,
        [Parameter(Mandatory)]$FailureResults,
        [Parameter(Mandatory)]$RowAction,
        [Parameter(Mandatory)]$Logger
    )

    # RowProcessor は dependency object 上の RowAction / Logger port だけを使う。
    # 個別 callback 注入は正規経路を曖昧にするため廃止する。
    $exportForRow = Get-InstalledAppExportCallbackScriptBlock -Callbacks $RowAction -Name 'ExportForRow'
    $newFailure = Get-InstalledAppExportCallbackScriptBlock -Callbacks $RowAction -Name 'NewFailure'
    $writeWarning = Get-InstalledAppExportCallbackScriptBlock -Callbacks $Logger -Name 'WriteWarning'

    return {
        param($rowInfo)
        $dataId = [string]$rowInfo.dataId
        $assetName = [string]$rowInfo.assetName
        try {
            $result = & $exportForRow $Context $dataId $assetName
            [void]$SuccessResults.Add($result)
        }
        catch {
            $message = $_.Exception.Message
            & $writeWarning "処理失敗: $assetName ($dataId) / $message"
            [void]$FailureResults.Add((& $newFailure $dataId $assetName $message))
        }
    }.GetNewClosure()
}

function New-InstalledAppExportListOperations {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$SuccessResults,
        [Parameter(Mandatory)]$FailureResults,
        [AllowNull()]$Dependencies = $null
    )

    # Workflow は dependency object だけを受け取り、list traversal を組み立てる。
    # private 関数の bridge と fallback は Dependencies.ps1 に閉じ込める。
    $resolvedDependencies = Resolve-InstalledAppExportWorkflowDependencies -Context $Context -Dependencies $Dependencies

    $processor = New-InstalledAppExportRowProcessor `
        -Context $Context `
        -SuccessResults $SuccessResults `
        -FailureResults $FailureResults `
        -RowAction $resolvedDependencies.RowAction `
        -Logger $resolvedDependencies.Logger

    return [pscustomobject]@{
        Name = 'InstalledAppExportListOperations'
        GetVisibleRows = Get-InstalledAppExportCallbackScriptBlock -Callbacks $resolvedDependencies.ListTraversal -Name 'GetVisibleRows'
        GetRowKey = Get-InstalledAppExportCallbackScriptBlock -Callbacks $resolvedDependencies.ListTraversal -Name 'GetRowKey'
        ProcessRow = $processor
        ScrollDown = Get-InstalledAppExportCallbackScriptBlock -Callbacks $resolvedDependencies.ListTraversal -Name 'ScrollDown'
    }
}

function Invoke-InstalledAppExportCsvWorkflow {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][int]$TotalCount,
        [AllowNull()]$Dependencies = $null
    )
    $settings = $Context.JobSettings
    $resolvedDependencies = Resolve-InstalledAppExportWorkflowDependencies -Context $Context -Dependencies $Dependencies
    $successResults = New-Object System.Collections.ArrayList
    $failureResults = New-Object System.Collections.ArrayList
    $operations = New-InstalledAppExportListOperations `
        -Context $Context `
        -SuccessResults $successResults `
        -FailureResults $failureResults `
        -Dependencies $resolvedDependencies

    $invokeScrollableList = Get-InstalledAppExportCallbackScriptBlock -Callbacks $resolvedDependencies.Workflow -Name 'InvokeScrollableList'
    $scanResult = & $invokeScrollableList `
        $TotalCount `
        $operations `
        $Context.Logger `
        ([int]$settings.MaxScanLoops) `
        ([int]$settings.SameScrollLimit) `
        '端末行を取得できませんでした。'

    return [pscustomobject]@{
        ScanResult = $scanResult
        SuccessResults = @($successResults)
        FailureResults = @($failureResults)
    }
}
