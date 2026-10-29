$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

function Close-InstalledAppExportDetailPanelSafely {
    param([Parameter(Mandatory)]$Context)
    $settings = $Context.JobSettings
    try {
        $closeResult = Close-InstalledAppExportDetailPanel
        if ($closeResult -and $closeResult.ok -ne $true) {
            $details = $closeResult | ConvertTo-Json -Compress -Depth 20
            Write-FoundationLog -Logger $Context.Logger -Level Warning -Message "右側詳細パネルのクローズは完了しませんでした。details=$details"
            return
        }
        if ($closeResult -and $closeResult.action) { Write-FoundationLog -Logger $Context.Logger -Message "詳細パネル cleanup: $($closeResult.action)" }
        if ($closeResult -and $closeResult.alreadyClosed -eq $true) { return }
        try {
            Wait-InstalledAppExportDetailPanelClosed `
                -TimeoutSeconds ([int]$settings.DetailPanelCloseWaitSeconds) | Out-Null
            Write-FoundationLog -Logger $Context.Logger -Message "詳細パネル cleanup: close後の非表示を確認しました。"
        }
        catch {
            Write-FoundationLog -Logger $Context.Logger -Level Warning -Message "右側詳細パネルの close 後、短時間内に非表示を確認できませんでした。詳細: $($_.Exception.Message)"
        }
    }
    catch {
        Write-FoundationLog -Logger $Context.Logger -Level Warning -Message "右側詳細パネルのクローズ処理に失敗しました。詳細: $($_.Exception.Message)"
    }
}

function Start-InstalledAppExportCsvRow {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string]$DataId,
        [Parameter(Mandatory)][string]$AssetName
    )

    Write-FoundationLog -Logger $Context.Logger -Message "------------------------------------------------------------"
    Write-FoundationLog -Logger $Context.Logger -Message "処理開始: $AssetName ($DataId)"
}

function Open-InstalledAppExportCsvDetail {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string]$DataId,
        [Parameter(Mandatory)][string]$AssetName
    )

    Write-FoundationObject -Logger $Context.Logger -Data (Open-InstalledAppExportDetailPanel -DataId $DataId -AssetName $AssetName)
    Assert-InstalledAppExportDetailPanel -DataId $DataId -AssetName $AssetName | Out-Null
    Write-FoundationLog -Logger $Context.Logger -Message "右側詳細パネルを確認しました: $AssetName"
}

function Open-InstalledAppExportCsvList {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string]$DataId,
        [Parameter(Mandatory)][string]$AssetName
    )

    Write-FoundationObject -Logger $Context.Logger -Data (Open-InstalledAppExportAppTab)
    Assert-InstalledAppExportAppList -DataId $DataId -AssetName $AssetName | Out-Null
    Write-FoundationObject -Logger $Context.Logger -Data (Assert-InstalledAppExportAppRadioChecked)
}

function Assert-InstalledAppExportCsvTarget {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string]$AssetName
    )

    $detailAssetName = Get-InstalledAppExportDetailName
    if ($detailAssetName -ne $AssetName) {
        throw "右側詳細パネルの端末名が対象と一致しません。expected=$AssetName actual=$detailAssetName"
    }
}

function Invoke-InstalledAppExportAppCsvDownload {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string]$AssetName
    )

    $settings = $Context.JobSettings
    Write-FoundationLog -Logger $Context.Logger -Message "アプリ一覧のCSV出力ボタンをクリックします... AssetName=$AssetName"
    $Context.Services.FileSystem.ClearDirectory.Invoke($settings.TempDirectory, "一時ダウンロード")
    Write-FoundationObject -Logger $Context.Logger -Data (Click-InstalledAppExportAppCsvButton)
    $downloadedCsv = Wait-InstalledAppExportDownloadedCsv -Directory $settings.TempDirectory -Prefix $settings.DownloadFilePrefix -TimeoutSeconds ([int]$settings.DownloadTimeoutSeconds) -StableSeconds ([int]$settings.DownloadStableSeconds)
    $renamedCsv = Rename-InstalledAppExportDownloadedCsv -CsvFile $downloadedCsv -AssetName $AssetName -DestinationDirectory $settings.DownloadDirectory
    Write-FoundationLog -Logger $Context.Logger -Message "CSVファイル名を変更しました: $($renamedCsv.FullName)"
    return $renamedCsv
}

function Complete-InstalledAppExportCsvResult {
    param(
        [Parameter(Mandatory)][string]$DataId,
        [Parameter(Mandatory)][string]$AssetName,
        [Parameter(Mandatory)]$RenamedCsv
    )

    return New-InstalledAppExportProcessResult -DataId $DataId -AssetName $AssetName -CsvPath $RenamedCsv.FullName
}

function Invoke-InstalledAppExportCsvForRow {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string]$DataId,
        [Parameter(Mandatory)][string]$AssetName
    )

    try {
        Start-InstalledAppExportCsvRow -Context $Context -DataId $DataId -AssetName $AssetName
        Open-InstalledAppExportCsvDetail -Context $Context -DataId $DataId -AssetName $AssetName
        Open-InstalledAppExportCsvList -Context $Context -DataId $DataId -AssetName $AssetName
        Assert-InstalledAppExportCsvTarget -Context $Context -AssetName $AssetName
        $renamedCsv = Invoke-InstalledAppExportAppCsvDownload -Context $Context -AssetName $AssetName
        return Complete-InstalledAppExportCsvResult -DataId $DataId -AssetName $AssetName -RenamedCsv $renamedCsv
    }
    finally {
        Close-InstalledAppExportDetailPanelSafely -Context $Context
    }
}

