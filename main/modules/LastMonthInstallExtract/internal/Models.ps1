$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

function New-LastMonthInstallExtractInstallationRow {
    param(
        [Parameter(Mandatory)][string]$AssetName,
        [AllowEmptyString()][string]$ProductName = '',
        [AllowEmptyString()][string]$Version = '',
        [AllowEmptyString()][string]$InstallDate = ''
    )

    return [pscustomobject]@{
        '端末名'   = $AssetName
        'アプリ名'           = $ProductName
        'バージョン'       = $Version
        '導入日'   = $InstallDate
    }
}

function New-LastMonthInstallExtractFailureRow {
    param(
        [AllowEmptyString()][string]$FileName = '',
        [AllowEmptyString()][string]$AssetName = '',
        [AllowEmptyString()][string]$LineNumber = '',
        [Parameter(Mandatory)][string]$Reason,
        [AllowEmptyString()][string]$Timestamp = ''
    )

    return [pscustomobject]@{
        FileName     = $FileName
        AssetName = $AssetName
        LineNumber   = $LineNumber
        Reason       = $Reason
        Timestamp    = $Timestamp
    }
}

function New-LastMonthInstallExtractWorkflowResult {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$InstallationRows,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$FailureRows,
        [int]$InputFileCount = 0,
        [int]$ProcessedFileCount = 0,
        [int]$SkippedFileCount = 0,
        [int]$ReadRowCount = 0,
        [int]$MatchedRowCount = 0
    )

    return [pscustomobject]@{
        InstallationRows   = @($InstallationRows)
        FailureRows        = @($FailureRows)
        InputFileCount     = $InputFileCount
        ProcessedFileCount = $ProcessedFileCount
        SkippedFileCount   = $SkippedFileCount
        ReadRowCount       = $ReadRowCount
        MatchedRowCount    = $MatchedRowCount
    }
}
