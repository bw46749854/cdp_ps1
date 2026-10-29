$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

function Initialize-ScanTargetSyncWorkflow {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$Dependencies
    )

    Assert-ScanTargetSyncWorkflowInitializationDependencies -Dependencies $Dependencies

    $settings = $Context.JobSettings
    $initializeOutputDirectory = Get-ScanTargetSyncCallbackScriptBlock -Callbacks $Dependencies.FileSystem -Name 'InitializeOutputDirectory'

    & $initializeOutputDirectory $settings.OutputDirectory "出力" | Out-Null
    Write-ScanTargetSyncWorkflowStartLog -Context $Context
}

function New-ScanTargetSyncValidatedPlan {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)]$Dependencies
    )

    $plan = Import-ScanTargetSyncCsvPlan -Context $Context -Timing $Dependencies.Timing
    $State.CsvErrorRowsForExport = @($plan.CsvErrorRows)

    if ($State.CsvErrorRowsForExport.Count -eq 0) {
        $plan = Resolve-ScanTargetSyncSyncPlan -Plan $plan
    }

    Assert-ScanTargetSyncCsvPlanOrStop `
        -Context $Context `
        -State $State `
        -Plan $plan `
        -FileSystemService $Dependencies.FileSystem
    Write-ScanTargetSyncCsvSummary -Context $Context -Plan $plan

    return $plan
}

function Test-ScanTargetSyncNoSyncTarget {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)]$Dependencies
    )

    if (@($Plan.SyncRows).Count -ne 0) {
        return $false
    }

    Complete-ScanTargetSyncEndCsvExport `
        -Context $Context `
        -State $State `
        -FileSystemService $Dependencies.FileSystem
    Write-FoundationLog -Logger $Context.Logger -Message "チェック状態整合対象が0件のため、CDP操作は実行しません。"

    return $true
}

function Invoke-ScanTargetSyncScanAndSync {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)]$Dependencies
    )

    $syncIndex = New-ScanTargetSyncSyncIndex -SyncRows @($Plan.SyncRows)
    $deviceListTotalCount = Open-ScanTargetSyncPageAndValidate `
        -Context $Context `
        -State $State `
        -Plan $Plan `
        -Dependencies $Dependencies
    $scanResult = Invoke-ScanTargetSyncUiScan `
        -Context $Context `
        -State $State `
        -Plan $Plan `
        -SyncIndex $syncIndex `
        -DeviceListTotalCount $deviceListTotalCount `
        -Dependencies $Dependencies

    Add-ScanTargetSyncUiScanValidationFailures `
        -State $State `
        -Plan $Plan `
        -SyncIndex $syncIndex `
        -ScanResult $scanResult `
        -DeviceListTotalCount $deviceListTotalCount

    $breakdown = Get-ScanTargetSyncSuccessBreakdown -SuccessRows @($scanResult.SuccessRows)
    Add-ScanTargetSyncSuccessValidationFailures -State $State -Plan $Plan -Breakdown $breakdown

    return [pscustomobject]@{
        SyncIndex = $syncIndex
        DeviceListTotalCount = $deviceListTotalCount
        ScanResult = $scanResult
        Breakdown = $breakdown
    }
}

function Complete-ScanTargetSyncWorkflow {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)]$ScanAndSyncResult,
        [Parameter(Mandatory)]$Dependencies
    )

    Confirm-ScanTargetSyncPostSelectionContract `
        -Context $Context `
        -State $State `
        -Plan $Plan `
        -Dependencies $Dependencies
    Write-ScanTargetSyncProcessingSummary `
        -Context $Context `
        -State $State `
        -Plan $Plan `
        -ScanResult $ScanAndSyncResult.ScanResult `
        -Breakdown $ScanAndSyncResult.Breakdown `
        -DeviceListTotalCount $ScanAndSyncResult.DeviceListTotalCount
    Complete-ScanTargetSyncEndCsvExport `
        -Context $Context `
        -State $State `
        -FileSystemService $Dependencies.FileSystem
}

function Assert-ScanTargetSyncWorkflowSucceeded {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$State
    )

    if (@($State.FailureRows).Count -gt 0 -or @($State.CsvErrorRowsForExport).Count -gt 0) {
        throw "処理は完了しましたが異常があります。CSVデータエラー=$(@($State.CsvErrorRowsForExport).Count)件 チェック状態整合失敗=$(@($State.FailureRows).Count)件。出力されたCSVデータエラーCSV / チェック処理失敗CSVを確認してください。"
    }

    Write-FoundationLog -Logger $Context.Logger -Message "結果: 正常終了"
    Write-FoundationLog -Logger $Context.Logger -Message "処理が正常に完了しました。CSV判定に基づくチェック状態整合が完了しました。手動スキャンの開始はクリックしていません。"
}
