$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

function Open-ScanTargetSyncPageAndValidate {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)]$Plan,
        [AllowNull()]$Dependencies = $null
    )

    $resolvedDependencies = Resolve-ScanTargetSyncWorkflowDependencies -Context $Context -Dependencies $Dependencies
    Assert-ScanTargetSyncPageDependencies -Dependencies $resolvedDependencies

    $openPageMatchingIdentity = Get-ScanTargetSyncCallbackScriptBlock -Callbacks $resolvedDependencies.Browser -Name 'OpenPageMatchingIdentity'
    $registerAdapter = Get-ScanTargetSyncCallbackScriptBlock -Callbacks $resolvedDependencies.Dom -Name 'RegisterAdapter'
    $assertPage = Get-ScanTargetSyncCallbackScriptBlock -Callbacks $resolvedDependencies.Dom -Name 'AssertPage'
    $assertDeviceList = Get-ScanTargetSyncCallbackScriptBlock -Callbacks $resolvedDependencies.Dom -Name 'AssertDeviceList'
    $prepareOperationScope = Get-ScanTargetSyncCallbackScriptBlock -Callbacks $resolvedDependencies.Dom -Name 'PrepareOperationScope'
    $scrollToTop = Get-ScanTargetSyncCallbackScriptBlock -Callbacks $resolvedDependencies.Dom -Name 'ScrollToTop'

    $pageIdentityMatcher = New-ScanTargetSyncPageIdentityMatcher -Context $Context -Dependencies $resolvedDependencies

    & $openPageMatchingIdentity `
        $Context.CommonSettings.DebuggerUrl `
        ([int]$Context.CommonSettings.Cdp.ConnectTimeoutSeconds) `
        ([int]$Context.CommonSettings.Cdp.CommandTimeoutSeconds) `
        $pageIdentityMatcher | Out-Null
    & $registerAdapter
    & $assertPage | Out-Null
    $listContract = & $assertDeviceList
    $operationContext = & $prepareOperationScope
    if (-not $operationContext -or $operationContext.ok -ne $true) {
        throw "チェック操作スコープ確認に失敗しました。詳細=$($operationContext | ConvertTo-Json -Compress -Depth 30)"
    }

    $deviceListTotalCount = Get-ScanTargetSyncDeviceTotalCount -ListContract $listContract
    if ($deviceListTotalCount -lt 1) {
        Add-ScanTargetSyncFailureRow -State $State -FailureRow (New-ScanTargetSyncFailureRow -Endpoint "__UI_TOTAL_COUNT__" -DataId "" -User "" -Status "" -LastConnected "" -ScanStarted "" -ScanCompleted "" -Reason "UI一覧件数が1件未満です。UI一覧件数=$deviceListTotalCount")
        throw "UI一覧件数が1件未満です。誤操作防止のため停止します。"
    }
    if (@($Plan.CsvRows).Count -ne $deviceListTotalCount) {
        Add-ScanTargetSyncFailureRow -State $State -FailureRow (New-ScanTargetSyncFailureRow -Endpoint "__CSV_UI_COUNT_MISMATCH__" -DataId "" -User "" -Status "" -LastConnected "" -ScanStarted "" -ScanCompleted "" -Reason "CSV総行数とUI一覧件数が一致しません。CSV総行数=$(@($Plan.CsvRows).Count) UI一覧件数=$deviceListTotalCount")
        throw "CSV総行数とUI一覧件数が一致しません。CSV総行数=$(@($Plan.CsvRows).Count) UI一覧件数=$deviceListTotalCount。誤操作防止のためチェック操作を開始しません。"
    }
    if (@($Plan.SyncRows).Count -ne $deviceListTotalCount) {
        Add-ScanTargetSyncFailureRow -State $State -FailureRow (New-ScanTargetSyncFailureRow -Endpoint "__SYNC_UI_COUNT_MISMATCH__" -DataId "" -User "" -Status "" -LastConnected "" -ScanStarted "" -ScanCompleted "" -Reason "チェック状態整合対象件数とUI一覧件数が一致しません。整合対象=$(@($Plan.SyncRows).Count) UI一覧件数=$deviceListTotalCount")
        throw "チェック状態整合対象件数とUI一覧件数が一致しません。整合対象=$(@($Plan.SyncRows).Count) UI一覧件数=$deviceListTotalCount。誤操作防止のためチェック操作を開始しません。"
    }

    Write-FoundationLog -Logger $Context.Logger -Message "デバイス一覧画面確認: OK"
    Write-FoundationLog -Logger $Context.Logger -Message "チェック操作スコープ確認: OK"
    Write-FoundationLog -Logger $Context.Logger -Message "CSV/UI件数照合: OK（CSV $(@($Plan.CsvRows).Count)件 / UI $($deviceListTotalCount)件）"
    Write-FoundationLog -Logger $Context.Logger -Message "照合方法: 検索欄は使わず、UI一覧を上から全件走査"
    Write-FoundationLog -Logger $Context.Logger -Message "=== チェック状態整合結果 ==="
    & $scrollToTop

    return $deviceListTotalCount
}

function Confirm-ScanTargetSyncPostSelectionContract {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)]$Plan,
        [AllowNull()]$Dependencies = $null
    )

    $resolvedDependencies = Resolve-ScanTargetSyncWorkflowDependencies -Context $Context -Dependencies $Dependencies
    Assert-ScanTargetSyncPostSelectionDependencies -Dependencies $resolvedDependencies

    $assertPostSelectionContract = Get-ScanTargetSyncCallbackScriptBlock -Callbacks $resolvedDependencies.Dom -Name 'AssertPostSelectionContract'

    if (@($Plan.OnRows).Count -gt 0) {
        try {
            & $assertPostSelectionContract | Out-Null
            Write-FoundationLog -Logger $Context.Logger -Message "手動スキャンの開始メニュー: 有効化確認OK"
            Write-FoundationLog -Logger $Context.Logger -Message "手動スキャンの開始クリック: 未実行"
        }
        catch {
            Add-ScanTargetSyncFailureRow -State $State -FailureRow (New-ScanTargetSyncFailureRow -Endpoint "__POST_SELECTION_CONTRACT__" -DataId "" -User "" -Status "" -LastConnected "" -ScanStarted "" -ScanCompleted "" -Reason "手動スキャンの開始メニュー有効化確認に失敗しました。詳細=$($_.Exception.Message)")
        }
    }
    else {
        Write-FoundationLog -Logger $Context.Logger -Message "ONに揃える対象が0件のため、手動スキャンの開始メニュー有効化確認は行いません。"
        Write-FoundationLog -Logger $Context.Logger -Message "手動スキャンの開始クリック: 未実行"
    }
}
