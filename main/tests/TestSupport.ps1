$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

function New-TestCallList {
    $list = New-Object System.Collections.ArrayList
    return ,$list
}

function Get-TestCallCount {
    param(
        [Parameter(Mandatory)]$Calls,
        [Parameter(Mandatory)][string]$Name
    )

    $count = 0
    foreach ($call in $Calls) {
        if ($call.Name -eq $Name) {
            $count++
        }
    }

    return $count
}

function New-TestLoggerPort {
    $calls = New-TestCallList
    $records = New-TestCallList

    $writeInfo = {
        param([AllowEmptyString()][string]$Message = '')

        [void]$calls.Add([pscustomobject]@{
            Name = 'WriteInfo'
            Arguments = @{ Message = $Message }
        })
        [void]$records.Add([pscustomobject]@{
            Level = 'Info'
            Message = $Message
            Data = $null
            Depth = $null
        })
    }.GetNewClosure()

    $writeWarning = {
        param([AllowEmptyString()][string]$Message = '')

        [void]$calls.Add([pscustomobject]@{
            Name = 'WriteWarning'
            Arguments = @{ Message = $Message }
        })
        [void]$records.Add([pscustomobject]@{
            Level = 'Warning'
            Message = $Message
            Data = $null
            Depth = $null
        })
    }.GetNewClosure()

    $writeObject = {
        param(
            [object]$Data,
            [AllowEmptyString()][string]$Message = '',
            [int]$Depth = 10
        )

        [void]$calls.Add([pscustomobject]@{
            Name = 'WriteObject'
            Arguments = @{ Message = $Message; Data = $Data; Depth = $Depth }
        })
        [void]$records.Add([pscustomobject]@{
            Level = 'Object'
            Message = $Message
            Data = $Data
            Depth = $Depth
        })
    }.GetNewClosure()

    $writeSection = {
        param([Parameter(Mandatory)][string]$Title)

        [void]$calls.Add([pscustomobject]@{
            Name = 'WriteSection'
            Arguments = @{ Title = $Title }
        })
        [void]$records.Add([pscustomobject]@{
            Level = 'Section'
            Message = $Title
            Data = $null
            Depth = $null
        })
    }.GetNewClosure()

    return [pscustomobject]@{
        Calls = $calls
        Records = $records
        WriteInfo = $writeInfo
        WriteWarning = $writeWarning
        WriteObject = $writeObject
        WriteSection = $writeSection
    }
}

