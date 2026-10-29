$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

function Get-LastMonthInstallExtractSettingValue {
    param(
        [Parameter(Mandatory)]$Settings,
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()]$Default = $null
    )

    if ($Settings -is [hashtable] -and $Settings.ContainsKey($Name)) {
        return $Settings[$Name]
    }

    $property = $Settings.PSObject.Properties[$Name]
    if ($property) {
        return $property.Value
    }

    return $Default
}

function Get-LastMonthInstallExtractRequiredHeadersFromSettings {
    param([Parameter(Mandatory)]$Settings)

    $value = Get-LastMonthInstallExtractSettingValue -Settings $Settings -Name 'RequiredHeaders' -Default $null
    if ($null -ne $value) {
        return @($value | ForEach-Object { [string]$_ })
    }

    return @(Get-LastMonthInstallExtractDefaultRequiredHeaders)
}

function Get-LastMonthInstallExtractFileNamePatternFromSettings {
    param([Parameter(Mandatory)]$Settings)

    $value = Get-LastMonthInstallExtractSettingValue -Settings $Settings -Name 'FileNamePattern' -Default ''
    if (-not [string]::IsNullOrWhiteSpace([string]$value)) {
        return [string]$value
    }

    return Get-LastMonthInstallExtractDefaultFileNamePattern
}

function Get-LastMonthInstallExtractFailureCsvFileNameFromSettings {
    param([Parameter(Mandatory)]$Settings)

    $value = Get-LastMonthInstallExtractSettingValue -Settings $Settings -Name 'FailureCsvFileName' -Default ''
    if (-not [string]::IsNullOrWhiteSpace([string]$value)) {
        return [string]$value
    }

    return 'pc_installation_failure_list.csv'
}

function Get-LastMonthInstallExtractTargetDirectoryFromSettings {
    param([Parameter(Mandatory)]$Settings)

    return [string](Get-LastMonthInstallExtractSettingValue -Settings $Settings -Name 'TargetDirectory' -Default '')
}

function Get-LastMonthInstallExtractOutputCsvFileNameFromSettings {
    param([Parameter(Mandatory)]$Settings)

    return [string](Get-LastMonthInstallExtractSettingValue -Settings $Settings -Name 'OutputCsvFileName' -Default '')
}

