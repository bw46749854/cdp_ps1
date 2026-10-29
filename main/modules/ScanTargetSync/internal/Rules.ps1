$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

function ConvertTo-ScanTargetSyncOptionalText {
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return $null
    }

    $text = [string]$Value

    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }

    return $text
}

function New-ScanTargetSyncEvaluationResult {
    param(
        [Parameter(Mandatory)]
        [bool]$IsTarget,

        [Parameter(Mandatory)]
        [bool]$IsCsvError,

        [AllowNull()]
        [object]$ElapsedDays,

        [AllowNull()]
        [object]$Reason,

        [AllowNull()]
        [object]$ErrorReason
    )

    return [pscustomobject]@{
        IsTarget     = $IsTarget
        IsCsvError   = $IsCsvError
        ElapsedDays  = $ElapsedDays
        Reason       = ConvertTo-ScanTargetSyncOptionalText -Value $Reason
        ErrorReason  = ConvertTo-ScanTargetSyncOptionalText -Value $ErrorReason
    }
}

function Test-ScanTargetSyncScanCompletionIsMissing {
    param(
        [AllowNull()]
        [string]$ScanCompletedRaw
    )

    return ([string]::IsNullOrWhiteSpace($ScanCompletedRaw) -or $ScanCompletedRaw.Trim() -eq "-")
}

function Convert-ScanTargetSyncRuleDate {
    param(
        [AllowNull()]
        [string]$Value
    )

    return Convert-VendorDateOnly -Value $Value
}

function Get-ScanTargetSyncElapsedDays {
    param(
        [Parameter(Mandatory)]
        [datetime]$ScanCompleted,

        [Parameter(Mandatory)]
        [datetime]$LastConnected
    )

    return ($LastConnected.Date - $ScanCompleted.Date).Days
}

function New-ScanTargetSyncMissingCompletionEvaluation {
    return New-ScanTargetSyncEvaluationResult `
        -IsTarget $true `
        -IsCsvError $false `
        -ElapsedDays $null `
        -Reason "手動スキャンの完了なし" `
        -ErrorReason $null
}

function New-ScanTargetSyncCsvErrorEvaluation {
    param(
        [Parameter(Mandatory)]
        [string]$ErrorReason,

        [AllowNull()]
        [object]$ElapsedDays
    )

    return New-ScanTargetSyncEvaluationResult `
        -IsTarget $false `
        -IsCsvError $true `
        -ElapsedDays $ElapsedDays `
        -Reason $null `
        -ErrorReason $ErrorReason
}

function New-ScanTargetSyncTargetEvaluation {
    param(
        [Parameter(Mandatory)]
        [object]$ElapsedDays
    )

    return New-ScanTargetSyncEvaluationResult `
        -IsTarget $true `
        -IsCsvError $false `
        -ElapsedDays $ElapsedDays `
        -Reason "最終通信日時との差が $ElapsedDays 日" `
        -ErrorReason $null
}

function New-ScanTargetSyncNonTargetEvaluation {
    param(
        [Parameter(Mandatory)]
        [object]$ElapsedDays
    )

    return New-ScanTargetSyncEvaluationResult `
        -IsTarget $false `
        -IsCsvError $false `
        -ElapsedDays $ElapsedDays `
        -Reason "最終通信日時との差が $ElapsedDays 日のため対象外" `
        -ErrorReason $null
}

