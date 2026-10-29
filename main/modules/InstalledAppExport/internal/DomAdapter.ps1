$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

function Register-InstalledAppExportDomAdapter {
    param([Parameter(Mandatory)]$Context)

    Register-FoundationDomBundle -Context $Context
}

function Assert-InstalledAppExportPage {
    return Assert-InstalledAppExportDomOperationContract -Operation ValidatePageContract -TimeoutSeconds 20
}

function Assert-InstalledAppExportList {
    return Assert-InstalledAppExportDomOperationContract -Operation ValidateListContract -TimeoutSeconds 20
}

function Get-InstalledAppExportListTotalCount {
    return Invoke-InstalledAppExportDomOperation -Operation GetListTotalCount
}

function Test-InstalledAppExportPageIdentity {
    param([Parameter(Mandatory)]$Context)

    Register-InstalledAppExportDomAdapter -Context $Context
    $identity = Invoke-InstalledAppExportDomOperation -Operation DetectPageIdentity -TimeoutSeconds 2
    $matched = ($identity -and $identity.ok -eq $true)

    $reason = 'InstalledAppExport page identity did not match.'
    if ($matched) {
        $reason = 'InstalledAppExport page identity matched.'
    }
    elseif ($identity -and $identity.PSObject.Properties['fatalCount']) {
        $reason = "InstalledAppExport page identity did not match. fatalCount=$($identity.fatalCount)"
    }

    return [pscustomobject]@{
        Matched = ([bool]$matched)
        Reason = $reason
        Result = $identity
    }
}

function Get-VisibleAssetRows {
    return @(Invoke-InstalledAppExportDomOperation -Operation FindRowsInfo)
}

function Open-InstalledAppExportDetailPanel {
    param(
        [string]$DataId,
        [string]$AssetName
    )

    return Invoke-InstalledAppExportDomOperation -Operation ClickNameCell -Arguments @($DataId, $AssetName)
}

function Assert-InstalledAppExportDetailPanel {
    param(
        [string]$DataId,
        [string]$AssetName
    )

    $expectedDataId = $DataId
    $expectedAssetName = $AssetName
    $selectedRowMatches = {
        param($Result)
        return ($Result -and $Result.ok -eq $true -and $Result.dataId -eq $expectedDataId -and $Result.assetName -eq $expectedAssetName)
    }.GetNewClosure()

    Wait-InstalledAppExportDomOperationResult `
        -Operation GetSelectedRow `
        -TimeoutSeconds 10 `
        -AcceptResult $selectedRowMatches | Out-Null

    Wait-InstalledAppExportDomOperation `
        -Operation IsDetailPanelReadyFor `
        -Arguments @($AssetName) `
        -TimeoutSeconds 20 | Out-Null

    return Assert-InstalledAppExportDomOperationContract `
        -Operation ValidateClickedRowContext `
        -Arguments @($DataId, $AssetName) `
        -TimeoutSeconds 20 `
        -Description "行クリック後の詳細パネル対象一致: $AssetName ($DataId)"
}

function Open-InstalledAppExportAppTab {
    return Invoke-InstalledAppExportDomOperation -Operation ClickAppTab
}

function Assert-InstalledAppExportAppList {
    param(
        [string]$DataId,
        [string]$AssetName
    )

    return Assert-InstalledAppExportDomOperationContract `
        -Operation ValidateAppListContract `
        -TimeoutSeconds 20 `
        -Description "アプリ一覧DOM契約: $AssetName ($DataId)"
}

function Assert-InstalledAppExportAppRadioChecked {
    return Invoke-InstalledAppExportDomOperation -Operation AssertAppRadioChecked
}

function Get-InstalledAppExportDetailName {
    return Invoke-InstalledAppExportDomOperation -Operation GetDetailName
}

function Click-InstalledAppExportAppCsvButton {
    return Invoke-InstalledAppExportDomOperation -Operation ClickAppCsvButton
}

function Close-InstalledAppExportDetailPanel {
    $missingValue = [pscustomobject]@{
        ok = $false
        severity = 'warning'
        action = 'helper-not-registered'
        reason = 'helper_not_registered'
        message = 'InstalledAppExport DOM helper is not registered'
    }

    return Invoke-InstalledAppExportDomOperation -Operation CloseDetailPanel -MissingValue $missingValue
}

function Wait-InstalledAppExportDetailPanelClosed {
    param([int]$TimeoutSeconds = 5)

    return Wait-InstalledAppExportDomOperation `
        -Operation IsDetailPanelClosed `
        -TimeoutSeconds $TimeoutSeconds `
        -Description "右側詳細パネル close 後の短時間非表示確認" `
        -MissingValue $false
}

function Scroll-InstalledAppExportListToTop {
    Invoke-InstalledAppExportDomOperation -Operation ScrollToTop | Out-Null
}

function Scroll-InstalledAppExportListDown {
    return Invoke-InstalledAppExportDomOperation -Operation ScrollDown
}
