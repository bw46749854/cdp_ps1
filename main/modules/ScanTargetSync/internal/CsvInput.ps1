$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

function Assert-VendorDeviceCsvContract {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Rows
    )

    $requiredHeaders = @(
        "ホスト名",
        "利用者",
        "接続状態",
        "最終通信日時",
        "手動スキャンの開始",
        "手動スキャンの完了"
    )

    if ($Rows.Count -eq 0) {
        throw "CSVにデータ行がありません。"
    }

    $headers = @($Rows[0].PSObject.Properties | Select-Object -ExpandProperty Name)
    $missing = @($requiredHeaders | Where-Object { $headers -notcontains $_ })

    if ($missing.Count -gt 0) {
        throw "CSV必須列が不足しています: $($missing -join ', ')"
    }
}

function Test-VendorDateTextIsMissing {
    param(
        [AllowNull()]
        [string]$Value
    )

    return ([string]::IsNullOrWhiteSpace($Value) -or $Value.Trim() -eq "-")
}

function Normalize-VendorDateText {
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    return [regex]::Replace($Value.Trim(), "\s+", " ")
}

function ConvertFrom-VendorDateOffsetPreservingDisplayedDate {
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    $invariantCulture = [System.Globalization.CultureInfo]::InvariantCulture
    $styles = [System.Globalization.DateTimeStyles]::None

    # CSV実データは 2025-09-07T23:11:04+09:00 のような ISO 8601 + オフセット形式で出力される。
    # 業務判定ではCSVに表示された暦日をそのまま使うため、UTCやPCローカル時刻へ変換せず DateTimeOffset.DateTime.Date を使う。
    $dateTimeOffsetFormats = @(
        "yyyy-MM-dd'T'HH:mm:sszzz",
        "yyyy-MM-dd'T'H:mm:sszzz",
        "yyyy-M-d'T'HH:mm:sszzz",
        "yyyy-M-d'T'H:mm:sszzz",
        "yyyy-MM-dd'T'HH:mm:ss.FFFFFFFzzz",
        "yyyy-MM-dd'T'H:mm:ss.FFFFFFFzzz",
        "yyyy-M-d'T'HH:mm:ss.FFFFFFFzzz",
        "yyyy-M-d'T'H:mm:ss.FFFFFFFzzz",
        "yyyy-MM-dd'T'HH:mm:ss'Z'",
        "yyyy-MM-dd'T'H:mm:ss'Z'",
        "yyyy-M-d'T'HH:mm:ss'Z'",
        "yyyy-M-d'T'H:mm:ss'Z'",
        "yyyy-MM-dd'T'HH:mm:ss.FFFFFFF'Z'",
        "yyyy-MM-dd'T'H:mm:ss.FFFFFFF'Z'",
        "yyyy-M-d'T'HH:mm:ss.FFFFFFF'Z'",
        "yyyy-M-d'T'H:mm:ss.FFFFFFF'Z'"
    )

    foreach ($format in $dateTimeOffsetFormats) {
        try {
            return ([System.DateTimeOffset]::ParseExact($Value, $format, $invariantCulture, $styles)).DateTime.Date
        }
        catch {
            # 次の契約内形式を試す。
        }
    }

    if ($Value -match "^\d{4}-\d{1,2}-\d{1,2}T\d{1,2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$") {
        try {
            return ([System.DateTimeOffset]::Parse($Value, $invariantCulture, $styles)).DateTime.Date
        }
        catch {
            # 次の契約内形式を試す。
        }
    }

    return $null
}

