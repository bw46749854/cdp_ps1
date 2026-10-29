$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

function Get-DeviceListExportDependencyProperty {
    param(
        [AllowNull()]$Object,
        [Parameter(Mandatory)][string]$Name
    )

    if (-not $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if (-not $property) { return $null }
    return $property.Value
}

function Get-DeviceListExportCallbackScriptBlock {
    param(
        [Parameter(Mandatory)]$Callbacks,
        [Parameter(Mandatory)][string]$Name
    )

    $value = Get-DeviceListExportDependencyProperty -Object $Callbacks -Name $Name
    if (-not ($value -is [scriptblock])) {
        throw "DeviceListExport callback '$Name' が scriptblock として定義されていません。"
    }

    return $value
}

function Get-DeviceListExportDependencyCommand {
    param([Parameter(Mandatory)][string]$Name)

    return Get-Command -Name $Name -CommandType Function -ErrorAction Stop
}

function New-DeviceListExportModuleBoundScriptBlock {
    param([Parameter(Mandatory)][scriptblock]$ScriptBlock)

    $module = $ExecutionContext.SessionState.Module
    if ($module -and ($module.PSObject.Methods.Name -contains 'NewBoundScriptBlock')) {
        return $module.NewBoundScriptBlock($ScriptBlock)
    }

    return $ScriptBlock.GetNewClosure()
}

function New-DeviceListExportPageIdentityMatcher {
    param([Parameter(Mandatory)]$Context)

    $boundIdentityMatcher = New-DeviceListExportModuleBoundScriptBlock -ScriptBlock {
        param([Parameter(Mandatory)]$ProbeContext)

        Test-DeviceListExportPageIdentity -Context $ProbeContext
    }

    return {
        param($PageTarget, $Session)
        & $boundIdentityMatcher $Context
    }.GetNewClosure()
}

function New-DeviceListExportDomCallbacks {
    param([Parameter(Mandatory)]$Context)

    # Workflow 実行時のスコープで private 関数名を再解決しない。
    # ScanTargetSync と同じく、構築時に CommandInfo を閉じ込める。
    $registerCommand = Get-DeviceListExportDependencyCommand -Name Register-DeviceListExportDomAdapter
    $assertInitialContractCommand = Get-DeviceListExportDependencyCommand -Name Assert-DeviceListExportInitialContract
    $assertExportPageContractCommand = Get-DeviceListExportDependencyCommand -Name Assert-DeviceListExportExportPageContract
    $clickTaskButtonCommand = Get-DeviceListExportDependencyCommand -Name Invoke-DeviceListExportClickTaskButton
    $waitTaskMenuReadyCommand = Get-DeviceListExportDependencyCommand -Name Wait-DeviceListExportTaskMenuReady
    $clickExportMenuItemCommand = Get-DeviceListExportDependencyCommand -Name Invoke-DeviceListExportClickExportMenuItem
    $assertPostconditionCommand = Get-DeviceListExportDependencyCommand -Name Assert-DeviceListExportPostcondition

    return [pscustomobject]@{
        Register = {
            & $registerCommand -Context $Context
        }.GetNewClosure()
        AssertInitialContract = {
            & $assertInitialContractCommand
        }.GetNewClosure()
        AssertExportPageContract = {
            & $assertExportPageContractCommand
        }.GetNewClosure()
        ClickTaskButton = {
            & $clickTaskButtonCommand
        }.GetNewClosure()
        WaitTaskMenuReady = {
            param([int]$TimeoutSeconds)
            & $waitTaskMenuReadyCommand -TimeoutSeconds $TimeoutSeconds
        }.GetNewClosure()
        ClickExportMenuItem = {
            & $clickExportMenuItemCommand
        }.GetNewClosure()
        AssertPostcondition = {
            & $assertPostconditionCommand
        }.GetNewClosure()
    }
}

function New-DeviceListExportDownloadCallbacks {

    # DOM callbacks と同じく、Workflow 実行時の raw function name 解決に依存しない。
    $waitDownloadedCsvCommand = Get-DeviceListExportDependencyCommand -Name Wait-DeviceListExportDownloadedCsv
    $renameDownloadedCsvCommand = Get-DeviceListExportDependencyCommand -Name Rename-DeviceListExportDownloadedCsv

    return [pscustomobject]@{
        WaitDownloadedCsv = {
            param(
                [string]$Directory,
                [string]$FileNamePattern,
                [int]$TimeoutSeconds,
                [int]$StableSeconds
            )
            & $waitDownloadedCsvCommand `
                -Directory $Directory `
                -FileNamePattern $FileNamePattern `
                -TimeoutSeconds $TimeoutSeconds `
                -StableSeconds $StableSeconds
        }.GetNewClosure()
        RenameDownloadedCsv = {
            param(
                [System.IO.FileInfo]$CsvFile,
                [string]$DestinationDirectory,
                [string]$FileNameTemplate,
                [string]$TimestampText
            )
            & $renameDownloadedCsvCommand `
                -CsvFile $CsvFile `
                -DestinationDirectory $DestinationDirectory `
                -FileNameTemplate $FileNameTemplate `
                -TimestampText $TimestampText
        }.GetNewClosure()
    }
}

function New-DeviceListExportLoggerPort {
    param([Parameter(Mandatory)]$Context)

    $services = Get-DeviceListExportDependencyProperty -Object $Context -Name 'Services'
    $serviceLogger = Get-DeviceListExportDependencyProperty -Object $services -Name 'Logger'
    $serviceWriteInfo = Get-DeviceListExportDependencyProperty -Object $serviceLogger -Name 'WriteInfo'
    $serviceWriteObject = Get-DeviceListExportDependencyProperty -Object $serviceLogger -Name 'WriteObject'
    if ($serviceWriteInfo -is [scriptblock] -and $serviceWriteObject -is [scriptblock]) {
        return $serviceLogger
    }

    $logger = $Context.Logger
    $writeFoundationLogCommand = Get-Command -Name Write-FoundationLog -CommandType Function -ErrorAction Stop
    $writeFoundationObjectCommand = Get-Command -Name Write-FoundationObject -CommandType Function -ErrorAction Stop
    return [pscustomobject]@{
        WriteInfo = {
            param([AllowEmptyString()][string]$Message = '')
            & $writeFoundationLogCommand -Logger $logger -Level Info -Message $Message
        }.GetNewClosure()
        WriteWarning = {
            param([AllowEmptyString()][string]$Message = '')
            & $writeFoundationLogCommand -Logger $logger -Level Warning -Message $Message
        }.GetNewClosure()
        WriteObject = {
            param([object]$Data,[AllowEmptyString()][string]$Message = '',[int]$Depth = 10)
            & $writeFoundationObjectCommand -Logger $logger -Message $Message -Data $Data -Depth $Depth
        }.GetNewClosure()
    }
}

function New-DeviceListExportTimingPort {
    param([Parameter(Mandatory)]$Context)

    $services = Get-DeviceListExportDependencyProperty -Object $Context -Name 'Services'
    $serviceTiming = Get-DeviceListExportDependencyProperty -Object $services -Name 'Timing'
    $sleepMilliseconds = Get-DeviceListExportDependencyProperty -Object $serviceTiming -Name 'SleepMilliseconds'

    if (-not ($sleepMilliseconds -is [scriptblock])) {
        $sleepMilliseconds = {
            param([int]$Milliseconds)
            Start-Sleep -Milliseconds $Milliseconds
        }
    }

    return [pscustomobject]@{
        TimestampText = { (Get-Date).ToString('MMdd') }
        SleepMilliseconds = $sleepMilliseconds
    }
}

function Assert-DeviceListExportWorkflowDependencies {
    param([Parameter(Mandatory)]$Dependencies)

    foreach ($name in @(
        'Register',
        'AssertInitialContract',
        'AssertExportPageContract',
        'ClickTaskButton',
        'WaitTaskMenuReady',
        'ClickExportMenuItem',
        'AssertPostcondition'
    )) {
        [void](Get-DeviceListExportCallbackScriptBlock -Callbacks $Dependencies.Dom -Name $name)
    }

    foreach ($name in @('WaitDownloadedCsv','RenameDownloadedCsv')) {
        [void](Get-DeviceListExportCallbackScriptBlock -Callbacks $Dependencies.Download -Name $name)
    }

    [void](Get-DeviceListExportCallbackScriptBlock -Callbacks $Dependencies.Logger -Name 'WriteInfo')
    [void](Get-DeviceListExportCallbackScriptBlock -Callbacks $Dependencies.Timing -Name 'TimestampText')
}

function Resolve-DeviceListExportWorkflowDependencies {
    param(
        [Parameter(Mandatory)]$Context,
        [AllowNull()]$Dependencies = $null
    )

    if (-not $Dependencies) {
        $Dependencies = [pscustomobject]@{}
    }

    $dom = Get-DeviceListExportDependencyProperty -Object $Dependencies -Name 'Dom'
    if (-not $dom) { $dom = New-DeviceListExportDomCallbacks -Context $Context }

    $download = Get-DeviceListExportDependencyProperty -Object $Dependencies -Name 'Download'
    if (-not $download) { $download = New-DeviceListExportDownloadCallbacks }

    $logger = Get-DeviceListExportDependencyProperty -Object $Dependencies -Name 'Logger'
    if (-not $logger) { $logger = New-DeviceListExportLoggerPort -Context $Context }

    $timing = Get-DeviceListExportDependencyProperty -Object $Dependencies -Name 'Timing'
    if (-not $timing) { $timing = New-DeviceListExportTimingPort -Context $Context }

    $resolved = [pscustomobject]@{
        Dom = $dom
        Download = $download
        Logger = $logger
        Timing = $timing
    }

    Assert-DeviceListExportWorkflowDependencies -Dependencies $resolved
    return $resolved
}
