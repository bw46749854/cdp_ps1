$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。
# 薄いComposite Job専用モジュール。Feature内部処理、DOM/CDP操作、CSV解析は持たない。

$foundationModulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Foundation\Foundation.psm1'
if (-not (Test-Path -LiteralPath $foundationModulePath)) { throw "Foundationモジュールが見つかりません: $foundationModulePath" }
Import-Module -Name $foundationModulePath -DisableNameChecking

function Get-CompositeCallbackScriptBlock {
    param(
        [Parameter(Mandatory)]$Callbacks,
        [Parameter(Mandatory)][string]$Name
    )

    if ($null -eq $Callbacks) {
        throw "CompositeJobs dependency が指定されていません: $Name"
    }

    $property = $Callbacks.PSObject.Properties[$Name]
    if ($null -eq $property -or -not ($property.Value -is [scriptblock])) {
        throw "CompositeJobs dependency に必要な scriptblock がありません: $Name"
    }

    return $property.Value
}

function New-CompositeFoundationDependencies {

    return [pscustomobject]@{
        Foundation = [pscustomobject]@{
            InvokeJob = {
                param(
                    [Parameter(Mandatory)][string]$RootPath,
                    [Parameter(Mandatory)][string]$ConfigPath,
                    [Parameter(Mandatory)][string]$JobName,
                    [AllowEmptyString()][string]$JobRegistryPath = '',
                    [AllowNull()][hashtable]$JobSettingsOverrides = $null
                )

                $invokeArgs = @{
                    RootPath = $RootPath
                    ConfigPath = $ConfigPath
                    JobName = $JobName
                    JobRegistryPath = $JobRegistryPath
                }

                if ($JobSettingsOverrides) {
                    $invokeArgs.JobSettingsOverrides = $JobSettingsOverrides
                }

                return Invoke-FoundationEntrypoint @invokeArgs
            }.GetNewClosure()
        }
        FileSystem = [pscustomobject]@{
            TestPath = {
                param([Parameter(Mandatory)][string]$Path)
                return (Test-Path -LiteralPath $Path)
            }.GetNewClosure()
            InitializeDirectory = {
                param(
                    [Parameter(Mandatory)][string]$Directory,
                    [string]$Purpose = 'CompositeJob'
                )
                if ([string]::IsNullOrWhiteSpace($Directory)) {
                    throw "CompositeJob のディレクトリが空です: $Purpose"
                }
                if (-not (Test-Path -LiteralPath $Directory)) {
                    New-Item -ItemType Directory -Path $Directory -Force | Out-Null
                }
                return $Directory
            }.GetNewClosure()
            GetFiles = {
                param(
                    [Parameter(Mandatory)][string]$Directory,
                    [Parameter(Mandatory)][string]$Filter
                )
                return @(Get-ChildItem -LiteralPath $Directory -File -Filter $Filter -ErrorAction Stop)
            }.GetNewClosure()
        }
        Timing = [pscustomobject]@{
            RunTimestamp = {
                return (Get-Date).ToString('yyyyMMdd_HHmmss')
            }.GetNewClosure()
        }
    }
}

function Resolve-CompositeJobDependencies {
    param(
        [Parameter(Mandatory)]$Context,
        [AllowNull()]$Dependencies = $null
    )

    if ($null -ne $Dependencies) {
        return $Dependencies
    }

    return New-CompositeFoundationDependencies
}

function Get-CompositeDefaultConfigPath {
    param([Parameter(Mandatory)][string]$RootPath)

    return (Join-Path (Join-Path $RootPath 'config') 'foundation.config.psd1')
}

function Get-CompositeDefaultJobRegistryPath {
    param([Parameter(Mandatory)][string]$RootPath)

    return (Join-Path (Join-Path $RootPath 'config') 'foundation.jobs.psd1')
}

function Get-CompositeConfigPath {
    param([Parameter(Mandatory)]$Context)

    if ($Context.PSObject.Properties['ConfigPath'] -and -not [string]::IsNullOrWhiteSpace([string]$Context.ConfigPath)) {
        return [string]$Context.ConfigPath
    }

    return Get-CompositeDefaultConfigPath -RootPath ([string]$Context.RootPath)
}

function Get-CompositeJobRegistryPath {
    param([Parameter(Mandatory)]$Context)

    if ($Context.PSObject.Properties['JobRegistryPath'] -and -not [string]::IsNullOrWhiteSpace([string]$Context.JobRegistryPath)) {
        return [string]$Context.JobRegistryPath
    }

    return Get-CompositeDefaultJobRegistryPath -RootPath ([string]$Context.RootPath)
}

function Invoke-CompositeChildJob {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$Dependencies,
        [Parameter(Mandatory)][string]$JobName,
        [AllowNull()][hashtable]$JobSettingsOverrides = $null
    )

    $invokeJob = Get-CompositeCallbackScriptBlock -Callbacks $Dependencies.Foundation -Name 'InvokeJob'
    $invokeArgs = @{
        RootPath = [string]$Context.RootPath
        ConfigPath = (Get-CompositeConfigPath -Context $Context)
        JobName = $JobName
        JobRegistryPath = (Get-CompositeJobRegistryPath -Context $Context)
    }

    if ($JobSettingsOverrides) {
        $invokeArgs.JobSettingsOverrides = $JobSettingsOverrides
    }

    return & $invokeJob @invokeArgs
}

