$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。


function Get-FoundationRunId {
    return (Get-Date).ToString('yyyyMMdd_HHmmss_fff')
}

function New-FoundationLoggerService {
    param([AllowNull()][object]$Logger = $null)

    $writeFoundationLogCommand = Get-Command -Name Write-FoundationLog -CommandType Function -ErrorAction Stop
    $writeFoundationObjectCommand = Get-Command -Name Write-FoundationObject -CommandType Function -ErrorAction Stop
    $writeFoundationSectionCommand = Get-Command -Name Write-FoundationSection -CommandType Function -ErrorAction Stop

    return [pscustomobject]@{
        WriteInfo = {
            param([AllowEmptyString()][string]$Message = '')
            & $writeFoundationLogCommand -Logger $Logger -Level Info -Message $Message
        }.GetNewClosure()
        WriteWarning = {
            param([AllowEmptyString()][string]$Message = '')
            & $writeFoundationLogCommand -Logger $Logger -Level Warning -Message $Message
        }.GetNewClosure()
        WriteObject = {
            param(
                [object]$Data,
                [AllowEmptyString()][string]$Message = '',
                [int]$Depth = 10
            )
            & $writeFoundationObjectCommand -Logger $Logger -Message $Message -Data $Data -Depth $Depth
        }.GetNewClosure()
        WriteSection = {
            param([Parameter(Mandatory)][string]$Title)
            & $writeFoundationSectionCommand -Logger $Logger -Title $Title
        }.GetNewClosure()
    }
}

function New-FoundationWorkflowService {
    param([AllowNull()][object]$TimingService = $null)

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

            $invokeArgs = @{
                TotalCount = $TotalCount
                Operations = $Operations
                Logger = $Logger
                MaxScanLoops = $MaxScanLoops
                SameScrollLimit = $SameScrollLimit
                EmptyRowsMessage = $EmptyRowsMessage
            }

            if ($TimingService -and ($TimingService.SleepMilliseconds -is [scriptblock])) {
                $invokeArgs.Runtime = [pscustomobject]@{
                    SleepMilliseconds = $TimingService.SleepMilliseconds
                }
            }

            & $invokeScrollableListCommand @invokeArgs
        }.GetNewClosure()
    }
}

function New-FoundationFileSystemService {
    $initializeOutputDirectoryCommand = Get-Command -Name Initialize-FoundationOutputDirectory -CommandType Function -ErrorAction Stop
    $clearDirectoryContentsCommand = Get-Command -Name Clear-DirectoryContentsSafely -CommandType Function -ErrorAction Stop
    $assertFoundationSafeDirectoryCommand = Get-Command -Name Assert-FoundationSafeDirectory -CommandType Function -ErrorAction Stop
    $testPathUnderDirectoryCommand = Get-Command -Name Test-PathUnderDirectory -CommandType Function -ErrorAction Stop
    $removeFileIfExistsSafelyCommand = Get-Command -Name Remove-FileIfExistsSafely -CommandType Function -ErrorAction Stop

    return [pscustomobject]@{
        InitializeOutputDirectory = {
            param(
                [Parameter(Mandatory)][string]$Directory,
                [string]$Purpose = "出力"
            )

            & $initializeOutputDirectoryCommand -Directory $Directory -Purpose $Purpose
        }.GetNewClosure()
        ClearDirectory = {
            param(
                [Parameter(Mandatory)][string]$Directory,
                [string]$Purpose = "作業"
            )

            & $clearDirectoryContentsCommand -Directory $Directory -Purpose $Purpose
        }.GetNewClosure()
        AssertSafeDirectory = {
            param(
                [Parameter(Mandatory)][string]$Directory,
                [string]$Purpose = "作業"
            )

            & $assertFoundationSafeDirectoryCommand -Directory $Directory -Purpose $Purpose
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

function New-FoundationBrowserService {
    $openFoundationPageCommand = Get-Command -Name Open-FoundationPage -CommandType Function -ErrorAction Stop
    $openFoundationPageMatchingIdentityCommand = Get-Command -Name Open-FoundationPageMatchingIdentity -CommandType Function -ErrorAction Stop
    $setFoundationDownloadDirectoryCommand = Get-Command -Name Set-FoundationDownloadDirectory -CommandType Function -ErrorAction Stop

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


function New-FoundationTimingService {
    return [pscustomobject]@{
        Now = {
            Get-Date
        }
        TimestampText = {
            (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        }
        SleepMilliseconds = {
            param([int]$Milliseconds)
            Start-Sleep -Milliseconds $Milliseconds
        }
    }
}

function New-FoundationServices {
    param([AllowNull()][object]$Logger = $null)

    $timing = New-FoundationTimingService

    return [pscustomobject]@{
        Logger = New-FoundationLoggerService -Logger $Logger
        FileSystem = New-FoundationFileSystemService
        Browser = New-FoundationBrowserService
        Workflow = New-FoundationWorkflowService -TimingService $timing
        Timing = $timing
    }
}

function New-FoundationRunContext {
    param(
        [Parameter(Mandatory)][string]$RootPath,
        [Parameter(Mandatory)][hashtable]$Config,
        [Parameter(Mandatory)][string]$JobName,
        [AllowNull()][object]$JobDefinition = $null,
        [AllowEmptyString()][string]$ConfigPath = '',
        [AllowEmptyString()][string]$JobRegistryPath = ''
    )

    $runId = Get-FoundationRunId
    $common = $Config.Common
    $jobSettings = Get-FoundationJobConfig -Config $Config -JobName $JobName
    $logger = New-FoundationLogger -Config $common.Logging -RunId $runId
    $services = New-FoundationServices -Logger $logger

    return [pscustomobject]@{
        RootPath = $RootPath
        RunId = $runId
        JobName = $JobName
        JobDefinition = $JobDefinition
        ConfigPath = $ConfigPath
        JobRegistryPath = $JobRegistryPath
        Config = $Config
        CommonSettings = $common
        JobSettings = $jobSettings
        Logger = $logger
        Services = $services
        Page = $null
    }
}

function Close-FoundationRunContext {
    param([Parameter(Mandatory)]$Context)

    try {
        if ($Context.Page -and $Context.Page.CdpSession) {
            Close-CDPConnection -Session $Context.Page.CdpSession -Quiet
        }
        else {
            Close-CDPConnection -Quiet
        }
    }
    catch {}

    try { Close-FoundationLogger } catch {}
}
