$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

function Export-InstalledAppExportFailureResultsCsv {
    param(
        [object[]]$FailureResults,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        $FileSystemService
    )

    $directory = Split-Path -Parent $Path

    if ([string]::IsNullOrWhiteSpace($directory)) {
        throw "InstalledAppExport失敗CSVの出力ディレクトリが空です: $Path"
    }

    $resolvedDirectory = @($FileSystemService.AssertSafeDirectory.Invoke($directory, "InstalledAppExport失敗CSV出力"))[0]

    if (-not (@($FileSystemService.TestPathUnderDirectory.Invoke($Path, $resolvedDirectory))[0])) {
        throw "InstalledAppExport失敗CSVの出力先が許可ディレクトリ配下ではありません: $Path"
    }

    $items = @($FailureResults)

    if ($items.Count -eq 0) {
        $FileSystemService.RemoveFileIfExists.Invoke($Path, $resolvedDirectory) | Out-Null
        return $null
    }

    $items |
        Select-Object DataId, AssetName, Reason, Timestamp |
        Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8

    return Get-Item -LiteralPath $Path
}

function Export-InstalledAppExportFailureCsv {
    param(
        [object[]]$FailureResults,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        $FileSystemService
    )

    return Export-InstalledAppExportFailureResultsCsv `
        -FailureResults $FailureResults `
        -Path $Path `
        -FileSystemService $FileSystemService
}