function Assert-CompositeSucceededWhenResultHasOk {
    param(
        [AllowNull()]$Result = $null,
        [Parameter(Mandatory)][string]$JobName
    )

    foreach ($item in @($Result | Where-Object { $null -ne $_ })) {
        if ($item.PSObject.Properties['Ok'] -and $item.Ok -ne $true) {
            throw "$JobName が失敗結果を返しました。"
        }
    }
}

function Get-CompositeSingleFeatureResult {
    param(
        [AllowNull()]$Result = $null,
        [Parameter(Mandatory)][string]$Feature
    )

    $items = @($Result | Where-Object {
        $null -ne $_ -and $_.PSObject.Properties['Feature'] -and [string]$_.Feature -eq $Feature
    })

    if ($items.Count -ne 1) {
        throw "$Feature の結果を一意に取得できませんでした。ResultCount=$($items.Count)"
    }

    return $items[0]
}

function Assert-DeviceListExportResultForComposite {
    param(
        [Parameter(Mandatory)]$Result,
        [Parameter(Mandatory)]$Dependencies
    )

    if (-not $Result.PSObject.Properties['Ok'] -or $Result.Ok -ne $true) {
        throw 'DeviceListExport が成功結果を返しませんでした。'
    }

    if (-not $Result.PSObject.Properties['ExportedCsvPath'] -or [string]::IsNullOrWhiteSpace([string]$Result.ExportedCsvPath)) {
        throw 'DeviceListExport の ExportedCsvPath が空です。'
    }

    $exportedCsvPath = [string]$Result.ExportedCsvPath
    $testPath = Get-CompositeCallbackScriptBlock -Callbacks $Dependencies.FileSystem -Name 'TestPath'
    if (-not (& $testPath $exportedCsvPath)) {
        throw "DeviceListExport のリネーム済みCSVが見つかりません: $exportedCsvPath"
    }

    return $exportedCsvPath
}

function Get-CompositeSettingValue {
    param(
        [Parameter(Mandatory)]$Settings,
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()]$Default = $null
    )

    if ($Settings -and $Settings.ContainsKey($Name)) {
        return $Settings[$Name]
    }

    return $Default
}

function Get-MonthlyInstallReportRunRootDirectory {
    param([Parameter(Mandatory)]$Context)

    $value = Get-CompositeSettingValue -Settings $Context.JobSettings -Name 'RunRootDirectory' -Default ''
    if ([string]::IsNullOrWhiteSpace([string]$value)) {
        throw 'MonthlyInstallReport設定に必須キーがありません: Jobs.MonthlyInstallReport.RunRootDirectory'
    }

    return [string]$value
}

function New-MonthlyInstallReportRunDirectories {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$Dependencies
    )

    $runTimestamp = & (Get-CompositeCallbackScriptBlock -Callbacks $Dependencies.Timing -Name 'RunTimestamp')
    if ([string]::IsNullOrWhiteSpace([string]$runTimestamp) -or [string]$runTimestamp -notmatch '^\d{8}_\d{6}$') {
        throw "CompositeJob timestamp が yyyyMMdd_HHmmss 形式ではありません: $runTimestamp"
    }

    $runRootDirectory = Get-MonthlyInstallReportRunRootDirectory -Context $Context
    $runDirectory = Join-Path $runRootDirectory ([string]$runTimestamp)
    $installedAppExportTempDirectory = Join-Path $runDirectory 'installed_app_export_tmp'
    $installedAppExportDownloadDirectory = Join-Path $runDirectory 'installed_app_export_downloads'

    $initializeDirectory = Get-CompositeCallbackScriptBlock -Callbacks $Dependencies.FileSystem -Name 'InitializeDirectory'
    & $initializeDirectory $runDirectory 'InstalledAppExport→LastMonthInstallExtract実行ディレクトリ' | Out-Null
    & $initializeDirectory $installedAppExportTempDirectory 'InstalledAppExport一時ディレクトリ' | Out-Null
    & $initializeDirectory $installedAppExportDownloadDirectory 'InstalledAppExport成果物ディレクトリ' | Out-Null

    return [pscustomobject]@{
        RunTimestamp = [string]$runTimestamp
        RunDirectory = $runDirectory
        InstalledAppExportTempDirectory = $installedAppExportTempDirectory
        InstalledAppExportDownloadDirectory = $installedAppExportDownloadDirectory
    }
}

function Get-InstalledAppExportExportArtifactFileFilter {
    param([Parameter(Mandatory)]$Context)

    $prefix = ''
    if ($Context.Config -and $Context.Config.Jobs -and $Context.Config.Jobs.InstalledAppExport -and $Context.Config.Jobs.InstalledAppExport.ContainsKey('DownloadFilePrefix')) {
        $prefix = [string]$Context.Config.Jobs.InstalledAppExport.DownloadFilePrefix
    }

    if ([string]::IsNullOrWhiteSpace($prefix)) {
        throw 'InstalledAppExport.DownloadFilePrefix が空のため、InstalledAppExport成果物CSVの存在確認ができません。'
    }

    return "$prefix*.csv"
}

