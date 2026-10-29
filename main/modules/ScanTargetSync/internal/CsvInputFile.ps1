$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

function Import-VendorDeviceCsv {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "CSVファイルパスが空です。"
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "CSVファイルが見つかりません: $Path"
    }

    $firstLine = Get-Content -LiteralPath $Path -TotalCount 1 -Encoding UTF8

    if ([string]::IsNullOrWhiteSpace($firstLine)) {
        throw "CSVファイルの先頭行が空です: $Path"
    }

    $delimiter = if ($firstLine -match "`t") {
        "`t"
    }
    else {
        ","
    }

    return @(Import-Csv -LiteralPath $Path -Delimiter $delimiter -Encoding UTF8)
}

function Import-ScanTargetSyncInputCsv {
    param([Parameter(Mandatory)][string]$Path)

    return Import-VendorDeviceCsv -Path $Path
}