function New-TestFileSystemService {
    param(
        [bool]$PathUnderDirectoryResult = $true,
        [bool]$RemoveFileIfExistsResult = $false,
        [bool]$CreateDirectories = $false,
        [bool]$RemoveFiles = $false
    )

    $calls = New-TestCallList

    $initializeOutputDirectory = {
        param(
            [Parameter(Mandatory)][string]$Directory,
            [string]$Purpose = '出力'
        )

        [void]$calls.Add([pscustomobject]@{
            Name = 'InitializeOutputDirectory'
            Arguments = @{ Directory = $Directory; Purpose = $Purpose }
        })

        if ($CreateDirectories -and -not (Test-Path -LiteralPath $Directory)) {
            New-Item -ItemType Directory -Path $Directory -Force | Out-Null
        }

        return $Directory
    }.GetNewClosure()

    $clearDirectory = {
        param(
            [Parameter(Mandatory)][string]$Directory,
            [string]$Purpose = '作業'
        )

        [void]$calls.Add([pscustomobject]@{
            Name = 'ClearDirectory'
            Arguments = @{ Directory = $Directory; Purpose = $Purpose }
        })

        if ($CreateDirectories -and -not (Test-Path -LiteralPath $Directory)) {
            New-Item -ItemType Directory -Path $Directory -Force | Out-Null
        }
    }.GetNewClosure()

    $assertSafeDirectory = {
        param(
            [Parameter(Mandatory)][string]$Directory,
            [string]$Purpose = '作業'
        )

        [void]$calls.Add([pscustomobject]@{
            Name = 'AssertSafeDirectory'
            Arguments = @{ Directory = $Directory; Purpose = $Purpose }
        })

        if ($CreateDirectories -and -not (Test-Path -LiteralPath $Directory)) {
            New-Item -ItemType Directory -Path $Directory -Force | Out-Null
        }

        return $Directory
    }.GetNewClosure()

    $testPathUnderDirectory = {
        param(
            [Parameter(Mandatory)][string]$Path,
            [Parameter(Mandatory)][string]$Directory
        )

        [void]$calls.Add([pscustomobject]@{
            Name = 'TestPathUnderDirectory'
            Arguments = @{ Path = $Path; Directory = $Directory }
        })

        return $PathUnderDirectoryResult
    }.GetNewClosure()

    $removeFileIfExists = {
        param(
            [Parameter(Mandatory)][string]$Path,
            [Parameter(Mandatory)][string]$AllowedDirectory
        )

        [void]$calls.Add([pscustomobject]@{
            Name = 'RemoveFileIfExists'
            Arguments = @{ Path = $Path; AllowedDirectory = $AllowedDirectory }
        })

        if ($RemoveFiles) {
            if (Test-Path -LiteralPath $Path) {
                Remove-Item -LiteralPath $Path -Force
                return $true
            }

            return $false
        }

        return $RemoveFileIfExistsResult
    }.GetNewClosure()

    return [pscustomobject]@{
        Calls = $calls
        InitializeOutputDirectory = $initializeOutputDirectory
        ClearDirectory = $clearDirectory
        AssertSafeDirectory = $assertSafeDirectory
        TestPathUnderDirectory = $testPathUnderDirectory
        RemoveFileIfExists = $removeFileIfExists
    }
}

function New-TestBrowserService {
    param([AllowNull()][object]$Page = $null)

    $calls = New-TestCallList
    if (-not $Page) {
        $Page = [pscustomobject]@{ CdpSession = $null }
    }

    $openPage = {
        param(
            [Parameter(Mandatory)][string]$DebuggerUrl,
            [int]$ConnectTimeoutSeconds = 15,
            [int]$CommandTimeoutSeconds = 30
        )

        [void]$calls.Add([pscustomobject]@{
            Name = 'OpenPage'
            Arguments = @{
                DebuggerUrl = $DebuggerUrl
                ConnectTimeoutSeconds = $ConnectTimeoutSeconds
                CommandTimeoutSeconds = $CommandTimeoutSeconds
            }
        })

        return $Page
    }.GetNewClosure()

    $openPageMatchingIdentity = {
        param(
            [Parameter(Mandatory)][string]$DebuggerUrl,
            [int]$ConnectTimeoutSeconds = 15,
            [int]$CommandTimeoutSeconds = 30,
            [Parameter(Mandatory)][scriptblock]$PageIdentityMatcher
        )

        [void]$calls.Add([pscustomobject]@{
            Name = 'OpenPageMatchingIdentity'
            Arguments = @{
                DebuggerUrl = $DebuggerUrl
                ConnectTimeoutSeconds = $ConnectTimeoutSeconds
                CommandTimeoutSeconds = $CommandTimeoutSeconds
                PageIdentityMatcher = $PageIdentityMatcher
            }
        })

        return $Page
    }.GetNewClosure()

    $setDownloadDirectory = {
        param([Parameter(Mandatory)][string]$Directory)

        [void]$calls.Add([pscustomobject]@{
            Name = 'SetDownloadDirectory'
            Arguments = @{ Directory = $Directory }
        })
    }.GetNewClosure()

    return [pscustomobject]@{
        Calls = $calls
        OpenPage = $openPage
        OpenPageMatchingIdentity = $openPageMatchingIdentity
        SetDownloadDirectory = $setDownloadDirectory
    }
}


