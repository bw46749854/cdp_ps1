$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

function Register-DeviceListExportDomAdapter {
    param([Parameter(Mandatory)]$Context)

    Register-FoundationDomBundle -Context $Context
}

function Test-DeviceListExportPageIdentity {
    param([Parameter(Mandatory)]$Context)

    Register-DeviceListExportDomAdapter -Context $Context
    $identity = Invoke-DeviceListExportDomOperation -Operation DetectPageIdentity -TimeoutSeconds 2
    $matched = ($identity -and $identity.ok -eq $true)

    $reason = 'DeviceListExport page identity did not match.'
    if ($matched) {
        $reason = 'DeviceListExport page identity matched.'
    }
    elseif ($identity -and $identity.PSObject.Properties['fatalCount']) {
        $reason = "DeviceListExport page identity did not match. fatalCount=$($identity.fatalCount)"
    }

    return [pscustomobject]@{
        Matched = ([bool]$matched)
        Reason = $reason
        Result = $identity
    }
}

function Assert-DeviceListExportInitialContract {
    return Assert-DeviceListExportDomOperationContract -Operation ValidateInitialContract -TimeoutSeconds 20
}

function Assert-DeviceListExportExportPageContract {
    return Assert-DeviceListExportDomOperationContract -Operation ValidateExportPageContract -TimeoutSeconds 20
}

function Invoke-DeviceListExportClickTaskButton {
    return Invoke-DeviceListExportDomOperation -Operation ClickTaskButton
}

function Wait-DeviceListExportTaskMenuReady {
    param([int]$TimeoutSeconds = 10)

    return Wait-DeviceListExportDomOperation `
        -Operation IsTaskMenuReady `
        -TimeoutSeconds $TimeoutSeconds `
        -Description '操作メニュー表示待ち'
}

function Invoke-DeviceListExportClickExportMenuItem {
    return Invoke-DeviceListExportDomOperation -Operation ClickExportMenuItem
}

function Assert-DeviceListExportPostcondition {
    return Assert-DeviceListExportDomOperationContract -Operation ValidateExportPostcondition -TimeoutSeconds 5
}
