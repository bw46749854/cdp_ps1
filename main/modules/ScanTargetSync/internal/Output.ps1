$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

function New-ScanTargetSyncFailureRow {
    param(
        [string]$Endpoint,
        [string]$DataId,
        [string]$User,
        [string]$Status,
        [string]$LastConnected,
        [string]$ScanStarted,
        [string]$ScanCompleted,
        [string]$Reason,
        [AllowEmptyString()][string]$Timestamp = ''
    )

    [pscustomobject]@{
        Endpoint      = $Endpoint
        DataId        = $DataId
        User          = $User
        Status        = $Status
        LastConnected = $LastConnected
        ScanStarted   = $ScanStarted
        ScanCompleted = $ScanCompleted
        Reason        = $Reason
        Timestamp     = $Timestamp
    }
}

function Export-ScanTargetSyncCsvErrorCsv {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$ErrorRows,

        [Parameter(Mandatory)]
        [string]$OutputDirectory,

        [Parameter(Mandatory)]
        [string]$ErrorCsvFileName,

        [Parameter(Mandatory)]
        $FileSystemService
    )

    $resolvedOutputDirectory = @($FileSystemService.InitializeOutputDirectory.Invoke($OutputDirectory, "出力"))[0]

    $path = Join-Path $OutputDirectory $ErrorCsvFileName

    if (-not (@($FileSystemService.TestPathUnderDirectory.Invoke($path, $resolvedOutputDirectory))[0])) {
        throw "CSVデータエラーCSVの出力先が許可ディレクトリ配下ではありません: $path"
    }

    $items = @($ErrorRows)

    if ($items.Count -eq 0) {
        $removed = @($FileSystemService.RemoveFileIfExists.Invoke($path, $resolvedOutputDirectory))[0]

        return [pscustomobject]@{
            ErrorCsvPath       = $path
            ErrorCsvCreated    = $false
            OldErrorCsvRemoved = $removed
        }
    }

    $items |
        Select-Object Endpoint, User, Status, LastConnected, ScanStarted, ScanCompleted, ElapsedDays, Reason, Timestamp |
        Export-Csv -LiteralPath $path -NoTypeInformation -Encoding UTF8

    return [pscustomobject]@{
        ErrorCsvPath       = $path
        ErrorCsvCreated    = $true
        OldErrorCsvRemoved = $false
    }
}

function Export-ScanTargetSyncFailureCsv {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$FailureRows,

        [Parameter(Mandatory)]
        [string]$OutputDirectory,

        [Parameter(Mandatory)]
        [string]$FailureCsvFileName,

        [Parameter(Mandatory)]
        $FileSystemService
    )

    $resolvedOutputDirectory = @($FileSystemService.InitializeOutputDirectory.Invoke($OutputDirectory, "出力"))[0]

    $path = Join-Path $OutputDirectory $FailureCsvFileName

    if (-not (@($FileSystemService.TestPathUnderDirectory.Invoke($path, $resolvedOutputDirectory))[0])) {
        throw "チェック処理失敗CSVの出力先が許可ディレクトリ配下ではありません: $path"
    }

    $items = @($FailureRows)

    if ($items.Count -eq 0) {
        $removed = @($FileSystemService.RemoveFileIfExists.Invoke($path, $resolvedOutputDirectory))[0]

        return [pscustomobject]@{
            FailureCsvPath       = $path
            FailureCsvCreated    = $false
            OldFailureCsvRemoved = $removed
        }
    }

    $items |
        Select-Object Endpoint, DataId, User, Status, LastConnected, ScanStarted, ScanCompleted, Reason, Timestamp |
        Export-Csv -LiteralPath $path -NoTypeInformation -Encoding UTF8

    return [pscustomobject]@{
        FailureCsvPath       = $path
        FailureCsvCreated    = $true
        OldFailureCsvRemoved = $false
    }
}