function New-TestTimingService {
    $calls = New-TestCallList
    $nowValue = [datetime]'2026-01-02T03:04:05'

    $now = {
        [void]$calls.Add([pscustomobject]@{
            Name = 'Now'
            Arguments = @{}
        })
        return $nowValue
    }.GetNewClosure()

    $timestampText = {
        [void]$calls.Add([pscustomobject]@{
            Name = 'TimestampText'
            Arguments = @{}
        })
        return $nowValue.ToString('yyyy-MM-dd HH:mm:ss')
    }.GetNewClosure()

    $sleepMilliseconds = {
        param([int]$Milliseconds)
        [void]$calls.Add([pscustomobject]@{
            Name = 'SleepMilliseconds'
            Arguments = @{ Milliseconds = $Milliseconds }
        })
    }.GetNewClosure()

    return [pscustomobject]@{
        Calls = $calls
        Now = $now
        TimestampText = $timestampText
        SleepMilliseconds = $sleepMilliseconds
    }
}

function New-TestWorkflowService {
    param([AllowNull()][object]$ScrollableListResult = $null)

    $calls = New-TestCallList
    if (-not $ScrollableListResult) {
        $ScrollableListResult = [pscustomobject]@{
            ProcessedCount = 0
            FailureResults = @()
            SeenKeys = @{}
        }
    }

    $invokeScrollableList = {
        param(
            [Parameter(Mandatory)][int]$TotalCount,
            [Parameter(Mandatory)]$Operations,
            [object]$Logger = $null,
            [int]$MaxScanLoops = 500,
            [int]$SameScrollLimit = 2,
            [string]$EmptyRowsMessage = '表示行を取得できませんでした。'
        )

        [void]$calls.Add([pscustomobject]@{
            Name = 'InvokeScrollableList'
            Arguments = @{
                TotalCount = $TotalCount
                Operations = $Operations
                Logger = $Logger
                MaxScanLoops = $MaxScanLoops
                SameScrollLimit = $SameScrollLimit
                EmptyRowsMessage = $EmptyRowsMessage
            }
        })

        return $ScrollableListResult
    }.GetNewClosure()

    return [pscustomobject]@{
        Calls = $calls
        InvokeScrollableList = $invokeScrollableList
    }
}

function New-TestFoundationContext {
    param(
        [string]$RootPath = $TestDrive,
        [string]$RunId = 'unit-test',
        [string]$JobName = 'UnitTest',
        [hashtable]$Config = @{ Common = @{}; Jobs = @{} },
        [hashtable]$CommonSettings = @{},
        [hashtable]$JobSettings = @{},
        [AllowNull()][object]$JobDefinition = $null,
        [AllowNull()][object]$Logger = $null,
        [AllowNull()][object]$LoggerPort = $null,
        [AllowNull()][object]$FileSystemService = $null,
        [AllowNull()][object]$BrowserService = $null,
        [AllowNull()][object]$WorkflowService = $null,
        [AllowNull()][object]$TimingService = $null,
        [AllowNull()][object]$Page = $null
    )

    if (-not $Logger) {
        $Logger = [pscustomobject]@{ Console = $false; File = $false; Level = 'Debug'; RunId = $RunId }
    }
    if (-not $LoggerPort) { $LoggerPort = New-TestLoggerPort }
    if (-not $FileSystemService) { $FileSystemService = New-TestFileSystemService }
    if (-not $BrowserService) { $BrowserService = New-TestBrowserService -Page $Page }
    if (-not $WorkflowService) { $WorkflowService = New-TestWorkflowService }
    if (-not $TimingService) { $TimingService = New-TestTimingService }

    return [pscustomobject]@{
        RootPath = $RootPath
        RunId = $RunId
        JobName = $JobName
        JobDefinition = $JobDefinition
        Config = $Config
        CommonSettings = $CommonSettings
        JobSettings = $JobSettings
        Logger = $Logger
        Services = [pscustomobject]@{
            Logger = $LoggerPort
            FileSystem = $FileSystemService
            Browser = $BrowserService
            Workflow = $WorkflowService
            Timing = $TimingService
        }
        Page = $Page
    }
}
