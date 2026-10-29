$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

function Assert-LastMonthInstallExtractJobSettings {
    param([Parameter(Mandatory)]$Settings)

    foreach ($key in @('TargetDirectory','OutputCsvFileName')) {
        $value = Get-LastMonthInstallExtractSettingValue -Settings $Settings -Name $key -Default ''
        if ([string]::IsNullOrWhiteSpace([string]$value)) {
            throw "LastMonthInstallExtract設定に必須キーがありません: Jobs.LastMonthInstallExtract.$key"
        }
    }
}

function Initialize-LastMonthInstallExtractOutputDirectory {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$Dependencies
    )

    $targetDirectory = Get-LastMonthInstallExtractTargetDirectoryFromSettings -Settings $Context.JobSettings
    $initializeOutputDirectory = Get-LastMonthInstallExtractCallbackScriptBlock -Callbacks $Dependencies.Output -Name 'InitializeOutputDirectory'
    $initializeOutputDirectory.Invoke($targetDirectory) | Out-Null
}

function New-LastMonthInstallExtractJobDateRange {
    param([Parameter(Mandatory)]$Dependencies)

    $now = Get-LastMonthInstallExtractCallbackScriptBlock -Callbacks $Dependencies.Timing -Name 'Now'
    return New-LastMonthInstallExtractMonthlyDateRange -Now (& $now)
}

function Export-LastMonthInstallExtractJobResults {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$WorkflowResult,
        [Parameter(Mandatory)]$Dependencies
    )

    $settings = $Context.JobSettings
    $targetDirectory = Get-LastMonthInstallExtractTargetDirectoryFromSettings -Settings $settings
    $outputCsvFileName = Get-LastMonthInstallExtractOutputCsvFileNameFromSettings -Settings $settings
    $failureCsvFileName = Get-LastMonthInstallExtractFailureCsvFileNameFromSettings -Settings $settings
    $outputPath = Join-Path $targetDirectory $outputCsvFileName
    $failurePath = Join-Path $targetDirectory $failureCsvFileName

    $exportInstallationCsv = Get-LastMonthInstallExtractCallbackScriptBlock -Callbacks $Dependencies.Output -Name 'ExportInstallationCsv'
    $exportFailureCsv = Get-LastMonthInstallExtractCallbackScriptBlock -Callbacks $Dependencies.Output -Name 'ExportFailureCsv'

    $installationCsv = & $exportInstallationCsv -Rows @($WorkflowResult.InstallationRows) -Path $outputPath
    $failureCsv = & $exportFailureCsv -FailureRows @($WorkflowResult.FailureRows) -Path $failurePath

    return [pscustomobject]@{
        InstallationCsv = $installationCsv
        FailureCsv = $failureCsv
        OutputPath = $outputPath
        FailurePath = $failurePath
    }
}

function Write-LastMonthInstallExtractWorkflowSummary {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$DateRange,
        [Parameter(Mandatory)]$WorkflowResult,
        [Parameter(Mandatory)]$ExportResult,
        [Parameter(Mandatory)]$Dependencies
    )

    $logger = $Dependencies.Logger
    $writeSection = Get-LastMonthInstallExtractCallbackScriptBlock -Callbacks $logger -Name 'WriteSection'
    $writeInfo = Get-LastMonthInstallExtractCallbackScriptBlock -Callbacks $logger -Name 'WriteInfo'
    $writeWarning = Get-LastMonthInstallExtractCallbackScriptBlock -Callbacks $logger -Name 'WriteWarning'
    $targetDirectory = Get-LastMonthInstallExtractTargetDirectoryFromSettings -Settings $Context.JobSettings

    & $writeSection '処理結果'
    & $writeInfo "対象ディレクトリ: $targetDirectory"
    & $writeInfo "出力CSV: $($ExportResult.OutputPath)"
    & $writeInfo "現在日付: $($DateRange.Today.ToString('yyyy-MM-dd'))"
    & $writeInfo "先月判定範囲: $($DateRange.StartInclusive.ToString('yyyy-MM-dd')) 以上、$($DateRange.EndExclusive.ToString('yyyy-MM-dd')) 未満"
    & $writeInfo "入力CSV数: $($WorkflowResult.InputFileCount) 件"
    & $writeInfo "処理CSV数: $($WorkflowResult.ProcessedFileCount) 件"
    & $writeInfo "スキップCSV数: $($WorkflowResult.SkippedFileCount) 件"
    & $writeInfo "読み取り行数: $($WorkflowResult.ReadRowCount) 行"
    & $writeInfo "出力件数: $($WorkflowResult.InstallationRows.Count) 件"

    if ($WorkflowResult.FailureRows.Count -gt 0) {
        & $writeWarning "失敗/スキップ一覧CSVを出力しました: $($ExportResult.FailurePath) / 件数=$($WorkflowResult.FailureRows.Count)"
    }
    else {
        & $writeInfo "失敗/スキップ一覧CSVはありません。既存ファイルがあれば削除済みです: $($ExportResult.FailurePath)"
    }
}

function Invoke-LastMonthInstallExtractJob {
    param(
        [Parameter(Mandatory)]$Context,
        [AllowNull()]$Dependencies = $null
    )

    Assert-LastMonthInstallExtractJobSettings -Settings $Context.JobSettings

    $resolvedDependencies = Resolve-LastMonthInstallExtractJobDependencies -Context $Context -Dependencies $Dependencies
    Initialize-LastMonthInstallExtractOutputDirectory -Context $Context -Dependencies $resolvedDependencies

    $dateRange = New-LastMonthInstallExtractJobDateRange -Dependencies $resolvedDependencies

    $workflowResult = Invoke-LastMonthInstallExtractInstallationWorkflow `
        -Context $Context `
        -DateRange $dateRange `
        -Dependencies $resolvedDependencies

    $exportResult = Export-LastMonthInstallExtractJobResults `
        -Context $Context `
        -WorkflowResult $workflowResult `
        -Dependencies $resolvedDependencies

    Write-LastMonthInstallExtractWorkflowSummary `
        -Context $Context `
        -DateRange $dateRange `
        -WorkflowResult $workflowResult `
        -ExportResult $exportResult `
        -Dependencies $resolvedDependencies

    return [pscustomobject]@{
        DateRange = $dateRange
        WorkflowResult = $workflowResult
        ExportResult = $exportResult
    }
}
