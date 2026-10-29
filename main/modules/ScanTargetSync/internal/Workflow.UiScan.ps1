$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

function Test-ScanTargetSyncUiScanCompleted {
    param(
        [Parameter(Mandatory)]$ScanState,
        [Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)][int]$DeviceListTotalCount
    )

    if ($ScanState.SeenUiEndpointSet.Count -lt $DeviceListTotalCount) {
        return $false
    }

    if ($ScanState.ProcessedEndpointMap.Count -lt @($Plan.SyncRows).Count) {
        return $false
    }

    return $true
}

function Move-ScanTargetSyncUiScanCursor {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$ScanState,
        [Parameter(Mandatory)][int]$SameScrollLimit,
        [AllowNull()]$Dependencies = $null
    )

    $resolvedDependencies = Resolve-ScanTargetSyncWorkflowDependencies -Context $Context -Dependencies $Dependencies
    Assert-ScanTargetSyncUiScanCursorDependencies -Dependencies $resolvedDependencies

    $scrollDown = Get-ScanTargetSyncCallbackScriptBlock -Callbacks $resolvedDependencies.Dom -Name 'ScrollDown'
    $scrollResult = & $scrollDown

    if ($scrollResult.changed -eq $true) {
        $ScanState.SameScrollCount = 0
    }
    else {
        $ScanState.SameScrollCount++
    }

    if ($ScanState.SameScrollCount -ge $SameScrollLimit) {
        return $true
    }

    return $false
}

function Invoke-ScanTargetSyncUiScan {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)]$SyncIndex,
        [Parameter(Mandatory)][int]$DeviceListTotalCount,
        [AllowNull()]$Dependencies = $null
    )

    $resolvedDependencies = Resolve-ScanTargetSyncWorkflowDependencies -Context $Context -Dependencies $Dependencies
    Assert-ScanTargetSyncUiScanDependencies -Dependencies $resolvedDependencies

    $getVisibleRows = Get-ScanTargetSyncCallbackScriptBlock -Callbacks $resolvedDependencies.Dom -Name 'GetVisibleRows'

    $s = $Context.JobSettings
    $scanState = New-ScanTargetSyncUiScanState -MaxScanLoops ([int]$s.MaxScanLoops)
    for ($loop = 0; $loop -lt $scanState.MaxScanLoops; $loop++) {
        $visibleRows = @(& $getVisibleRows)
        $visibleSyncEndpoints = Update-ScanTargetSyncUiScanStateFromVisibleRows `
            -ScanState $scanState `
            -SyncIndex $SyncIndex `
            -VisibleRows $visibleRows
        Invoke-ScanTargetSyncVisibleEndpointSyncBatch `
            -Context $Context `
            -WorkflowState $State `
            -ScanState $scanState `
            -SyncIndex $SyncIndex `
            -VisibleSyncEndpoints $visibleSyncEndpoints `
            -Dependencies $resolvedDependencies
        if (Test-ScanTargetSyncUiScanCompleted -ScanState $scanState -Plan $Plan -DeviceListTotalCount $DeviceListTotalCount) {
            $scanState.LoopReachedLimit = $false
            Write-FoundationLog -Logger $Context.Logger -Message "UI走査完了: UI $($scanState.SeenUiEndpointSet.Count)/$($DeviceListTotalCount)件確認、チェック状態整合 $($scanState.ProcessedEndpointMap.Count)/$(@($Plan.SyncRows).Count)件処理"
            break
        }
        if (Move-ScanTargetSyncUiScanCursor -Context $Context -ScanState $scanState -SameScrollLimit ([int]$s.SameScrollLimit) -Dependencies $resolvedDependencies) {
            $scanState.LoopReachedLimit = $false
            Write-FoundationLog -Logger $Context.Logger -Message "一覧終端を検出しました。UI走査を終了します。"
            break
        }
    }
    return $scanState
}
