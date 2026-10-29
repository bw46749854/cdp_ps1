$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

$script:DeviceListExportDomHelperName = '__DeviceListExportDomHelper'
$script:DeviceListExportDomMissingHelperMessage = 'DeviceListExport DOM helper is not registered'

$script:DeviceListExportDomOperations = @{
    DetectPageIdentity = @{ MethodName = 'detectDeviceListExportPageIdentity'; Description = 'DeviceListExport対象ページ識別'; MissingHelperBehavior = 'ReturnContractFailure'; ContractScope = 'deviceListExportPageIdentity' }
    ValidateInitialContract = @{ MethodName = 'validateInitialContract'; Description = 'DeviceListExport初期DOM契約'; MissingHelperBehavior = 'ReturnContractFailure'; ContractScope = 'deviceListExportInitial' }
    ValidateExportPageContract = @{ MethodName = 'validateExportPageContract'; Description = 'DeviceListExportエクスポート対象画面DOM契約'; MissingHelperBehavior = 'ReturnContractFailure'; ContractScope = 'deviceListExportPage' }
    ClickTaskButton = @{ MethodName = 'clickTaskButton'; MissingHelperBehavior = 'Throw'; Await = $true }
    IsTaskMenuReady = @{ MethodName = 'isTaskMenuReady'; Description = '操作メニュー表示待ち'; MissingHelperBehavior = 'ReturnValue'; MissingValue = $false }
    ClickExportMenuItem = @{ MethodName = 'clickExportMenuItem'; MissingHelperBehavior = 'Throw'; Await = $true }
    ValidateExportPostcondition = @{ MethodName = 'validateExportPostcondition'; Description = 'DeviceListExportエクスポートクリック後DOM契約'; MissingHelperBehavior = 'ReturnContractFailure'; ContractScope = 'deviceListExportPostcondition' }
}

function Get-DeviceListExportDomOperationDefinition {
    param([Parameter(Mandatory)][string]$Operation)

    if (-not $script:DeviceListExportDomOperations.ContainsKey($Operation)) {
        throw "未定義の DeviceListExport DOM operation です: $Operation"
    }

    $definition = @{}
    foreach ($key in $script:DeviceListExportDomOperations[$Operation].Keys) {
        $definition[$key] = $script:DeviceListExportDomOperations[$Operation][$key]
    }

    $definition.HelperName = $script:DeviceListExportDomHelperName
    $definition.MissingHelperMessage = $script:DeviceListExportDomMissingHelperMessage
    return $definition
}

function New-DeviceListExportDomHelperParameters {
    param(
        [Parameter(Mandatory)][string]$Operation,
        [AllowNull()][object[]]$Arguments = @(),
        [int]$TimeoutSeconds = 0,
        [string]$Description = '',
        [AllowNull()][object]$MissingValue = $null,
        [switch]$HasMissingValueOverride,
        [switch]$Await
    )

    $definition = Get-DeviceListExportDomOperationDefinition -Operation $Operation
    $parameters = @{
        HelperName = $definition.HelperName
        MethodName = $definition.MethodName
        Arguments = @($Arguments)
        MissingHelperBehavior = $definition.MissingHelperBehavior
        MissingHelperMessage = $definition.MissingHelperMessage
    }

    if ($TimeoutSeconds -gt 0) {
        $parameters.TimeoutSeconds = $TimeoutSeconds
    }

    if ($definition.ContainsKey('ContractScope')) {
        $parameters.ContractScope = $definition.ContractScope
    }

    if (-not [string]::IsNullOrWhiteSpace($Description)) {
        $parameters.Description = $Description
    }
    elseif ($definition.ContainsKey('Description')) {
        $parameters.Description = $definition.Description
    }

    if ($HasMissingValueOverride) {
        $parameters.MissingValue = $MissingValue
    }
    elseif ($definition.ContainsKey('MissingValue')) {
        $parameters.MissingValue = $definition.MissingValue
    }

    if ($Await -or ($definition.ContainsKey('Await') -and [bool]$definition.Await)) {
        $parameters.Await = $true
    }

    return $parameters
}

function Invoke-DeviceListExportDomOperation {
    param(
        [Parameter(Mandatory)][string]$Operation,
        [AllowNull()][object[]]$Arguments = @(),
        [int]$TimeoutSeconds = 0,
        [AllowNull()][object]$MissingValue = $null,
        [switch]$Await
    )

    $parameters = New-DeviceListExportDomHelperParameters `
        -Operation $Operation `
        -Arguments $Arguments `
        -TimeoutSeconds $TimeoutSeconds `
        -MissingValue $MissingValue `
        -HasMissingValueOverride:($PSBoundParameters.ContainsKey('MissingValue')) `
        -Await:$Await

    if ($parameters.ContainsKey('Description')) {
        [void]$parameters.Remove('Description')
    }

    return Invoke-FoundationDomHelperMethod @parameters
}

function Wait-DeviceListExportDomOperation {
    param(
        [Parameter(Mandatory)][string]$Operation,
        [AllowNull()][object[]]$Arguments = @(),
        [int]$TimeoutSeconds = 0,
        [string]$Description = '',
        [AllowNull()][object]$MissingValue = $null,
        [switch]$Await
    )

    $parameters = New-DeviceListExportDomHelperParameters `
        -Operation $Operation `
        -Arguments $Arguments `
        -TimeoutSeconds $TimeoutSeconds `
        -Description $Description `
        -MissingValue $MissingValue `
        -HasMissingValueOverride:($PSBoundParameters.ContainsKey('MissingValue')) `
        -Await:$Await

    Wait-FoundationDomHelperMethod @parameters
}

function Assert-DeviceListExportDomOperationContract {
    param(
        [Parameter(Mandatory)][string]$Operation,
        [AllowNull()][object[]]$Arguments = @(),
        [int]$TimeoutSeconds = 0,
        [string]$Description = '',
        [AllowNull()][object]$MissingValue = $null,
        [switch]$Await
    )

    $parameters = New-DeviceListExportDomHelperParameters `
        -Operation $Operation `
        -Arguments $Arguments `
        -TimeoutSeconds $TimeoutSeconds `
        -Description $Description `
        -MissingValue $MissingValue `
        -HasMissingValueOverride:($PSBoundParameters.ContainsKey('MissingValue')) `
        -Await:$Await

    return Assert-FoundationDomHelperContract @parameters
}
