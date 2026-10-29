$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

function Export-ScanTargetSyncFatalResultIfNeeded {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)][string]$Reason,
        [Parameter(Mandatory)]$FileSystemService
    )

    if ($State.EndCsvExportCompleted) { return }
    try {
        Add-ScanTargetSyncFailureRow -State $State -FailureRow (New-ScanTargetSyncFailureRow -Endpoint "__SCRIPT_FATAL__" -DataId "" -User "" -Status "" -LastConnected "" -ScanStarted "" -ScanCompleted "" -Reason "スクリプト実行中の致命的エラー: $Reason")
        Complete-ScanTargetSyncEndCsvExport -Context $Context -State $State -FileSystemService $FileSystemService
    }
    catch {
        Write-FoundationLog -Logger $Context.Logger -Level Warning -Message "異常終了時のCSVデータエラーCSV / チェック処理失敗CSV出力に失敗しました: $($_.Exception.Message)"
    }
}
