$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

function Invoke-ScanTargetSyncSyncForEndpoint {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][pscustomobject]$SyncRow,
        [AllowNull()]$Dependencies = $null
    )

    $resolvedDependencies = Resolve-ScanTargetSyncWorkflowDependencies -Context $Context -Dependencies $Dependencies
    Assert-ScanTargetSyncEndpointActionDependencies -Dependencies $resolvedDependencies

    $setDesiredState = Get-ScanTargetSyncCallbackScriptBlock -Callbacks $resolvedDependencies.EndpointAction -Name 'SetDesiredState'
    $testFoundationFatalError = Get-ScanTargetSyncCallbackScriptBlock -Callbacks $resolvedDependencies.EndpointAction -Name 'TestFoundationFatalError'

    $endpoint = [string]$SyncRow.Endpoint
    $desiredChecked = [bool]$SyncRow.DesiredChecked
    $desiredDisplay = Get-CheckboxDesiredStateDisplay -DesiredState $SyncRow.DesiredState

    try {
        $result = & $setDesiredState $endpoint $desiredChecked
        if ($result -and $result.ok -eq $true) {
            $changeDisplay = Get-CheckboxChangeResultDisplay -Result $result
            Write-FoundationLog -Logger $Context.Logger -Message "整合OK: $endpoint / 目的=$desiredDisplay / 結果=$changeDisplay / User=$($SyncRow.User) / Reason=$($SyncRow.Reason)"
            return [pscustomobject]@{
                Ok = $true
                Fatal = $false
                Result = $result
                FailureRow = $null
            }
        }

        $detailsJson = $result | ConvertTo-Json -Compress -Depth 30
        $reason = if ($result -and $result.reason) {
            "チェック状態整合に失敗しました。目的=$desiredDisplay / DOM理由=$($result.reason) / 詳細=$detailsJson"
        }
        else {
            "チェック状態整合に失敗しました。目的=$desiredDisplay / 詳細=$detailsJson"
        }

        Write-FoundationLog -Logger $Context.Logger -Level Warning -Message "整合NG: $endpoint / 目的=$desiredDisplay / Reason=$reason"
        $failureDataId = ""
        if ($result -and $result.dataId) { $failureDataId = [string]$result.dataId }

        return [pscustomobject]@{
            Ok = $false
            Fatal = $false
            Result = $result
            FailureRow = (New-ScanTargetSyncFailureRow -Endpoint $endpoint -DataId $failureDataId -User $SyncRow.User -Status $SyncRow.Status -LastConnected $SyncRow.LastConnected -ScanStarted $SyncRow.ScanStarted -ScanCompleted $SyncRow.ScanCompleted -Reason $reason)
        }
    }
    catch {
        $reason = $_.Exception.Message
        Write-FoundationLog -Logger $Context.Logger -Level Warning -Message "整合NG: $endpoint / 目的=$desiredDisplay / 例外=$reason"
        $failureRow = New-ScanTargetSyncFailureRow -Endpoint $endpoint -DataId "" -User $SyncRow.User -Status $SyncRow.Status -LastConnected $SyncRow.LastConnected -ScanStarted $SyncRow.ScanStarted -ScanCompleted $SyncRow.ScanCompleted -Reason "チェック状態整合中に例外が発生しました。目的=$desiredDisplay / 詳細=$reason"
        return [pscustomobject]@{
            Ok = $false
            Fatal = (& $testFoundationFatalError $reason)
            Result = $null
            FailureRow = $failureRow
        }
    }
}

function Invoke-ScanTargetSyncVisibleEndpointSyncBatch {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$WorkflowState,
        [Parameter(Mandatory)]$ScanState,
        [Parameter(Mandatory)]$SyncIndex,
        [Parameter(Mandatory)]$VisibleSyncEndpoints,
        [AllowNull()]$Dependencies = $null
    )

    foreach ($endpoint in @($VisibleSyncEndpoints.Keys | Sort-Object)) {
        if ($ScanState.ProcessedEndpointMap.ContainsKey($endpoint)) {
            continue
        }

        $syncRow = $SyncIndex.SyncRowByEndpoint[$endpoint]
        $syncResult = Invoke-ScanTargetSyncSyncForEndpoint -Context $Context -SyncRow $syncRow -Dependencies $Dependencies
        $ScanState.ProcessedEndpointMap[$endpoint] = $true

        if ($syncResult.Ok -eq $true) {
            $successRows = @($ScanState.SuccessRows)
            $successRows += $syncResult.Result
            $ScanState.SuccessRows = @($successRows)
            continue
        }

        Add-ScanTargetSyncFailureRow -State $WorkflowState -FailureRow $syncResult.FailureRow

        if ($syncResult.Fatal -eq $true) {
            throw "CDP接続継続不能のため処理を停止します。Endpoint=$endpoint Reason=$($syncResult.FailureRow.Reason)"
        }
    }
}
