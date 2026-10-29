$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

function Register-ScanTargetSyncDomAdapter {
    param([Parameter(Mandatory)]$Context)

    Register-FoundationDomBundle -Context $Context
}

function Assert-ScanTargetSyncPage {
    return Assert-ScanTargetSyncDomOperationContract `
        -Operation ValidateDevicePageContract `
        -TimeoutSeconds 30
}

function Prepare-ScanTargetSyncOperationScope {
    return Invoke-ScanTargetSyncDomOperation `
        -Operation PrepareOperationContext `
        -TimeoutSeconds 20
}

function Assert-ScanTargetSyncDeviceList {
    return Assert-ScanTargetSyncDomOperationContract `
        -Operation ValidateDeviceListContract `
        -TimeoutSeconds 30
}

function Get-ScanTargetSyncDeviceTotalCount {
    param([object]$ListContract)

    return [int]$ListContract.details.totalCount
}

function Test-ScanTargetSyncPageIdentity {
    param([Parameter(Mandatory)]$Context)

    Register-ScanTargetSyncDomAdapter -Context $Context
    $identity = Invoke-ScanTargetSyncDomOperation `
        -Operation DetectPageIdentity `
        -TimeoutSeconds 2
    $matched = ($identity -and $identity.ok -eq $true)

    $reason = 'ScanTargetSync page identity did not match.'
    if ($matched) {
        $reason = 'ScanTargetSync page identity matched.'
    }
    elseif ($identity -and $identity.PSObject.Properties['fatalCount']) {
        $reason = "ScanTargetSync page identity did not match. fatalCount=$($identity.fatalCount)"
    }

    return [pscustomobject]@{
        Matched = ([bool]$matched)
        Reason = $reason
        Result = $identity
    }
}

function Get-VisibleScanTargetSyncRows {
    return @(Invoke-ScanTargetSyncDomOperation -Operation FindDeviceRowsInfo -TimeoutSeconds 10)
}

function Set-ScanTargetSyncDesiredState {
    param(
        [string]$Endpoint,
        [bool]$DesiredChecked
    )

    return Invoke-ScanTargetSyncDomOperation `
        -Operation SyncEndpointCheckbox `
        -Arguments @($Endpoint, $DesiredChecked) `
        -TimeoutSeconds 20
}

function Assert-ScanTargetSyncPostSelectionContract {
    return Assert-ScanTargetSyncDomOperationContract `
        -Operation ValidatePostSelectionContract `
        -TimeoutSeconds 10
}

function Scroll-ScanTargetSyncListToTop {
    Invoke-ScanTargetSyncDomOperation `
        -Operation ScrollToTop `
        -TimeoutSeconds 10 | Out-Null
}

function Scroll-ScanTargetSyncListDown {
    return Invoke-ScanTargetSyncDomOperation `
        -Operation ScrollDown `
        -TimeoutSeconds 10
}
