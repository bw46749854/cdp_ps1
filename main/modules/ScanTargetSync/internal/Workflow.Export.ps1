$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

function Export-ScanTargetSyncEndCsvFiles {
    param(
        [Parameter(Mandatory)]$Context,
        [AllowEmptyCollection()][object[]]$CsvErrorRows,
        [AllowEmptyCollection()][object[]]$FailureRows,
        [Parameter(Mandatory)]$FileSystemService
    )

    $s = $Context.JobSettings
    $errorExport = Export-ScanTargetSyncCsvErrorCsv `
        -ErrorRows $CsvErrorRows `
        -OutputDirectory $s.OutputDirectory `
        -ErrorCsvFileName $s.CsvErrorFileName `
        -FileSystemService $FileSystemService
    $failureExport = Export-ScanTargetSyncFailureCsv `
        -FailureRows $FailureRows `
        -OutputDirectory $s.OutputDirectory `
        -FailureCsvFileName $s.FailureCsvFileName `
        -FileSystemService $FileSystemService

    if ($errorExport.ErrorCsvCreated) {
        Write-FoundationLog -Logger $Context.Logger -Level Warning -Message "CSVデータエラーCSV: 出力あり（$($CsvErrorRows.Count)件）: $($errorExport.ErrorCsvPath)"
    }
    elseif ($errorExport.OldErrorCsvRemoved) {
        Write-FoundationLog -Logger $Context.Logger -Message "CSVデータエラーCSV: 旧ファイル削除済み（CSVデータエラー0件）: $($errorExport.ErrorCsvPath)"
    }
    else {
        Write-FoundationLog -Logger $Context.Logger -Message "CSVデータエラーCSV: 出力なし（CSVデータエラー0件）: $($errorExport.ErrorCsvPath)"
    }

    if ($failureExport.FailureCsvCreated) {
        Write-FoundationLog -Logger $Context.Logger -Level Warning -Message "チェック処理失敗CSV: 出力あり（$($FailureRows.Count)件）: $($failureExport.FailureCsvPath)"
    }
    elseif ($failureExport.OldFailureCsvRemoved) {
        Write-FoundationLog -Logger $Context.Logger -Message "チェック処理失敗CSV: 旧ファイル削除済み（チェック処理失敗0件）: $($failureExport.FailureCsvPath)"
    }
    else {
        Write-FoundationLog -Logger $Context.Logger -Message "チェック処理失敗CSV: 出力なし（チェック処理失敗0件）: $($failureExport.FailureCsvPath)"
    }

    return [pscustomobject]@{
        ErrorExport = $errorExport
        FailureExport = $failureExport
    }
}

function Complete-ScanTargetSyncEndCsvExport {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)]$FileSystemService
    )

    Export-ScanTargetSyncEndCsvFiles `
        -Context $Context `
        -CsvErrorRows @($State.CsvErrorRowsForExport) `
        -FailureRows @($State.FailureRows) `
        -FileSystemService $FileSystemService | Out-Null
    $State.EndCsvExportCompleted = $true
}