function Add-LastMonthInstallExtractFailure {
    param(
        [Parameter(Mandatory)]$FailureRows,
        [Parameter(Mandatory)]$Logger,
        [Parameter(Mandatory)]$Timing,
        [AllowEmptyString()][string]$FileName = '',
        [AllowEmptyString()][string]$AssetName = '',
        [AllowEmptyString()][string]$LineNumber = '',
        [Parameter(Mandatory)][string]$Reason
    )

    $timestampText = Get-LastMonthInstallExtractCallbackScriptBlock -Callbacks $Timing -Name 'TimestampText'
    $writeWarning = Get-LastMonthInstallExtractCallbackScriptBlock -Callbacks $Logger -Name 'WriteWarning'
    & $writeWarning $Reason

    [void]$FailureRows.Add((New-LastMonthInstallExtractFailureRow `
        -FileName $FileName `
        -AssetName $AssetName `
        -LineNumber $LineNumber `
        -Reason $Reason `
        -Timestamp (& $timestampText)))
}

function Invoke-LastMonthInstallExtractCsvFileProcessing {
    param(
        [Parameter(Mandatory)]$File,
        [Parameter(Mandatory)]$DateRange,
        [Parameter(Mandatory)][string[]]$RequiredHeaders,
        [Parameter(Mandatory)][string]$FileNamePattern,
        [Parameter(Mandatory)]$Dependencies
    )

    $input = $Dependencies.Input
    $logger = $Dependencies.Logger
    $timing = $Dependencies.Timing

    $readAllBytes = Get-LastMonthInstallExtractCallbackScriptBlock -Callbacks $input -Name 'ReadAllBytes'
    $writeInfo = Get-LastMonthInstallExtractCallbackScriptBlock -Callbacks $logger -Name 'WriteInfo'

    $installationRows = New-Object System.Collections.ArrayList
    $failureRows = New-Object System.Collections.ArrayList
    $readRowCount = 0
    $matchedRowCount = 0

    $fileName = [string]$File.Name
    $fullName = [string]$File.FullName
    & $writeInfo "CSV処理開始: $fileName"

    $fileNameResult = Get-LastMonthInstallExtractAssetNameFromFileName -FileName $fileName -Pattern $FileNamePattern
    if (-not $fileNameResult.IsValid) {
        Add-LastMonthInstallExtractFailure -FailureRows $failureRows -Logger $logger -Timing $timing -FileName $fileName -Reason $fileNameResult.Reason
        return New-LastMonthInstallExtractWorkflowResult -InstallationRows @() -FailureRows $failureRows.ToArray() -ProcessedFileCount 0 -SkippedFileCount 1
    }

    $assetName = [string]$fileNameResult.AssetName

    try {
        $bytes = & $readAllBytes $fullName
        $readResult = ConvertFrom-LastMonthInstallExtractSupportedBytes -Bytes $bytes
        $text = $readResult.Text
        & $writeInfo "CSV文字コード: $fileName / $($readResult.EncodingName)"
    }
    catch {
        Add-LastMonthInstallExtractFailure -FailureRows $failureRows -Logger $logger -Timing $timing -FileName $fileName -AssetName $assetName -Reason "CSV読み取り失敗のためスキップ: $fileName / $($_.Exception.Message)"
        return New-LastMonthInstallExtractWorkflowResult -InstallationRows @() -FailureRows $failureRows.ToArray() -ProcessedFileCount 0 -SkippedFileCount 1
    }

    try {
        $delimiter = Get-LastMonthInstallExtractDelimiterFromText -Text $text
        $delimiterName = if ($delimiter -eq "`t") { 'TSV(tab)' } else { 'CSV(comma)' }
        $csv = Import-LastMonthInstallExtractDelimitedText -Text $text -Delimiter $delimiter
    }
    catch {
        Add-LastMonthInstallExtractFailure -FailureRows $failureRows -Logger $logger -Timing $timing -FileName $fileName -AssetName $assetName -Reason "CSV解析失敗のためスキップ: $fileName / $($_.Exception.Message)"
        return New-LastMonthInstallExtractWorkflowResult -InstallationRows @() -FailureRows $failureRows.ToArray() -ProcessedFileCount 0 -SkippedFileCount 1
    }

    $headers = @($csv.Headers)
    $headerValidation = Test-LastMonthInstallExtractRequiredHeadersExact -Headers $headers -RequiredHeaders $RequiredHeaders
    if (-not $headerValidation.IsValid) {
        $reason = (
            'カラム不一致のためスキップ: {0} / 実カラム=[{1}] / 期待カラム=[{2}] / 一致カラム=[{3}] / 不足カラム=[{4}] / 余分カラム=[{5}] / 重複カラム=[{6}] / 順序一致={7}' -f
            $fileName,
            (Format-LastMonthInstallExtractListForLog $headers),
            (Format-LastMonthInstallExtractListForLog $RequiredHeaders),
            (Format-LastMonthInstallExtractListForLog $headerValidation.MatchedHeaders),
            (Format-LastMonthInstallExtractListForLog $headerValidation.MissingHeaders),
            (Format-LastMonthInstallExtractListForLog $headerValidation.ExtraHeaders),
            (Format-LastMonthInstallExtractListForLog $headerValidation.DuplicateHeaders),
            $headerValidation.SameOrder
        )
        Add-LastMonthInstallExtractFailure -FailureRows $failureRows -Logger $logger -Timing $timing -FileName $fileName -AssetName $assetName -Reason $reason
        return New-LastMonthInstallExtractWorkflowResult -InstallationRows @() -FailureRows $failureRows.ToArray() -ProcessedFileCount 0 -SkippedFileCount 1
    }

    foreach ($entry in @($csv.Rows)) {
        $readRowCount++

        if ($entry.IsMalformed) {
            Add-LastMonthInstallExtractFailure -FailureRows $failureRows -Logger $logger -Timing $timing -FileName $fileName -AssetName $assetName -LineNumber ([string]$entry.LineNumber) -Reason "CSV行スキップ: $fileName / 行=$($entry.LineNumber) / 理由=$($entry.MalformedReason)"
            continue
        }

        $row = $entry.Data
        $installDateRaw = [string]$row.'導入日'
        $installDate = ConvertTo-LastMonthInstallExtractInstallDateOrNull -Value $installDateRaw

        if ($null -eq $installDate) {
            Add-LastMonthInstallExtractFailure -FailureRows $failureRows -Logger $logger -Timing $timing -FileName $fileName -AssetName $assetName -LineNumber ([string]$entry.LineNumber) -Reason "導入日を日付として解釈できないため行スキップ: $fileName / 行=$($entry.LineNumber) / 導入日='$installDateRaw'"
            continue
        }

        if (Test-LastMonthInstallExtractDateInRange -Date $installDate -StartInclusive $DateRange.StartInclusive -EndExclusive $DateRange.EndExclusive) {
            [void]$installationRows.Add((New-LastMonthInstallExtractInstallationRow `
                -AssetName $assetName `
                -ProductName ([string]$row.'アプリ名') `
                -Version ([string]$row.'バージョン') `
                -InstallDate ($installDateRaw.Trim())))
            $matchedRowCount++
        }
    }

    & $writeInfo "CSV処理完了: $fileName / 端末名=$assetName / 文字コード=$($readResult.EncodingName) / 区切り=$delimiterName / 読み取り行数=$readRowCount / 抽出件数=$matchedRowCount"

    return New-LastMonthInstallExtractWorkflowResult `
        -InstallationRows $installationRows.ToArray() `
        -FailureRows $failureRows.ToArray() `
        -ProcessedFileCount 1 `
        -SkippedFileCount 0 `
        -ReadRowCount $readRowCount `
        -MatchedRowCount $matchedRowCount
}

function Add-LastMonthInstallExtractWorkflowFileResult {
    param(
        [Parameter(Mandatory)]$InstallationRows,
        [Parameter(Mandatory)]$FailureRows,
        [Parameter(Mandatory)]$FileResult
    )

    foreach ($row in @($FileResult.InstallationRows)) { [void]$InstallationRows.Add($row) }
    foreach ($row in @($FileResult.FailureRows)) { [void]$FailureRows.Add($row) }
}

function Invoke-LastMonthInstallExtractInstallationWorkflow {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$DateRange,
        [AllowNull()]$Dependencies = $null
    )

    $settings = $Context.JobSettings
    $resolvedDependencies = Resolve-LastMonthInstallExtractInstallationWorkflowDependencies -Context $Context -Dependencies $Dependencies
    $input = $resolvedDependencies.Input
    $logger = $resolvedDependencies.Logger

    $getTargetCsvFiles = Get-LastMonthInstallExtractCallbackScriptBlock -Callbacks $input -Name 'GetTargetCsvFiles'
    $writeInfo = Get-LastMonthInstallExtractCallbackScriptBlock -Callbacks $logger -Name 'WriteInfo'

    $targetDirectory = Get-LastMonthInstallExtractTargetDirectoryFromSettings -Settings $settings
    $outputCsvFileName = Get-LastMonthInstallExtractOutputCsvFileNameFromSettings -Settings $settings
    $requiredHeaders = @(Get-LastMonthInstallExtractRequiredHeadersFromSettings -Settings $settings)
    $fileNamePattern = Get-LastMonthInstallExtractFileNamePatternFromSettings -Settings $settings
    $failureCsvFileName = Get-LastMonthInstallExtractFailureCsvFileNameFromSettings -Settings $settings

    $installationRows = New-Object System.Collections.ArrayList
    $failureRows = New-Object System.Collections.ArrayList

    $files = @(& $getTargetCsvFiles $targetDirectory $outputCsvFileName $failureCsvFileName)
    & $writeInfo "読み取り対象CSV数: $($files.Count)"

    $processedFileCount = 0
    $skippedFileCount = 0
    $totalReadRowCount = 0
    $totalMatchedRowCount = 0

    foreach ($file in $files) {
        $fileResult = Invoke-LastMonthInstallExtractCsvFileProcessing `
            -File $file `
            -DateRange $DateRange `
            -RequiredHeaders $requiredHeaders `
            -FileNamePattern $fileNamePattern `
            -Dependencies $resolvedDependencies

        Add-LastMonthInstallExtractWorkflowFileResult -InstallationRows $installationRows -FailureRows $failureRows -FileResult $fileResult
        $processedFileCount += $fileResult.ProcessedFileCount
        $skippedFileCount += $fileResult.SkippedFileCount
        $totalReadRowCount += $fileResult.ReadRowCount
        $totalMatchedRowCount += $fileResult.MatchedRowCount
    }

    return New-LastMonthInstallExtractWorkflowResult `
        -InstallationRows $installationRows.ToArray() `
        -FailureRows $failureRows.ToArray() `
        -InputFileCount $files.Count `
        -ProcessedFileCount $processedFileCount `
        -SkippedFileCount $skippedFileCount `
        -ReadRowCount $totalReadRowCount `
        -MatchedRowCount $totalMatchedRowCount
}
