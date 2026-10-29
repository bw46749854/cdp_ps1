$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

function New-ScanTargetSyncUiScanState {
    param(
        [Parameter(Mandatory)][int]$MaxScanLoops
    )

    return [pscustomobject]@{
        ProcessedEndpointMap     = @{}
        SeenUiEndpointSet        = @{}
        SeenUiEndpointDataIdMap  = @{}
        UiEndpointConflictMap    = @{}
        UiBadRowMap              = @{}
        SuccessRows              = @()
        SameScrollCount          = 0
        LoopReachedLimit         = $true
        MaxScanLoops             = $MaxScanLoops
    }
}

function Update-ScanTargetSyncUiScanStateFromVisibleRows {
    param(
        [Parameter(Mandatory)]$ScanState,
        [Parameter(Mandatory)]$SyncIndex,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$VisibleRows
    )

    $visibleSyncEndpoints = @{}

    foreach ($rowInfo in @($VisibleRows)) {
        $endpoint = [string]$rowInfo.endpoint
        $dataId = [string]$rowInfo.dataId

        if ([string]::IsNullOrWhiteSpace($endpoint) -or [string]::IsNullOrWhiteSpace($dataId)) {
            $badKey = "画面行識別子(data-id)=$dataId endpoint=$endpoint"
            if (-not $ScanState.UiBadRowMap.ContainsKey($badKey)) {
                $ScanState.UiBadRowMap[$badKey] = $true
            }
            continue
        }

        $ScanState.SeenUiEndpointSet[$endpoint] = $true

        if (-not $ScanState.SeenUiEndpointDataIdMap.ContainsKey($endpoint)) {
            $ScanState.SeenUiEndpointDataIdMap[$endpoint] = $dataId
        }
        elseif ($ScanState.SeenUiEndpointDataIdMap[$endpoint] -ne $dataId) {
            $ScanState.UiEndpointConflictMap[$endpoint] = "firstDataId=$($ScanState.SeenUiEndpointDataIdMap[$endpoint]) anotherDataId=$dataId"
        }

        if ($SyncIndex.SyncEndpointSet.ContainsKey($endpoint) -and -not $ScanState.ProcessedEndpointMap.ContainsKey($endpoint)) {
            $visibleSyncEndpoints[$endpoint] = $true
        }
    }

    return $visibleSyncEndpoints
}
