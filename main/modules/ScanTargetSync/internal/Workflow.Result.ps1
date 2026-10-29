$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

function Add-ScanTargetSyncScanLoopLimitFailure {
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)]$ScanResult,
        [Parameter(Mandatory)][int]$DeviceListTotalCount
    )

    if (-not $ScanResult.LoopReachedLimit) { return }

    Add-ScanTargetSyncFailureRow -State $State -FailureRow (New-ScanTargetSyncFailureRow -Endpoint "__SCAN_LOOP_LIMIT__" -DataId "" -User "" -Status "" -LastConnected "" -ScanStarted "" -ScanCompleted "" -Reason "最大走査ループ数 $($ScanResult.MaxScanLoops) に到達しました。未処理のチェック状態整合対象=$(@($Plan.SyncRows).Count - $ScanResult.ProcessedEndpointMap.Count)件 UI走査済み=$($ScanResult.SeenUiEndpointSet.Count)件 UI一覧件数=$($DeviceListTotalCount)件")
}

function Add-ScanTargetSyncUiBadRowFailures {
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)]$ScanResult
    )

    foreach ($badKey in @($ScanResult.UiBadRowMap.Keys | Sort-Object)) {
        Add-ScanTargetSyncFailureRow -State $State -FailureRow (New-ScanTargetSyncFailureRow -Endpoint "__UI_BAD_ROW__" -DataId "" -User "" -Status "" -LastConnected "" -ScanStarted "" -ScanCompleted "" -Reason "UI走査中に、endpoint または画面行識別子(data-id)が空の表示行を検出しました: $badKey")
    }
}

function Add-ScanTargetSyncUiEndpointConflictFailures {
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)]$ScanResult
    )

    foreach ($endpoint in @($ScanResult.UiEndpointConflictMap.Keys | Sort-Object)) {
        Add-ScanTargetSyncFailureRow -State $State -FailureRow (New-ScanTargetSyncFailureRow -Endpoint $endpoint -DataId "" -User "" -Status "" -LastConnected "" -ScanStarted "" -ScanCompleted "" -Reason "UI走査中に同一endpointが複数の画面行識別子(data-id)で検出されました。$($ScanResult.UiEndpointConflictMap[$endpoint])")
    }
}

function Add-ScanTargetSyncUiSeenCountMismatchFailure {
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)]$ScanResult,
        [Parameter(Mandatory)][int]$DeviceListTotalCount
    )

    if ($ScanResult.SeenUiEndpointSet.Count -eq $DeviceListTotalCount) { return }

    Add-ScanTargetSyncFailureRow -State $State -FailureRow (New-ScanTargetSyncFailureRow -Endpoint "__UI_SEEN_COUNT_MISMATCH__" -DataId "" -User "" -Status "" -LastConnected "" -ScanStarted "" -ScanCompleted "" -Reason "UI走査で確認できたendpoint件数とUI一覧件数が一致しません。確認済み=$($ScanResult.SeenUiEndpointSet.Count) UI一覧件数=$DeviceListTotalCount")
}

function Add-ScanTargetSyncCsvMissingInUiFailures {
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)]$SyncIndex,
        [Parameter(Mandatory)]$ScanResult
    )

    foreach ($endpoint in @($SyncIndex.SyncEndpointSet.Keys | Sort-Object)) {
        if (-not $ScanResult.SeenUiEndpointSet.ContainsKey($endpoint)) {
            $syncRow = $SyncIndex.SyncRowByEndpoint[$endpoint]
            Add-ScanTargetSyncFailureRow -State $State -FailureRow (New-ScanTargetSyncFailureRow -Endpoint $endpoint -DataId "" -User $syncRow.User -Status $syncRow.Status -LastConnected $syncRow.LastConnected -ScanStarted $syncRow.ScanStarted -ScanCompleted $syncRow.ScanCompleted -Reason "CSVにあるendpointがUI一覧の全件走査で見つかりません。目的=$(Get-CheckboxDesiredStateDisplay -DesiredState $syncRow.DesiredState)")
        }
    }
}

