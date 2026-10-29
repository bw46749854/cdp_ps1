$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

$script:ScanTargetSyncDomHelperName = '__ScanTargetSyncDomHelper'
$script:ScanTargetSyncDomMissingHelperMessage = 'ScanTargetSync DOM helper is not registered'

$script:ScanTargetSyncDomOperations = @{
    DetectPageIdentity = @{ MethodName = 'detectDevicePageIdentity'; Description = 'デバイス一覧画面識別'; MissingHelperBehavior = 'ReturnContractFailure'; ContractScope = 'scanTargetSyncDevicePageIdentity' }
    ValidateDevicePageContract = @{ MethodName = 'validateDevicePageContract'; Description = 'デバイス一覧画面契約'; MissingHelperBehavior = 'ReturnContractFailure'; ContractScope = 'scanTargetSyncDevicePage' }
    PrepareOperationContext = @{ MethodName = 'prepareOperationContext'; MissingHelperBehavior = 'Throw' }
    ValidateDeviceListContract = @{ MethodName = 'validateDeviceListContract'; Description = 'デバイス一覧リスト契約'; MissingHelperBehavior = 'ReturnContractFailure'; ContractScope = 'scanTargetSyncDeviceList' }
    FindDeviceRowsInfo = @{ MethodName = 'findDeviceRowsInfo'; MissingHelperBehavior = 'Throw' }
    SyncEndpointCheckbox = @{ MethodName = 'syncEndpointCheckbox'; MissingHelperBehavior = 'Throw'; Await = $true }
    ValidatePostSelectionContract = @{ MethodName = 'validatePostSelectionContract'; Description = 'チェック後の検索メニュー有効化契約'; MissingHelperBehavior = 'ReturnContractFailure'; ContractScope = 'scanTargetSyncPostSelection' }
    ScrollToTop = @{ MethodName = 'scrollToTop'; MissingHelperBehavior = 'Throw'; Await = $true }
    ScrollDown = @{ MethodName = 'scrollDown'; MissingHelperBehavior = 'Throw'; Await = $true }
}

function Get-ScanTargetSyncDomOperationDefinition {
    param([Parameter(Mandatory)][string]$Operation)

    if (-not $script:ScanTargetSyncDomOperations.ContainsKey($Operation)) {
        throw "未定義の ScanTargetSync DOM operation です: $Operation"
    }

    $definition = @{}
    foreach ($key in $script:ScanTargetSyncDomOperations[$Operation].Keys) {
        $definition[$key] = $script:ScanTargetSyncDomOperations[$Operation][$key]
    }

    $definition.HelperName = $script:ScanTargetSyncDomHelperName
    $definition.MissingHelperMessage = $script:ScanTargetSyncDomMissingHelperMessage
    return $definition
}

function New-ScanTargetSyncDomHelperParameters {
    param(
        [Parameter(Mandatory)][string]$Operation,
        [AllowNull()][object[]]$Arguments = @(),
        [int]$TimeoutSeconds = 0,
        [string]$Description = '',
        [AllowNull()][object]$MissingValue = $null,
        [switch]$HasMissingValueOverride,
        [switch]$Await
    )

    $definition = Get-ScanTargetSyncDomOperationDefinition -Operation $Operation
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

function Invoke-ScanTargetSyncDomOperation {
    param(
        [Parameter(Mandatory)][string]$Operation,
        [AllowNull()][object[]]$Arguments = @(),
        [int]$TimeoutSeconds = 0,
        [AllowNull()][object]$MissingValue = $null,
        [switch]$Await
    )

    $parameters = New-ScanTargetSyncDomHelperParameters `
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

function Assert-ScanTargetSyncDomOperationContract {
    param(
        [Parameter(Mandatory)][string]$Operation,
        [AllowNull()][object[]]$Arguments = @(),
        [int]$TimeoutSeconds = 0,
        [string]$Description = '',
        [AllowNull()][object]$MissingValue = $null,
        [switch]$Await
    )

    $parameters = New-ScanTargetSyncDomHelperParameters `
        -Operation $Operation `
        -Arguments $Arguments `
        -TimeoutSeconds $TimeoutSeconds `
        -Description $Description `
        -MissingValue $MissingValue `
        -HasMissingValueOverride:($PSBoundParameters.ContainsKey('MissingValue')) `
        -Await:$Await

    return Assert-FoundationDomHelperContract @parameters
}
