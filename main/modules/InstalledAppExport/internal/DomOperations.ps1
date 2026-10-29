$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

$script:InstalledAppExportDomHelperName = '__InstalledAppExportDomHelper'
$script:InstalledAppExportDomMissingHelperMessage = 'InstalledAppExport DOM helper is not registered'

$script:InstalledAppExportDomOperations = @{
    DetectPageIdentity = @{ MethodName = 'detectAssetPageIdentity'; Description = '端末一覧画面識別'; MissingHelperBehavior = 'ReturnContractFailure'; ContractScope = 'assetPageIdentity' }
    ValidatePageContract = @{ MethodName = 'validateAssetPageContract'; Description = '初期端末一覧画面種別DOM契約'; MissingHelperBehavior = 'ReturnContractFailure'; ContractScope = 'assetPage' }
    ValidateListContract = @{ MethodName = 'validateAssetListContract'; Description = '初期端末一覧DOM契約'; MissingHelperBehavior = 'ReturnContractFailure'; ContractScope = 'assetList' }
    GetListTotalCount = @{ MethodName = 'getAssetListTotalCount'; MissingHelperBehavior = 'Throw' }
    FindRowsInfo = @{ MethodName = 'findAssetRowsInfo'; MissingHelperBehavior = 'Throw' }
    ClickNameCell = @{ MethodName = 'clickAssetNameCell'; MissingHelperBehavior = 'Throw' }
    GetSelectedRow = @{ MethodName = 'getSelectedAssetRow'; Description = '選択行が対象端末になるまで'; MissingHelperBehavior = 'ReturnValue'; MissingValue = $false }
    IsDetailPanelReadyFor = @{ MethodName = 'isDetailPanelReadyFor'; Description = '右側詳細パネルの対象端末名一致'; MissingHelperBehavior = 'ReturnValue'; MissingValue = $false }
    ValidateClickedRowContext = @{ MethodName = 'validateClickedRowContext'; Description = '行クリック後の詳細パネル対象一致契約'; MissingHelperBehavior = 'ReturnContractFailure'; ContractScope = 'clickedRowContext' }
    ClickAppTab = @{ MethodName = 'clickAppTab'; MissingHelperBehavior = 'Throw' }
    ValidateAppListContract = @{ MethodName = 'validateAppListContract'; Description = 'アプリ一覧DOM契約'; MissingHelperBehavior = 'ReturnContractFailure'; ContractScope = 'appList' }
    AssertAppRadioChecked = @{ MethodName = 'assertAppRadioChecked'; MissingHelperBehavior = 'Throw' }
    GetDetailName = @{ MethodName = 'getDetailAssetName'; MissingHelperBehavior = 'Throw' }
    ClickAppCsvButton = @{ MethodName = 'clickAppCsvButton'; MissingHelperBehavior = 'Throw' }
    CloseDetailPanel = @{ MethodName = 'closeDetailPanel'; MissingHelperBehavior = 'ReturnValue' }
    IsDetailPanelClosed = @{ MethodName = 'isDetailPanelClosed'; MissingHelperBehavior = 'ReturnValue'; MissingValue = $false }
    ScrollToTop = @{ MethodName = 'scrollToTop'; MissingHelperBehavior = 'Throw' }
    ScrollDown = @{ MethodName = 'scrollDown'; MissingHelperBehavior = 'Throw' }
}

function Get-InstalledAppExportDomOperationDefinition {
    param([Parameter(Mandatory)][string]$Operation)

    if (-not $script:InstalledAppExportDomOperations.ContainsKey($Operation)) {
        throw "未定義の InstalledAppExport DOM operation です: $Operation"
    }

    $definition = @{}
    foreach ($key in $script:InstalledAppExportDomOperations[$Operation].Keys) {
        $definition[$key] = $script:InstalledAppExportDomOperations[$Operation][$key]
    }

    $definition.HelperName = $script:InstalledAppExportDomHelperName
    $definition.MissingHelperMessage = $script:InstalledAppExportDomMissingHelperMessage
    return $definition
}

function New-InstalledAppExportDomHelperParameters {
    param(
        [Parameter(Mandatory)][string]$Operation,
        [AllowNull()][object[]]$Arguments = @(),
        [int]$TimeoutSeconds = 0,
        [string]$Description = '',
        [AllowNull()][object]$MissingValue = $null,
        [switch]$HasMissingValueOverride,
        [switch]$Await
    )

    $definition = Get-InstalledAppExportDomOperationDefinition -Operation $Operation
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

function Invoke-InstalledAppExportDomOperation {
    param(
        [Parameter(Mandatory)][string]$Operation,
        [AllowNull()][object[]]$Arguments = @(),
        [int]$TimeoutSeconds = 0,
        [AllowNull()][object]$MissingValue = $null,
        [switch]$Await
    )

    $parameters = New-InstalledAppExportDomHelperParameters `
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

function Wait-InstalledAppExportDomOperation {
    param(
        [Parameter(Mandatory)][string]$Operation,
        [AllowNull()][object[]]$Arguments = @(),
        [int]$TimeoutSeconds = 0,
        [string]$Description = '',
        [AllowNull()][object]$MissingValue = $null,
        [switch]$Await
    )

    $parameters = New-InstalledAppExportDomHelperParameters `
        -Operation $Operation `
        -Arguments $Arguments `
        -TimeoutSeconds $TimeoutSeconds `
        -Description $Description `
        -MissingValue $MissingValue `
        -HasMissingValueOverride:($PSBoundParameters.ContainsKey('MissingValue')) `
        -Await:$Await

    Wait-FoundationDomHelperMethod @parameters
}

function Wait-InstalledAppExportDomOperationResult {
    param(
        [Parameter(Mandatory)][string]$Operation,
        [AllowNull()][object[]]$Arguments = @(),
        [int]$TimeoutSeconds = 0,
        [string]$Description = '',
        [scriptblock]$AcceptResult = { param($Result) $Result -eq $true },
        [AllowNull()][object]$MissingValue = $null,
        [switch]$Await
    )

    $parameters = New-InstalledAppExportDomHelperParameters `
        -Operation $Operation `
        -Arguments $Arguments `
        -TimeoutSeconds $TimeoutSeconds `
        -Description $Description `
        -MissingValue $MissingValue `
        -HasMissingValueOverride:($PSBoundParameters.ContainsKey('MissingValue')) `
        -Await:$Await
    $parameters.AcceptResult = $AcceptResult

    Wait-FoundationDomHelperMethodResult @parameters
}

function Assert-InstalledAppExportDomOperationContract {
    param(
        [Parameter(Mandatory)][string]$Operation,
        [AllowNull()][object[]]$Arguments = @(),
        [int]$TimeoutSeconds = 0,
        [string]$Description = '',
        [AllowNull()][object]$MissingValue = $null,
        [switch]$Await
    )

    $parameters = New-InstalledAppExportDomHelperParameters `
        -Operation $Operation `
        -Arguments $Arguments `
        -TimeoutSeconds $TimeoutSeconds `
        -Description $Description `
        -MissingValue $MissingValue `
        -HasMissingValueOverride:($PSBoundParameters.ContainsKey('MissingValue')) `
        -Await:$Await

    return Assert-FoundationDomHelperContract @parameters
}
