$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

function Get-LastMonthInstallExtractDependencyProperty {
    param(
        [AllowNull()]$Object,
        [Parameter(Mandatory)][string]$Name
    )

    if (-not $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if (-not $property) { return $null }
    return $property.Value
}

function Get-LastMonthInstallExtractCallbackScriptBlock {
    param(
        [AllowNull()]$Callbacks,
        [Parameter(Mandatory)][string]$Name
    )

    $value = Get-LastMonthInstallExtractDependencyProperty -Object $Callbacks -Name $Name
    if (-not ($value -is [scriptblock])) {
        throw "LastMonthInstallExtract callback '$Name' が scriptblock として定義されていません。"
    }

    return $value
}

function New-LastMonthInstallExtractLoggerPort {
    param([Parameter(Mandatory)]$Context)

    $services = Get-LastMonthInstallExtractDependencyProperty -Object $Context -Name 'Services'
    $serviceLogger = Get-LastMonthInstallExtractDependencyProperty -Object $services -Name 'Logger'
    if ((Get-LastMonthInstallExtractDependencyProperty -Object $serviceLogger -Name 'WriteInfo') -is [scriptblock] -and
        (Get-LastMonthInstallExtractDependencyProperty -Object $serviceLogger -Name 'WriteWarning') -is [scriptblock] -and
        (Get-LastMonthInstallExtractDependencyProperty -Object $serviceLogger -Name 'WriteSection') -is [scriptblock]) {
        return $serviceLogger
    }

    $logger = $Context.Logger
    $writeFoundationLogCommand = Get-Command -Name Write-FoundationLog -CommandType Function -ErrorAction Stop
    $writeFoundationSectionCommand = Get-Command -Name Write-FoundationSection -CommandType Function -ErrorAction Stop

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

function New-LastMonthInstallExtractInputPort {
    $getFilesCommand = Get-Command -Name Get-LastMonthInstallExtractTargetCsvFileInfos -CommandType Function -ErrorAction Stop
    $readBytesCommand = Get-Command -Name Read-LastMonthInstallExtractFileBytes -CommandType Function -ErrorAction Stop

    return [pscustomobject]@{
        GetTargetCsvFiles = {
            param(
                [Parameter(Mandatory)][string]$TargetDirectory,
                [Parameter(Mandatory)][string]$OutputCsvFileName,
                [AllowEmptyString()][string]$FailureCsvFileName = ''
            )
            @(& $getFilesCommand -TargetDirectory $TargetDirectory -OutputCsvFileName $OutputCsvFileName -FailureCsvFileName $FailureCsvFileName)
        }.GetNewClosure()
        ReadAllBytes = {
            param([Parameter(Mandatory)][string]$Path)
            & $readBytesCommand -Path $Path
        }.GetNewClosure()
    }
}

function New-LastMonthInstallExtractFileSystemPort {
    param([Parameter(Mandatory)]$Context)

    $services = Get-LastMonthInstallExtractDependencyProperty -Object $Context -Name 'Services'
    $fileSystem = Get-LastMonthInstallExtractDependencyProperty -Object $services -Name 'FileSystem'

    foreach ($name in @('InitializeOutputDirectory','AssertSafeDirectory','TestPathUnderDirectory','RemoveFileIfExists')) {
        if (-not ((Get-LastMonthInstallExtractDependencyProperty -Object $fileSystem -Name $name) -is [scriptblock])) {
            throw "LastMonthInstallExtract FileSystem service '$name' が scriptblock として定義されていません。"
        }
    }

    return $fileSystem
}

function New-LastMonthInstallExtractOutputPort {
    param([Parameter(Mandatory)]$Context)

    $fileSystem = New-LastMonthInstallExtractFileSystemPort -Context $Context
    $exportInstallationCommand = Get-Command -Name Export-LastMonthInstallExtractInstallationCsv -CommandType Function -ErrorAction Stop
    $exportFailureCommand = Get-Command -Name Export-LastMonthInstallExtractFailureCsv -CommandType Function -ErrorAction Stop

    return [pscustomobject]@{
        InitializeOutputDirectory = {
            param([Parameter(Mandatory)][string]$Directory)
            $fileSystem.InitializeOutputDirectory.Invoke($Directory, 'アプリ出力')
        }.GetNewClosure()
        ExportInstallationCsv = {
            param(
                [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Rows,
                [Parameter(Mandatory)][string]$Path
            )
            & $exportInstallationCommand -Rows $Rows -Path $Path -FileSystemService $fileSystem
        }.GetNewClosure()
        ExportFailureCsv = {
            param(
                [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$FailureRows,
                [Parameter(Mandatory)][string]$Path
            )
            & $exportFailureCommand -FailureRows $FailureRows -Path $Path -FileSystemService $fileSystem
        }.GetNewClosure()
    }
}

function New-LastMonthInstallExtractTimingPort {
    param([Parameter(Mandatory)]$Context)

    $services = Get-LastMonthInstallExtractDependencyProperty -Object $Context -Name 'Services'
    $timing = Get-LastMonthInstallExtractDependencyProperty -Object $services -Name 'Timing'
    if ((Get-LastMonthInstallExtractDependencyProperty -Object $timing -Name 'Now') -is [scriptblock] -and
        (Get-LastMonthInstallExtractDependencyProperty -Object $timing -Name 'TimestampText') -is [scriptblock]) {
        return $timing
    }

    return [pscustomobject]@{
        Now = { Get-Date }
        TimestampText = { (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') }
    }
}

function Assert-LastMonthInstallExtractInstallationWorkflowDependencies {
    param([Parameter(Mandatory)]$Dependencies)

    foreach ($name in @('GetTargetCsvFiles','ReadAllBytes')) {
        [void](Get-LastMonthInstallExtractCallbackScriptBlock -Callbacks $Dependencies.Input -Name $name)
    }

    foreach ($name in @('WriteInfo','WriteWarning')) {
        [void](Get-LastMonthInstallExtractCallbackScriptBlock -Callbacks $Dependencies.Logger -Name $name)
    }

    [void](Get-LastMonthInstallExtractCallbackScriptBlock -Callbacks $Dependencies.Timing -Name 'TimestampText')
}

function Assert-LastMonthInstallExtractJobDependencies {
    param([Parameter(Mandatory)]$Dependencies)

    Assert-LastMonthInstallExtractInstallationWorkflowDependencies -Dependencies $Dependencies

    foreach ($name in @('InitializeOutputDirectory','ExportInstallationCsv','ExportFailureCsv')) {
        [void](Get-LastMonthInstallExtractCallbackScriptBlock -Callbacks $Dependencies.Output -Name $name)
    }

    [void](Get-LastMonthInstallExtractCallbackScriptBlock -Callbacks $Dependencies.Logger -Name 'WriteSection')
    [void](Get-LastMonthInstallExtractCallbackScriptBlock -Callbacks $Dependencies.Timing -Name 'Now')
}

function Resolve-LastMonthInstallExtractInstallationWorkflowDependencies {
    param(
        [Parameter(Mandatory)]$Context,
        [AllowNull()]$Dependencies = $null
    )

    if (-not $Dependencies) { $Dependencies = [pscustomobject]@{} }

    $input = Get-LastMonthInstallExtractDependencyProperty -Object $Dependencies -Name 'Input'
    if (-not $input) { $input = New-LastMonthInstallExtractInputPort }

    $logger = Get-LastMonthInstallExtractDependencyProperty -Object $Dependencies -Name 'Logger'
    if (-not $logger) { $logger = New-LastMonthInstallExtractLoggerPort -Context $Context }

    $timing = Get-LastMonthInstallExtractDependencyProperty -Object $Dependencies -Name 'Timing'
    if (-not $timing) { $timing = New-LastMonthInstallExtractTimingPort -Context $Context }

    $resolved = [pscustomobject]@{
        Input = $input
        Logger = $logger
        Timing = $timing
    }

    Assert-LastMonthInstallExtractInstallationWorkflowDependencies -Dependencies $resolved
    return $resolved
}

function Resolve-LastMonthInstallExtractJobDependencies {
    param(
        [Parameter(Mandatory)]$Context,
        [AllowNull()]$Dependencies = $null
    )

    if (-not $Dependencies) { $Dependencies = [pscustomobject]@{} }

    $workflowDependencies = Resolve-LastMonthInstallExtractInstallationWorkflowDependencies -Context $Context -Dependencies $Dependencies

    $output = Get-LastMonthInstallExtractDependencyProperty -Object $Dependencies -Name 'Output'
    if (-not $output) { $output = New-LastMonthInstallExtractOutputPort -Context $Context }

    $resolved = [pscustomobject]@{
        Input = $workflowDependencies.Input
        Output = $output
        Logger = $workflowDependencies.Logger
        Timing = $workflowDependencies.Timing
    }

    Assert-LastMonthInstallExtractJobDependencies -Dependencies $resolved
    return $resolved
}

