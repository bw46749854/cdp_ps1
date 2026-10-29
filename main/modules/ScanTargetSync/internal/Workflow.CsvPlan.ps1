$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

function Write-ScanTargetSyncWorkflowStartLog {
    param([Parameter(Mandatory)]$Context)

    $s = $Context.JobSettings
    Write-FoundationLog -Logger $Context.Logger -Message "=== scan_target_sync 開始 ==="
    Write-FoundationLog -Logger $Context.Logger -Message "実行内容: ScanTargetSync入力CSVの判定結果に基づき、手動スキャン対象チェックボックスをON/OFFに整合します。"
    Write-FoundationLog -Logger $Context.Logger -Message "重要: 手動スキャンの開始はクリックしません。"
    Write-FoundationLog -Logger $Context.Logger -Message "入力CSV: $($s.InputCsvPath)"
    Write-FoundationLog -Logger $Context.Logger -Message "出力先 : $($s.OutputDirectory)"
    Write-FoundationLog -Logger $Context.Logger -Message "判定条件:"
    foreach($line in @(Get-ScanTargetSyncRuleDescription -DaysThreshold ([int]$s.DaysThreshold))){ Write-FoundationLog -Logger $Context.Logger -Message "  - $line" }
    Write-FoundationLog -Logger $Context.Logger -Message "基準日: 最終通信日時"
}

function Import-ScanTargetSyncCsvPlan {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$Timing
    )

    $s = $Context.JobSettings
    $csvRows = @(Import-ScanTargetSyncInputCsv -Path $s.InputCsvPath)
    Assert-ScanTargetSyncInputCsvContract -Rows $csvRows
    $timestampText = Get-ScanTargetSyncCallbackScriptBlock -Callbacks $Timing -Name 'TimestampText'
    $timestamp = & $timestampText

    $extraction = Get-ScanTargetSyncTargetExtraction -CsvRows $csvRows -DaysThreshold ([int]$s.DaysThreshold) -Timestamp $timestamp
    $csvErrorRows = @($extraction.CsvErrorRows)
    $duplicateEndpointRows = @(Get-ScanTargetSyncDuplicateEndpointErrors -CsvRows $csvRows -Timestamp $timestamp)
    if ($duplicateEndpointRows.Count -gt 0) { $csvErrorRows += $duplicateEndpointRows }

    return [pscustomobject]@{
        CsvRows      = @($csvRows)
        OnRows       = @($extraction.OnRows)
        OffRows      = @($extraction.OffRows)
        CsvErrorRows = @($csvErrorRows)
        SyncRows     = @()
    }
}

function Resolve-ScanTargetSyncSyncPlan {
    param([Parameter(Mandatory)]$Plan)

    $syncRows = @(Get-ScanTargetSyncSyncRows -OnRows @($Plan.OnRows) -OffRows @($Plan.OffRows))
    Assert-UniqueScanTargetSyncSyncRows -SyncRows $syncRows

    return [pscustomobject]@{
        CsvRows      = @($Plan.CsvRows)
        OnRows       = @($Plan.OnRows)
        OffRows      = @($Plan.OffRows)
        CsvErrorRows = @($Plan.CsvErrorRows)
        SyncRows     = @($syncRows)
    }
}

function Assert-ScanTargetSyncCsvPlanOrStop {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)]$FileSystemService
    )

    $State.CsvErrorRowsForExport = @($Plan.CsvErrorRows)

    if ($State.CsvErrorRowsForExport.Count -gt 0) {
        Write-FoundationLog -Logger $Context.Logger -Level Warning -Message "CSVデータエラーが $($State.CsvErrorRowsForExport.Count) 件あります。CSVデータエラーCSVを出力し、CDP接続前に停止します。"
        Complete-ScanTargetSyncEndCsvExport -Context $Context -State $State -FileSystemService $FileSystemService
        throw "CSVデータエラーが $($State.CsvErrorRowsForExport.Count) 件あります。判定不能または一意でないCSV行があるため、誤操作防止のためCDP操作を開始しません。CSVデータエラーCSVを確認してください。"
    }

    if ((@($Plan.OnRows).Count + @($Plan.OffRows).Count) -ne @($Plan.CsvRows).Count) {
        Add-ScanTargetSyncFailureRow -State $State -FailureRow (New-ScanTargetSyncFailureRow -Endpoint "__CSV_CLASSIFICATION_COUNT__" -DataId "" -User "" -Status "" -LastConnected "" -ScanStarted "" -ScanCompleted "" -Reason "CSV分類件数がCSV総行数と一致しません。ON件数=$(@($Plan.OnRows).Count) OFF件数=$(@($Plan.OffRows).Count) CSV総行数=$(@($Plan.CsvRows).Count)")
        Complete-ScanTargetSyncEndCsvExport -Context $Context -State $State -FileSystemService $FileSystemService
        throw "CSV分類件数がCSV総行数と一致しません。誤操作防止のためCDP操作を開始しません。"
    }

    if (@($Plan.SyncRows).Count -ne @($Plan.CsvRows).Count) {
        Add-ScanTargetSyncFailureRow -State $State -FailureRow (New-ScanTargetSyncFailureRow -Endpoint "__SYNC_COUNT__" -DataId "" -User "" -Status "" -LastConnected "" -ScanStarted "" -ScanCompleted "" -Reason "チェック状態整合対象件数がCSV総行数と一致しません。整合対象=$(@($Plan.SyncRows).Count) CSV総行数=$(@($Plan.CsvRows).Count)")
        Complete-ScanTargetSyncEndCsvExport -Context $Context -State $State -FileSystemService $FileSystemService
        throw "チェック状態整合対象件数がCSV総行数と一致しません。誤操作防止のためCDP操作を開始しません。"
    }
}

function Write-ScanTargetSyncCsvSummary {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$Plan
    )

    Write-FoundationLog -Logger $Context.Logger -Message "=== CSV判定結果 ==="
    Write-FoundationLog -Logger $Context.Logger -Message "CSV総行数: $(@($Plan.CsvRows).Count)件"
    Write-FoundationLog -Logger $Context.Logger -Message "CSVデータエラー: $(@($Plan.CsvErrorRows).Count)件"
    Write-FoundationLog -Logger $Context.Logger -Message "ONに揃える件数: $(@($Plan.OnRows).Count)件"
    Write-FoundationLog -Logger $Context.Logger -Message "OFFに揃える件数（手動スキャン対象外）: $(@($Plan.OffRows).Count)件"
    Write-FoundationLog -Logger $Context.Logger -Message "ON/OFF判定済み: $(@($Plan.SyncRows).Count)/$(@($Plan.CsvRows).Count)件"
}

function New-ScanTargetSyncSyncIndex {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$SyncRows)

    $syncRowByEndpoint = @{}
    $syncEndpointSet = @{}
    foreach ($syncRow in @($SyncRows)) {
        $endpoint = [string]$syncRow.Endpoint
        $syncRowByEndpoint[$endpoint] = $syncRow
        $syncEndpointSet[$endpoint] = $true
    }

    return [pscustomobject]@{
        SyncRowByEndpoint = $syncRowByEndpoint
        SyncEndpointSet   = $syncEndpointSet
    }
}