function Get-ScanTargetSyncEvaluation {
    param(
        [string]$ScanCompletedRaw,

        [string]$LastConnectedRaw,

        [Parameter(Mandatory)]
        [int]$DaysThreshold
    )

    if (Test-ScanTargetSyncScanCompletionIsMissing -ScanCompletedRaw $ScanCompletedRaw) {
        return New-ScanTargetSyncMissingCompletionEvaluation
    }

    $scanCompleted = Convert-ScanTargetSyncRuleDate -Value $ScanCompletedRaw

    if ($null -eq $scanCompleted) {
        return New-ScanTargetSyncCsvErrorEvaluation `
            -ElapsedDays $null `
            -ErrorReason "手動スキャンの完了が日付として解釈不可"
    }

    $lastConnected = Convert-ScanTargetSyncRuleDate -Value $LastConnectedRaw

    if ($null -eq $lastConnected) {
        return New-ScanTargetSyncCsvErrorEvaluation `
            -ElapsedDays $null `
            -ErrorReason "手動スキャンの完了は日付だが、最終通信日時が日付として解釈不可"
    }

    $elapsedDays = Get-ScanTargetSyncElapsedDays -ScanCompleted $scanCompleted -LastConnected $lastConnected

    if ($elapsedDays -lt 0) {
        return New-ScanTargetSyncCsvErrorEvaluation `
            -ElapsedDays $elapsedDays `
            -ErrorReason "最終通信日時が手動スキャンの完了より古く、日付関係が不整合"
    }

    if ($elapsedDays -ge $DaysThreshold) {
        return New-ScanTargetSyncTargetEvaluation -ElapsedDays $elapsedDays
    }

    return New-ScanTargetSyncNonTargetEvaluation -ElapsedDays $elapsedDays
}

function New-ScanTargetSyncTargetRow {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$CsvRow,

        [Parameter(Mandatory)]
        [pscustomobject]$Evaluation
    )

    [pscustomobject]@{
        Endpoint      = $CsvRow."ホスト名"
        User          = $CsvRow."利用者"
        Status        = $CsvRow."接続状態"
        LastConnected = $CsvRow."最終通信日時"
        ScanStarted   = $CsvRow."手動スキャンの開始"
        ScanCompleted = $CsvRow."手動スキャンの完了"
        ElapsedDays   = $Evaluation.ElapsedDays
        Reason        = $Evaluation.Reason
    }
}

function Get-ScanTargetSyncTargetExtraction {
    param(
        [Parameter(Mandatory)]
        [object[]]$CsvRows,

        [Parameter(Mandatory)]
        [int]$DaysThreshold,

        [Parameter(Mandatory)]
        [string]$Timestamp
    )

    $onRows = @()
    $csvErrorRows = @()
    $offRows = @()

    foreach ($row in $CsvRows) {
        $endpoint = $row."ホスト名"

        if ([string]::IsNullOrWhiteSpace($endpoint)) {
            $csvErrorRows += [pscustomobject]@{
                Endpoint      = $endpoint
                User          = $row."利用者"
                Status        = $row."接続状態"
                LastConnected = $row."最終通信日時"
                ScanStarted   = $row."手動スキャンの開始"
                ScanCompleted = $row."手動スキャンの完了"
                ElapsedDays   = $null
                Reason        = "ホスト名が空欄"
                Timestamp     = $Timestamp
            }
            continue
        }

        $evaluation = Get-ScanTargetSyncEvaluation `
            -ScanCompletedRaw $row."手動スキャンの完了" `
            -LastConnectedRaw $row."最終通信日時" `
            -DaysThreshold $DaysThreshold

        if ($evaluation.IsCsvError) {
            $csvErrorRows += New-ScanTargetSyncCsvErrorRow -CsvRow $row -Evaluation $evaluation -Timestamp $Timestamp
            continue
        }

        if ($evaluation.IsTarget) {
            $onRows += New-ScanTargetSyncTargetRow -CsvRow $row -Evaluation $evaluation
        }
        else {
            $offRows += New-ScanTargetSyncTargetRow -CsvRow $row -Evaluation $evaluation
        }
    }

    return [pscustomobject]@{
        OnRows   = @($onRows)
        CsvErrorRows = @($csvErrorRows)
        OffRows  = @($offRows)
    }
}

function Get-ScanTargetSyncRuleDescription {
    param([int]$DaysThreshold)

    return @(
        "手動スキャンの完了が '-' または空欄 → ON",
        "手動スキャンの完了が日付として解釈不可 → CSVデータエラーとして停止",
        "最終通信日時と手動スキャンの完了の差が $DaysThreshold 日以上 → ON",
        "手動スキャンの完了は日付だが、最終通信日時が日付として解釈不可 → CSVデータエラーとして停止",
        "最終通信日時が手動スキャンの完了より古い → CSVデータエラーとして停止",
        "上記以外 → OFF"
    )
}
