$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

function New-DeviceListExportResult {
    param(
        [Parameter(Mandatory)][string]$DownloadedCsvPath,
        [Parameter(Mandatory)][string]$ExportedCsvPath,
        [AllowNull()][object]$DomResult = $null
    )

    return [pscustomobject]@{
        Ok = $true
        Feature = 'DeviceListExport'
        DownloadedCsvPath = $DownloadedCsvPath
        ExportedCsvPath = $ExportedCsvPath
        DomResult = $DomResult
    }
}

function Write-DeviceListExportResultSummary {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$Result
    )

    Write-FoundationSection -Logger $Context.Logger -Title 'DeviceListExport 処理結果'
    Write-FoundationLog -Logger $Context.Logger -Message "ダウンロードCSV: $($Result.DownloadedCsvPath)"
    Write-FoundationLog -Logger $Context.Logger -Message "リネーム済みCSV: $($Result.ExportedCsvPath)"
}