function Add-ScanTargetSyncUiExtraEndpointFailures {
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)]$SyncIndex,
        [Parameter(Mandatory)]$ScanResult
    )

    foreach ($endpoint in @($ScanResult.SeenUiEndpointSet.Keys | Sort-Object)) {
        if (-not $SyncIndex.SyncEndpointSet.ContainsKey($endpoint)) {
            Add-ScanTargetSyncFailureRow -State $State -FailureRow (New-ScanTargetSyncFailureRow -Endpoint $endpoint -DataId $ScanResult.SeenUiEndpointDataIdMap[$endpoint] -User "" -Status "" -LastConnected "" -ScanStarted "" -ScanCompleted "" -Reason "UI一覧に存在するendpointがCSVに存在しません。CSV/UI件数またはCSV内容を確認してください。")
        }
    }
}

function Add-ScanTargetSyncUnprocessedSyncFailures {
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)]$ScanResult
    )

    foreach ($syncRow in @($Plan.SyncRows)) {
        $endpoint = [string]$syncRow.Endpoint
        if (-not $ScanResult.ProcessedEndpointMap.ContainsKey($endpoint)) {
            Add-ScanTargetSyncFailureRow -State $State -FailureRow (New-ScanTargetSyncFailureRow -Endpoint $endpoint -DataId "" -User $syncRow.User -Status $syncRow.Status -LastConnected $syncRow.LastConnected -ScanStarted $syncRow.ScanStarted -ScanCompleted $syncRow.ScanCompleted -Reason "UI走査中にチェック状態整合を実行できませんでした。目的=$(Get-CheckboxDesiredStateDisplay -DesiredState $syncRow.DesiredState)")
        }
    }
}

function Add-ScanTargetSyncProcessedCountMismatchFailure {
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)]$ScanResult
    )

    if ($ScanResult.ProcessedEndpointMap.Count -eq @($Plan.SyncRows).Count) { return }

    Add-ScanTargetSyncFailureRow -State $State -FailureRow (New-ScanTargetSyncFailureRow -Endpoint "__PROCESSED_COUNT_MISMATCH__" -DataId "" -User "" -Status "" -LastConnected "" -ScanStarted "" -ScanCompleted "" -Reason "チェック状態整合の処理済みendpoint件数と整合対象件数が一致しません。処理済み=$($ScanResult.ProcessedEndpointMap.Count) 整合対象=$(@($Plan.SyncRows).Count)")
}

function Add-ScanTargetSyncUiScanValidationFailures {
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)]$SyncIndex,
        [Parameter(Mandatory)]$ScanResult,
        [Parameter(Mandatory)][int]$DeviceListTotalCount
    )

    Add-ScanTargetSyncScanLoopLimitFailure -State $State -Plan $Plan -ScanResult $ScanResult -DeviceListTotalCount $DeviceListTotalCount
    Add-ScanTargetSyncUiBadRowFailures -State $State -ScanResult $ScanResult
    Add-ScanTargetSyncUiEndpointConflictFailures -State $State -ScanResult $ScanResult
    Add-ScanTargetSyncUiSeenCountMismatchFailure -State $State -ScanResult $ScanResult -DeviceListTotalCount $DeviceListTotalCount
    Add-ScanTargetSyncCsvMissingInUiFailures -State $State -SyncIndex $SyncIndex -ScanResult $ScanResult
    Add-ScanTargetSyncUiExtraEndpointFailures -State $State -SyncIndex $SyncIndex -ScanResult $ScanResult
    Add-ScanTargetSyncUnprocessedSyncFailures -State $State -Plan $Plan -ScanResult $ScanResult
    Add-ScanTargetSyncProcessedCountMismatchFailure -State $State -Plan $Plan -ScanResult $ScanResult
}

function Get-ScanTargetSyncSuccessBreakdown {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$SuccessRows)

    return [pscustomobject]@{
        OnSuccessRows         = @($SuccessRows | Where-Object { $_.desiredChecked -eq $true })
        OffSuccessRows        = @($SuccessRows | Where-Object { $_.desiredChecked -eq $false })
        MisalignedSuccessRows = @($SuccessRows | Where-Object { $_.effectiveCheckedNow -ne $_.desiredChecked })
        ChangedRows           = @($SuccessRows | Where-Object { $_.changed -eq $true })
        AlreadyAlignedRows    = @($SuccessRows | Where-Object { $_.alreadyAligned -eq $true })
    }
}

