$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

function Get-InstalledAppExportDependencyProperty {
    param(
        [AllowNull()]$Object,
        [Parameter(Mandatory)][string]$Name
    )

    if (-not $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if (-not $property) { return $null }
    return $property.Value
}

function Get-InstalledAppExportCallbackScriptBlock {
    param(
        [Parameter(Mandatory)]$Callbacks,
        [Parameter(Mandatory)][string]$Name
    )

    $value = Get-InstalledAppExportDependencyProperty -Object $Callbacks -Name $Name
    if (-not ($value -is [scriptblock])) {
        throw "InstalledAppExport callback '$Name' が scriptblock として定義されていません。"
    }

    return $value
}

function Get-InstalledAppExportTimestampTextCallback {
    param([Parameter(Mandatory)]$Context)

    $services = Get-InstalledAppExportDependencyProperty -Object $Context -Name 'Services'
    $serviceTiming = Get-InstalledAppExportDependencyProperty -Object $services -Name 'Timing'
    $serviceTimestampText = Get-InstalledAppExportDependencyProperty -Object $serviceTiming -Name 'TimestampText'
    if ($serviceTimestampText -is [scriptblock]) {
        return $serviceTimestampText
    }

    return {
        (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    }
}

function New-InstalledAppExportLoggerPort {
    param([Parameter(Mandatory)]$Context)

    $services = Get-InstalledAppExportDependencyProperty -Object $Context -Name 'Services'
    $serviceLogger = Get-InstalledAppExportDependencyProperty -Object $services -Name 'Logger'
    $serviceWriteWarning = Get-InstalledAppExportDependencyProperty -Object $serviceLogger -Name 'WriteWarning'
    if ($serviceWriteWarning -is [scriptblock]) {
        return $serviceLogger
    }

    $logger = $Context.Logger
    $writeFoundationLogCommand = Get-Command -Name Write-FoundationLog -CommandType Function -ErrorAction Stop
    return [pscustomobject]@{
        WriteWarning = {
            param([AllowEmptyString()][string]$Message = '')
            & $writeFoundationLogCommand -Logger $logger -Level Warning -Message $Message
        }.GetNewClosure()
    }
}

function New-InstalledAppExportWorkflowPort {
    param([Parameter(Mandatory)]$Context)

    $services = Get-InstalledAppExportDependencyProperty -Object $Context -Name 'Services'
    $serviceWorkflow = Get-InstalledAppExportDependencyProperty -Object $services -Name 'Workflow'
    $serviceInvokeScrollableList = Get-InstalledAppExportDependencyProperty -Object $serviceWorkflow -Name 'InvokeScrollableList'
    if ($serviceInvokeScrollableList -is [scriptblock]) {
        return $serviceWorkflow
    }

    $invokeScrollableListCommand = Get-Command -Name Invoke-ScrollableListWorkflow -CommandType Function -ErrorAction Stop
    return [pscustomobject]@{
        InvokeScrollableList = {
            param(
                [Parameter(Mandatory)][int]$TotalCount,
                [Parameter(Mandatory)]$Operations,
                [object]$Logger = $null,
                [int]$MaxScanLoops = 500,
                [int]$SameScrollLimit = 2,
                [string]$EmptyRowsMessage = '表示行を取得できませんでした。'
            )

            & $invokeScrollableListCommand `
                -TotalCount $TotalCount `
                -Operations $Operations `
                -Logger $Logger `
                -MaxScanLoops $MaxScanLoops `
                -SameScrollLimit $SameScrollLimit `
                -EmptyRowsMessage $EmptyRowsMessage
        }.GetNewClosure()
    }
}


function New-InstalledAppExportModuleBoundScriptBlock {
    param([Parameter(Mandatory)][scriptblock]$ScriptBlock)

    $module = $ExecutionContext.SessionState.Module
    if ($module -and ($module.PSObject.Methods.Name -contains 'NewBoundScriptBlock')) {
        return $module.NewBoundScriptBlock($ScriptBlock)
    }

    return $ScriptBlock.GetNewClosure()
}

function New-InstalledAppExportPageIdentityMatcher {
    param([Parameter(Mandatory)]$Context)

    # OpenPageMatchingIdentity は Foundation モジュール側で matcher を実行する。
    # InstalledAppExport モジュールに束縛した scriptblock 内で private 関数名を解決させる。
    # CommandInfo を先に捕捉すると Pester Mock を迂回するため、ここでは関数名呼び出しを維持する。
    $boundIdentityMatcher = New-InstalledAppExportModuleBoundScriptBlock -ScriptBlock {
        param([Parameter(Mandatory)]$ProbeContext)

        Test-InstalledAppExportPageIdentity -Context $ProbeContext
    }

    return {
        param($PageTarget, $Session)
        & $boundIdentityMatcher $Context
    }.GetNewClosure()
}

function New-InstalledAppExportListTraversalCallbacks {
    # Invoke-ScrollableListWorkflow は Foundation モジュール側で callback を実行する。
    # InstalledAppExport モジュール内の private 関数を安全に呼べるよう、feature-local factory で bridge を閉じ込める。
    $getVisibleRowsCommand = Get-Command -Name Get-VisibleAssetRows -CommandType Function -ErrorAction Stop
    $getRowKeyCommand = Get-Command -Name Get-InstalledAppExportRowKey -CommandType Function -ErrorAction Stop
    $scrollDownCommand = Get-Command -Name Scroll-InstalledAppExportListDown -CommandType Function -ErrorAction Stop

    return [pscustomobject]@{
        GetVisibleRows = { @(& $getVisibleRowsCommand) }.GetNewClosure()
        GetRowKey = { param($row) & $getRowKeyCommand -Row $row }.GetNewClosure()
        ScrollDown = { & $scrollDownCommand }.GetNewClosure()
    }
}

function New-InstalledAppExportRowActionCallbacks {
    param([Parameter(Mandatory)]$Context)

    # 行処理の実副作用も workflow から分離する。
    # 単体テストではこの default を実行せず、fake callback object を注入する。
    $exportForRowCommand = Get-Command -Name Invoke-InstalledAppExportCsvForRow -CommandType Function -ErrorAction Stop
    $newFailureCommand = Get-Command -Name New-InstalledAppExportFailure -CommandType Function -ErrorAction Stop
    $timestampText = Get-InstalledAppExportTimestampTextCallback -Context $Context

    return [pscustomobject]@{
        ExportForRow = {
            param($Context, [string]$DataId, [string]$AssetName)
            & $exportForRowCommand -Context $Context -DataId $DataId -AssetName $AssetName
        }.GetNewClosure()
        NewFailure = {
            param([string]$DataId, [string]$AssetName, [string]$Reason)
            & $newFailureCommand -DataId $DataId -AssetName $AssetName -Reason $Reason -Timestamp (& $timestampText)
        }.GetNewClosure()
    }
}


function Assert-InstalledAppExportWorkflowDependencies {
    param([Parameter(Mandatory)]$Dependencies)

    foreach ($name in @('GetVisibleRows', 'GetRowKey', 'ScrollDown')) {
        [void](Get-InstalledAppExportCallbackScriptBlock -Callbacks $Dependencies.ListTraversal -Name $name)
    }

    foreach ($name in @('ExportForRow', 'NewFailure')) {
        [void](Get-InstalledAppExportCallbackScriptBlock -Callbacks $Dependencies.RowAction -Name $name)
    }

    [void](Get-InstalledAppExportCallbackScriptBlock -Callbacks $Dependencies.Logger -Name 'WriteWarning')
    [void](Get-InstalledAppExportCallbackScriptBlock -Callbacks $Dependencies.Workflow -Name 'InvokeScrollableList')
}

function Resolve-InstalledAppExportWorkflowDependencies {
    param(
        [Parameter(Mandatory)]$Context,
        [AllowNull()]$Dependencies = $null
    )

    if (-not $Dependencies) {
        $Dependencies = [pscustomobject]@{}
    }

    $listTraversal = Get-InstalledAppExportDependencyProperty -Object $Dependencies -Name 'ListTraversal'
    if (-not $listTraversal) {
        $listTraversal = New-InstalledAppExportListTraversalCallbacks
    }

    $rowAction = Get-InstalledAppExportDependencyProperty -Object $Dependencies -Name 'RowAction'
    if (-not $rowAction) {
        $rowAction = New-InstalledAppExportRowActionCallbacks -Context $Context
    }

    $logger = Get-InstalledAppExportDependencyProperty -Object $Dependencies -Name 'Logger'
    if (-not $logger) {
        $logger = New-InstalledAppExportLoggerPort -Context $Context
    }

    $workflow = Get-InstalledAppExportDependencyProperty -Object $Dependencies -Name 'Workflow'
    if (-not $workflow) {
        $workflow = New-InstalledAppExportWorkflowPort -Context $Context
    }

    $resolved = [pscustomobject]@{
        ListTraversal = $listTraversal
        RowAction = $rowAction
        Logger = $logger
        Workflow = $workflow
    }

    Assert-InstalledAppExportWorkflowDependencies -Dependencies $resolved
    return $resolved
}