function Assert-InstalledAppExportExportArtifactsExist {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$Dependencies,
        [Parameter(Mandatory)][string]$InstalledAppExportDownloadDirectory
    )

    $filter = Get-InstalledAppExportExportArtifactFileFilter -Context $Context
    $getFiles = Get-CompositeCallbackScriptBlock -Callbacks $Dependencies.FileSystem -Name 'GetFiles'
    $files = @(& $getFiles $InstalledAppExportDownloadDirectory $filter)

    if ($files.Count -eq 0) {
        throw "InstalledAppExport の成果物CSVが存在しません。Directory=$InstalledAppExportDownloadDirectory Filter=$filter"
    }

    return @($files | ForEach-Object { $_.FullName })
}

function Invoke-WeeklyScanTargetSyncJob {
    param(
        [Parameter(Mandatory)]$Context,
        [AllowNull()]$Dependencies = $null
    )

    $resolvedDependencies = Resolve-CompositeJobDependencies -Context $Context -Dependencies $Dependencies

    $deviceListExportRawResult = Invoke-CompositeChildJob `
        -Context $Context `
        -Dependencies $resolvedDependencies `
        -JobName 'DeviceListExport'

    $deviceListExportResult = Get-CompositeSingleFeatureResult -Result $deviceListExportRawResult -Feature 'DeviceListExport'
    $exportedCsvPath = Assert-DeviceListExportResultForComposite `
        -Result $deviceListExportResult `
        -Dependencies $resolvedDependencies

    $scanTargetSyncResult = Invoke-CompositeChildJob `
        -Context $Context `
        -Dependencies $resolvedDependencies `
        -JobName 'ScanTargetSync' `
        -JobSettingsOverrides @{ InputCsvPath = $exportedCsvPath }

    Assert-CompositeSucceededWhenResultHasOk -Result $scanTargetSyncResult -JobName 'ScanTargetSync'

    return [pscustomobject]@{
        Ok = $true
        Feature = 'WeeklyScanTargetSync'
        DeviceListExport = $deviceListExportResult
        ScanTargetSync = $scanTargetSyncResult
        InputCsvPath = $exportedCsvPath
    }
}

function Invoke-MonthlyInstallReportJob {
    param(
        [Parameter(Mandatory)]$Context,
        [AllowNull()]$Dependencies = $null
    )

    $resolvedDependencies = Resolve-CompositeJobDependencies -Context $Context -Dependencies $Dependencies
    $directories = New-MonthlyInstallReportRunDirectories `
        -Context $Context `
        -Dependencies $resolvedDependencies

    $installedAppExportOverrides = @{
        TempDirectory = $directories.InstalledAppExportTempDirectory
        DownloadDirectory = $directories.InstalledAppExportDownloadDirectory
    }

    $installedAppExportResult = Invoke-CompositeChildJob `
        -Context $Context `
        -Dependencies $resolvedDependencies `
        -JobName 'InstalledAppExport' `
        -JobSettingsOverrides $installedAppExportOverrides

    Assert-CompositeSucceededWhenResultHasOk -Result $installedAppExportResult -JobName 'InstalledAppExport'

    $installedAppExportExportedCsvPaths = Assert-InstalledAppExportExportArtifactsExist `
        -Context $Context `
        -Dependencies $resolvedDependencies `
        -InstalledAppExportDownloadDirectory $directories.InstalledAppExportDownloadDirectory

    $lastMonthInstallExtractOverrides = @{
        TargetDirectory = $directories.InstalledAppExportDownloadDirectory
    }

    $lastMonthInstallExtractResult = Invoke-CompositeChildJob `
        -Context $Context `
        -Dependencies $resolvedDependencies `
        -JobName 'LastMonthInstallExtract' `
        -JobSettingsOverrides $lastMonthInstallExtractOverrides

    Assert-CompositeSucceededWhenResultHasOk -Result $lastMonthInstallExtractResult -JobName 'LastMonthInstallExtract'

    return [pscustomobject]@{
        Ok = $true
        Feature = 'MonthlyInstallReport'
        RunTimestamp = $directories.RunTimestamp
        RunDirectory = $directories.RunDirectory
        InstalledAppExportTempDirectory = $directories.InstalledAppExportTempDirectory
        InstalledAppExportDownloadDirectory = $directories.InstalledAppExportDownloadDirectory
        InstalledAppExportExportedCsvPaths = @($installedAppExportExportedCsvPaths)
        InstalledAppExport = $installedAppExportResult
        LastMonthInstallExtract = $lastMonthInstallExtractResult
        TargetDirectory = $directories.InstalledAppExportDownloadDirectory
    }
}

Export-ModuleMember -Function @(
    'Invoke-WeeklyScanTargetSyncJob',
    'Invoke-MonthlyInstallReportJob'
)