function Add-ScanTargetSyncSuccessValidationFailures {
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)]$Breakdown
    )

    if (@($Breakdown.OnSuccessRows).Count -ne @($Plan.OnRows).Count) {
        Add-ScanTargetSyncFailureRow -State $State -FailureRow (New-ScanTargetSyncFailureRow -Endpoint "__ON_SUCCESS_COUNT_MISMATCH__" -DataId "" -User "" -Status "" -LastConnected "" -ScanStarted "" -ScanCompleted "" -Reason "ONのチェック状態整合成功件数がONに揃える件数と一致しません。ON成功=$(@($Breakdown.OnSuccessRows).Count) ON対象=$(@($Plan.OnRows).Count)")
    }
    if (@($Breakdown.OffSuccessRows).Count -ne @($Plan.OffRows).Count) {
        Add-ScanTargetSyncFailureRow -State $State -FailureRow (New-ScanTargetSyncFailureRow -Endpoint "__OFF_SUCCESS_COUNT_MISMATCH__" -DataId "" -User "" -Status "" -LastConnected "" -ScanStarted "" -ScanCompleted "" -Reason "OFFのチェック状態整合成功件数がOFFに揃える件数と一致しません。OFF成功=$(@($Breakdown.OffSuccessRows).Count) OFF対象=$(@($Plan.OffRows).Count)")
    }
    if (@($Breakdown.MisalignedSuccessRows).Count -gt 0) {
        Add-ScanTargetSyncFailureRow -State $State -FailureRow (New-ScanTargetSyncFailureRow -Endpoint "__SUCCESS_MISALIGNED__" -DataId "" -User "" -Status "" -LastConnected "" -ScanStarted "" -ScanCompleted "" -Reason "成功扱いの行で、整合後のチェック状態が目的状態と一致していません。件数=$(@($Breakdown.MisalignedSuccessRows).Count)")
    }
}

function Write-ScanTargetSyncProcessingSummary {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)]$ScanResult,
        [Parameter(Mandatory)]$Breakdown,
        [Parameter(Mandatory)][int]$DeviceListTotalCount
    )

    Write-FoundationSection -Logger $Context.Logger -Title "処理サマリ"
    Write-FoundationLog -Logger $Context.Logger -Message "CSV総行数: $(@($Plan.CsvRows).Count)件"
    Write-FoundationLog -Logger $Context.Logger -Message "UI一覧件数: $($DeviceListTotalCount)件"
    Write-FoundationLog -Logger $Context.Logger -Message "UI走査: $($ScanResult.SeenUiEndpointSet.Count)/$($DeviceListTotalCount)件確認"
    Write-FoundationLog -Logger $Context.Logger -Message "チェック状態整合対象: $(@($Plan.SyncRows).Count)件（ON $(@($Plan.OnRows).Count)件 / OFF $(@($Plan.OffRows).Count)件）"
    Write-FoundationLog -Logger $Context.Logger -Message "チェック状態整合成功: $(@($ScanResult.SuccessRows).Count)/$(@($Plan.SyncRows).Count)件（ON $(@($Breakdown.OnSuccessRows).Count)/$(@($Plan.OnRows).Count)件 / OFF $(@($Breakdown.OffSuccessRows).Count)/$(@($Plan.OffRows).Count)件）"
    Write-FoundationLog -Logger $Context.Logger -Message "  変更済み : $(@($Breakdown.ChangedRows).Count)件"
    Write-FoundationLog -Logger $Context.Logger -Message "  変更不要 : $(@($Breakdown.AlreadyAlignedRows).Count)件"
    Write-FoundationLog -Logger $Context.Logger -Message "チェック状態整合失敗: $(@($State.FailureRows).Count)件"
    Write-FoundationLog -Logger $Context.Logger -Message "CSVデータエラー: $(@($State.CsvErrorRowsForExport).Count)件"
    Write-FoundationLog -Logger $Context.Logger -Message "手動スキャンの開始クリック: 未実行"
}
