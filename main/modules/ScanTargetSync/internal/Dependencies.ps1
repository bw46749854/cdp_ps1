$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

function Get-ScanTargetSyncDependencyProperty {
    param(
        [AllowNull()]$Object,
        [Parameter(Mandatory)][string]$Name
    )

    if (-not $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if (-not $property) { return $null }
    return $property.Value
}

function Get-ScanTargetSyncCallbackScriptBlock {
    param(
        [Parameter(Mandatory)]$Callbacks,
        [Parameter(Mandatory)][string]$Name
    )

    $value = Get-ScanTargetSyncDependencyProperty -Object $Callbacks -Name $Name
    if (-not ($value -is [scriptblock])) {
        throw "ScanTargetSync callback '$Name' が scriptblock として定義されていません。"
    }

    return $value
}

function Test-ScanTargetSyncCallbackScriptBlock {
    param(
        [AllowNull()]$Callbacks,
        [Parameter(Mandatory)][string]$Name
    )

    $value = Get-ScanTargetSyncDependencyProperty -Object $Callbacks -Name $Name
    return ($value -is [scriptblock])
}

function Assert-ScanTargetSyncCallbackGroup {
    param(
        [AllowNull()]$Callbacks,
        [Parameter(Mandatory)][string[]]$Names
    )

    foreach ($name in $Names) {
        [void](Get-ScanTargetSyncCallbackScriptBlock -Callbacks $Callbacks -Name $name)
    }
}

function Test-ScanTargetSyncCallbackGroup {
    param(
        [AllowNull()]$Callbacks,
        [Parameter(Mandatory)][string[]]$Names
    )

    foreach ($name in $Names) {
        if (-not (Test-ScanTargetSyncCallbackScriptBlock -Callbacks $Callbacks -Name $name)) {
            return $false
        }
    }

    return $true
}

function Get-ScanTargetSyncDependencyCommand {
    param([Parameter(Mandatory)][string]$Name)

    return Get-Command -Name $Name -CommandType Function -ErrorAction Stop
}

function New-ScanTargetSyncLoggerPort {
    param([Parameter(Mandatory)]$Context)

    $services = Get-ScanTargetSyncDependencyProperty -Object $Context -Name 'Services'
    $serviceLogger = Get-ScanTargetSyncDependencyProperty -Object $services -Name 'Logger'
    $serviceWriteInfo = Get-ScanTargetSyncDependencyProperty -Object $serviceLogger -Name 'WriteInfo'
    $serviceWriteWarning = Get-ScanTargetSyncDependencyProperty -Object $serviceLogger -Name 'WriteWarning'
    $serviceWriteSection = Get-ScanTargetSyncDependencyProperty -Object $serviceLogger -Name 'WriteSection'
    if (($serviceWriteInfo -is [scriptblock]) -and ($serviceWriteWarning -is [scriptblock]) -and ($serviceWriteSection -is [scriptblock])) {
        return $serviceLogger
    }

    $logger = $Context.Logger
    $writeFoundationLogCommand = Get-ScanTargetSyncDependencyCommand -Name Write-FoundationLog
    $writeFoundationSectionCommand = Get-ScanTargetSyncDependencyCommand -Name Write-FoundationSection
    return [pscustomobject]@{
        WriteInfo = {
            param([AllowEmptyString()][string]$Message = '')
            & $writeFoundationLogCommand -Logger $logger -Level Info -Message $Message
        }.GetNewClosure()
        WriteWarning = {
            param([AllowEmptyString()][string]$Message = '')
            & $writeFoundationLogCommand -Logger $logger -Level Warning -Message $Message
        }.GetNewClosure()
        WriteSection = {
            param([Parameter(Mandatory)][string]$Title)
            & $writeFoundationSectionCommand -Logger $logger -Title $Title
        }.GetNewClosure()
    }
}

function New-ScanTargetSyncBrowserPort {
    param([Parameter(Mandatory)]$Context)

    $services = Get-ScanTargetSyncDependencyProperty -Object $Context -Name 'Services'
    $serviceBrowser = Get-ScanTargetSyncDependencyProperty -Object $services -Name 'Browser'
    $serviceOpenPage = Get-ScanTargetSyncDependencyProperty -Object $serviceBrowser -Name 'OpenPage'
    $serviceOpenPageMatchingIdentity = Get-ScanTargetSyncDependencyProperty -Object $serviceBrowser -Name 'OpenPageMatchingIdentity'
    if (($serviceOpenPage -is [scriptblock]) -and ($serviceOpenPageMatchingIdentity -is [scriptblock])) {
        return $serviceBrowser
    }

    $openFoundationPageCommand = Get-ScanTargetSyncDependencyCommand -Name Open-FoundationPage
    $openFoundationPageMatchingIdentityCommand = Get-ScanTargetSyncDependencyCommand -Name Open-FoundationPageMatchingIdentity
    $setFoundationDownloadDirectoryCommand = Get-ScanTargetSyncDependencyCommand -Name Set-FoundationDownloadDirectory
    return [pscustomobject]@{
        OpenPage = {
            param(
                [Parameter(Mandatory)][string]$DebuggerUrl,
                [int]$ConnectTimeoutSeconds = 15,
                [int]$CommandTimeoutSeconds = 30
            )

            & $openFoundationPageCommand `
                -DebuggerUrl $DebuggerUrl `
                -ConnectTimeoutSeconds $ConnectTimeoutSeconds `
                -CommandTimeoutSeconds $CommandTimeoutSeconds
        }.GetNewClosure()
        OpenPageMatchingIdentity = {
            param(
                [Parameter(Mandatory)][string]$DebuggerUrl,
                [int]$ConnectTimeoutSeconds = 15,
                [int]$CommandTimeoutSeconds = 30,
                [Parameter(Mandatory)][scriptblock]$PageIdentityMatcher
            )

            & $openFoundationPageMatchingIdentityCommand `
                -DebuggerUrl $DebuggerUrl `
                -ConnectTimeoutSeconds $ConnectTimeoutSeconds `
                -CommandTimeoutSeconds $CommandTimeoutSeconds `
                -PageIdentityMatcher $PageIdentityMatcher
        }.GetNewClosure()
        SetDownloadDirectory = {
            param([Parameter(Mandatory)][string]$Directory)
            & $setFoundationDownloadDirectoryCommand -Directory $Directory
        }.GetNewClosure()
    }
}

function New-ScanTargetSyncFileSystemPort {
    param([Parameter(Mandatory)]$Context)

    $services = Get-ScanTargetSyncDependencyProperty -Object $Context -Name 'Services'
    $serviceFileSystem = Get-ScanTargetSyncDependencyProperty -Object $services -Name 'FileSystem'
    $initializeOutputDirectory = Get-ScanTargetSyncDependencyProperty -Object $serviceFileSystem -Name 'InitializeOutputDirectory'
    $testPathUnderDirectory = Get-ScanTargetSyncDependencyProperty -Object $serviceFileSystem -Name 'TestPathUnderDirectory'
    $removeFileIfExists = Get-ScanTargetSyncDependencyProperty -Object $serviceFileSystem -Name 'RemoveFileIfExists'
    if (($initializeOutputDirectory -is [scriptblock]) -and ($testPathUnderDirectory -is [scriptblock]) -and ($removeFileIfExists -is [scriptblock])) {
        return $serviceFileSystem
    }

    $initializeFoundationOutputDirectoryCommand = Get-ScanTargetSyncDependencyCommand -Name Initialize-FoundationOutputDirectory
    $testPathUnderDirectoryCommand = Get-ScanTargetSyncDependencyCommand -Name Test-PathUnderDirectory
    $removeFileIfExistsSafelyCommand = Get-ScanTargetSyncDependencyCommand -Name Remove-FileIfExistsSafely

    return [pscustomobject]@{
        InitializeOutputDirectory = {
            param(
                [Parameter(Mandatory)][string]$Directory,
                [string]$Purpose = '出力'
            )

            & $initializeFoundationOutputDirectoryCommand -Directory $Directory -Purpose $Purpose
        }.GetNewClosure()
        TestPathUnderDirectory = {
            param(
                [Parameter(Mandatory)][string]$Path,
                [Parameter(Mandatory)][string]$Directory
            )

            & $testPathUnderDirectoryCommand -Path $Path -Directory $Directory
        }.GetNewClosure()
        RemoveFileIfExists = {
            param(
                [Parameter(Mandatory)][string]$Path,
                [Parameter(Mandatory)][string]$AllowedDirectory
            )

            & $removeFileIfExistsSafelyCommand -Path $Path -AllowedDirectory $AllowedDirectory
        }.GetNewClosure()
    }
}

function New-ScanTargetSyncTimingPort {
    param([Parameter(Mandatory)]$Context)

    $services = Get-ScanTargetSyncDependencyProperty -Object $Context -Name 'Services'
    $serviceTiming = Get-ScanTargetSyncDependencyProperty -Object $services -Name 'Timing'
    $serviceTimestampText = Get-ScanTargetSyncDependencyProperty -Object $serviceTiming -Name 'TimestampText'
    if ($serviceTimestampText -is [scriptblock]) {
        return $serviceTiming
    }

    return [pscustomobject]@{
        TimestampText = {
            (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        }
    }
}

function New-ScanTargetSyncDomPort {
    param([Parameter(Mandatory)]$Context)

    # ScanTargetSync feature 内の DOM 関数 bridge。
    # 他 feature と共通化せず、ScanTargetSync の契約だけをここに閉じ込める。
    # 実行時スコープでの raw function name 解決に依存しないよう、構築時に CommandInfo を閉じ込める。
    $registerAdapterCommand = Get-ScanTargetSyncDependencyCommand -Name Register-ScanTargetSyncDomAdapter
    $assertPageCommand = Get-ScanTargetSyncDependencyCommand -Name Assert-ScanTargetSyncPage
    $assertDeviceListCommand = Get-ScanTargetSyncDependencyCommand -Name Assert-ScanTargetSyncDeviceList
    $prepareOperationScopeCommand = Get-ScanTargetSyncDependencyCommand -Name Prepare-ScanTargetSyncOperationScope
    $getVisibleRowsCommand = Get-ScanTargetSyncDependencyCommand -Name Get-VisibleScanTargetSyncRows
    $scrollToTopCommand = Get-ScanTargetSyncDependencyCommand -Name Scroll-ScanTargetSyncListToTop
    $scrollDownCommand = Get-ScanTargetSyncDependencyCommand -Name Scroll-ScanTargetSyncListDown
    $assertPostSelectionContractCommand = Get-ScanTargetSyncDependencyCommand -Name Assert-ScanTargetSyncPostSelectionContract
    $testPageIdentityCommand = Get-ScanTargetSyncDependencyCommand -Name Test-ScanTargetSyncPageIdentity

    return [pscustomobject]@{
        RegisterAdapter = {
            & $registerAdapterCommand -Context $Context
        }.GetNewClosure()
        AssertPage = {
            & $assertPageCommand
        }.GetNewClosure()
        TestPageIdentity = {
            & $testPageIdentityCommand -Context $Context
        }.GetNewClosure()
        AssertDeviceList = {
            & $assertDeviceListCommand
        }.GetNewClosure()
        PrepareOperationScope = {
            & $prepareOperationScopeCommand
        }.GetNewClosure()
        GetVisibleRows = {
            @(& $getVisibleRowsCommand)
        }.GetNewClosure()
        ScrollToTop = {
            & $scrollToTopCommand
        }.GetNewClosure()
        ScrollDown = {
            & $scrollDownCommand
        }.GetNewClosure()
        AssertPostSelectionContract = {
            & $assertPostSelectionContractCommand
        }.GetNewClosure()
    }
}


function New-ScanTargetSyncPageIdentityMatcher {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$Dependencies
    )

    # OpenPageMatchingIdentity は Foundation モジュール側で matcher を実行する。
    # ScanTargetSync では Dom port 構築時に CommandInfo を閉じ込めているため、ここでは callback port を閉じ込める。
    $testPageIdentity = Get-ScanTargetSyncCallbackScriptBlock -Callbacks $Dependencies.Dom -Name 'TestPageIdentity'

    return {
        param($PageTarget, $Session)
        & $testPageIdentity
    }.GetNewClosure()
}

function New-ScanTargetSyncEndpointActionCallbacks {
    # checkbox 操作と致命的 CDP 判定は endpoint 同期処理の副作用境界として扱う。
    # DOM port と同様に、構築時に CommandInfo を閉じ込める。
    $setDesiredStateCommand = Get-ScanTargetSyncDependencyCommand -Name Set-ScanTargetSyncDesiredState
    $testFoundationFatalErrorCommand = Get-ScanTargetSyncDependencyCommand -Name Test-FoundationFatalError

    return [pscustomobject]@{
        SetDesiredState = {
            param(
                [Parameter(Mandatory)][string]$Endpoint,
                [Parameter(Mandatory)][bool]$DesiredChecked
            )

            & $setDesiredStateCommand -Endpoint $Endpoint -DesiredChecked $DesiredChecked
        }.GetNewClosure()
        TestFoundationFatalError = {
            param([AllowEmptyString()][string]$Message = '')
            & $testFoundationFatalErrorCommand -Message $Message
        }.GetNewClosure()
    }
}


function Assert-ScanTargetSyncBrowserDependencies {
    param([Parameter(Mandatory)]$Dependencies)

    Assert-ScanTargetSyncCallbackGroup -Callbacks $Dependencies.Browser -Names @('OpenPageMatchingIdentity')
}

function Assert-ScanTargetSyncFileSystemDependencies {
    param(
        [Parameter(Mandatory)]$Dependencies,
        [Parameter(Mandatory)][string[]]$Names
    )

    Assert-ScanTargetSyncCallbackGroup -Callbacks $Dependencies.FileSystem -Names $Names
}

function Assert-ScanTargetSyncLoggerDependencies {
    param(
        [Parameter(Mandatory)]$Dependencies,
        [string[]]$Names = @('WriteInfo', 'WriteWarning', 'WriteSection')
    )

    Assert-ScanTargetSyncCallbackGroup -Callbacks $Dependencies.Logger -Names $Names
}

function Assert-ScanTargetSyncPageDependencies {
    param([Parameter(Mandatory)]$Dependencies)

    Assert-ScanTargetSyncBrowserDependencies -Dependencies $Dependencies
    Assert-ScanTargetSyncCallbackGroup `
        -Callbacks $Dependencies.Dom `
        -Names @(
            'RegisterAdapter',
            'TestPageIdentity',
            'AssertPage',
            'AssertDeviceList',
            'PrepareOperationScope',
            'ScrollToTop'
        )
}

function Assert-ScanTargetSyncPostSelectionDependencies {
    param([Parameter(Mandatory)]$Dependencies)

    Assert-ScanTargetSyncCallbackGroup -Callbacks $Dependencies.Dom -Names @('AssertPostSelectionContract')
}

function Assert-ScanTargetSyncUiScanDependencies {
    param([Parameter(Mandatory)]$Dependencies)

    Assert-ScanTargetSyncCallbackGroup -Callbacks $Dependencies.Dom -Names @('GetVisibleRows')
}

function Assert-ScanTargetSyncUiScanCursorDependencies {
    param([Parameter(Mandatory)]$Dependencies)

    Assert-ScanTargetSyncCallbackGroup -Callbacks $Dependencies.Dom -Names @('ScrollDown')
}

function Assert-ScanTargetSyncEndpointActionDependencies {
    param([Parameter(Mandatory)]$Dependencies)

    Assert-ScanTargetSyncCallbackGroup -Callbacks $Dependencies.EndpointAction -Names @('SetDesiredState', 'TestFoundationFatalError')
}

function Assert-ScanTargetSyncWorkflowInitializationDependencies {
    param([Parameter(Mandatory)]$Dependencies)

    Assert-ScanTargetSyncFileSystemDependencies -Dependencies $Dependencies -Names @('InitializeOutputDirectory')
}

function Assert-ScanTargetSyncTimingDependencies {
    param([Parameter(Mandatory)]$Dependencies)

    Assert-ScanTargetSyncCallbackGroup -Callbacks $Dependencies.Timing -Names @('TimestampText')
}

function Assert-ScanTargetSyncWorkflowDependencies {
    param([Parameter(Mandatory)]$Dependencies)

    Assert-ScanTargetSyncTimingDependencies -Dependencies $Dependencies
    Assert-ScanTargetSyncPageDependencies -Dependencies $Dependencies
    Assert-ScanTargetSyncPostSelectionDependencies -Dependencies $Dependencies
    Assert-ScanTargetSyncUiScanDependencies -Dependencies $Dependencies
    Assert-ScanTargetSyncUiScanCursorDependencies -Dependencies $Dependencies
    Assert-ScanTargetSyncEndpointActionDependencies -Dependencies $Dependencies
    Assert-ScanTargetSyncFileSystemDependencies `
        -Dependencies $Dependencies `
        -Names @('InitializeOutputDirectory', 'TestPathUnderDirectory', 'RemoveFileIfExists')
    Assert-ScanTargetSyncLoggerDependencies -Dependencies $Dependencies
}

function Resolve-ScanTargetSyncWorkflowDependencies {
    param(
        [Parameter(Mandatory)]$Context,
        [AllowNull()]$Dependencies = $null
    )

    if (-not $Dependencies) {
        $Dependencies = [pscustomobject]@{}
    }

    $browser = Get-ScanTargetSyncDependencyProperty -Object $Dependencies -Name 'Browser'
    if (-not $browser) {
        $browser = New-ScanTargetSyncBrowserPort -Context $Context
    }

    $fileSystem = Get-ScanTargetSyncDependencyProperty -Object $Dependencies -Name 'FileSystem'
    if (-not $fileSystem) {
        $fileSystem = New-ScanTargetSyncFileSystemPort -Context $Context
    }

    $logger = Get-ScanTargetSyncDependencyProperty -Object $Dependencies -Name 'Logger'
    if (-not (Test-ScanTargetSyncCallbackGroup -Callbacks $logger -Names @('WriteInfo', 'WriteWarning', 'WriteSection'))) {
        $logger = New-ScanTargetSyncLoggerPort -Context $Context
    }

    $timing = Get-ScanTargetSyncDependencyProperty -Object $Dependencies -Name 'Timing'
    if (-not (Test-ScanTargetSyncCallbackGroup -Callbacks $timing -Names @('TimestampText'))) {
        $timing = New-ScanTargetSyncTimingPort -Context $Context
    }

    $dom = Get-ScanTargetSyncDependencyProperty -Object $Dependencies -Name 'Dom'
    if (-not $dom) {
        $dom = New-ScanTargetSyncDomPort -Context $Context
    }

    $endpointAction = Get-ScanTargetSyncDependencyProperty -Object $Dependencies -Name 'EndpointAction'
    if (-not $endpointAction) {
        $endpointAction = New-ScanTargetSyncEndpointActionCallbacks
    }

    # Resolve は不足している上位 port を補うだけにする。
    # 各処理が必要とする callback は、その処理の入口で粒度を分けて検証する。
    return [pscustomobject]@{
        Browser = $browser
        FileSystem = $fileSystem
        Logger = $logger
        Timing = $timing
        Dom = $dom
        EndpointAction = $endpointAction
    }
}