function ConvertFrom-VendorKnownLocalDate {
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    $jaCulture = [System.Globalization.CultureInfo]::GetCultureInfo("ja-JP")
    $styles = [System.Globalization.DateTimeStyles]::None
    $formats = @(
        "yyyy-MM-dd",
        "yyyy-M-d",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-M-d H:mm:ss",
        "yyyy-M-d HH:mm:ss",
        "yyyy/MM/dd",
        "yyyy/M/d",
        "yyyy/MM/dd HH:mm:ss",
        "yyyy/M/d H:mm:ss",
        "yyyy/M/d HH:mm:ss",
        "yyyy年M月d日",
        "yyyy年MM月d日",
        "yyyy年M月dd日",
        "yyyy年MM月dd日",
        "yyyy年M月d日 H:mm:ss",
        "yyyy年M月d日 HH:mm:ss",
        "yyyy年MM月d日 H:mm:ss",
        "yyyy年MM月d日 HH:mm:ss",
        "yyyy年M月dd日 H:mm:ss",
        "yyyy年M月dd日 HH:mm:ss",
        "yyyy年MM月dd日 H:mm:ss",
        "yyyy年MM月dd日 HH:mm:ss"
    )

    foreach ($format in $formats) {
        try {
            return [datetime]::ParseExact($Value, $format, $jaCulture, $styles).Date
        }
        catch {
            # 次の契約内形式を試す。
        }
    }

    return $null
}

function Select-VendorLeadingDatePart {
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    if ($Value -match "^(\d{4}-\d{1,2}-\d{1,2})") {
        return $Matches[1]
    }

    if ($Value -match "^(\d{4}/\d{1,2}/\d{1,2})") {
        return $Matches[1]
    }

    if ($Value -match "^(\d{4}年\d{1,2}月\d{1,2}日)") {
        return $Matches[1]
    }

    return $null
}

function ConvertFrom-VendorLeadingDatePart {
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    $datePart = Select-VendorLeadingDatePart -Value $Value

    if (-not $datePart) {
        return $null
    }

    $jaCulture = [System.Globalization.CultureInfo]::GetCultureInfo("ja-JP")
    $styles = [System.Globalization.DateTimeStyles]::None
    $formats = @(
        "yyyy-MM-dd",
        "yyyy-M-d",
        "yyyy/MM/dd",
        "yyyy/M/d",
        "yyyy年M月d日",
        "yyyy年MM月d日",
        "yyyy年M月dd日",
        "yyyy年MM月dd日"
    )

    foreach ($format in $formats) {
        try {
            return [datetime]::ParseExact($datePart, $format, $jaCulture, $styles).Date
        }
        catch {
            # 次の契約内形式を試す。
        }
    }

    return $null
}

function Convert-VendorDateOnly {
    param(
        [string]$Value
    )

    if (Test-VendorDateTextIsMissing -Value $Value) {
        return $null
    }

    $normalizedValue = Normalize-VendorDateText -Value $Value

    $offsetDate = ConvertFrom-VendorDateOffsetPreservingDisplayedDate -Value $normalizedValue
    if ($null -ne $offsetDate) {
        return $offsetDate
    }

    $knownLocalDate = ConvertFrom-VendorKnownLocalDate -Value $normalizedValue
    if ($null -ne $knownLocalDate) {
        return $knownLocalDate
    }

    return ConvertFrom-VendorLeadingDatePart -Value $normalizedValue
}

function New-ScanTargetSyncCsvErrorRow {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$CsvRow,

        [Parameter(Mandatory)]
        [pscustomobject]$Evaluation,

        [Parameter(Mandatory)]
        [string]$Timestamp
    )

    [pscustomobject]@{
        Endpoint      = $CsvRow."ホスト名"
        User          = $CsvRow."利用者"
        Status        = $CsvRow."接続状態"
        LastConnected = $CsvRow."最終通信日時"
        ScanStarted   = $CsvRow."手動スキャンの開始"
        ScanCompleted = $CsvRow."手動スキャンの完了"
        ElapsedDays   = $Evaluation.ElapsedDays
        Reason        = $Evaluation.ErrorReason
        Timestamp     = $Timestamp
    }
}

function Assert-ScanTargetSyncInputCsvContract {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Rows
    )

    Assert-VendorDeviceCsvContract -Rows $Rows
}
