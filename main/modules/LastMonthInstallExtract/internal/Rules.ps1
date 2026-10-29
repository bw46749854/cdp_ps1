$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

function Get-LastMonthInstallExtractDefaultRequiredHeaders {
    return @('アプリ名', 'バージョン', '導入日')
}

function Get-LastMonthInstallExtractDefaultFileNamePattern {
    return '^.+_(PCXX-\d{2}-\d{3})\.csv$'
}

function Format-LastMonthInstallExtractListForLog {
    param([AllowNull()][object[]]$Values)

    if ($null -eq $Values -or @($Values).Count -eq 0) { return '(なし)' }
    return (@($Values) | ForEach-Object { "'$_'" }) -join ', '
}

function New-LastMonthInstallExtractMonthlyDateRange {
    param([Parameter(Mandatory)][datetime]$Now)

    $today = $Now.Date
    $thisMonthStart = [datetime]::new($today.Year, $today.Month, 1)
    $lastMonthStart = $thisMonthStart.AddMonths(-1)

    return [pscustomobject]@{
        Today = $today
        StartInclusive = $lastMonthStart
        EndExclusive = $thisMonthStart
    }
}

function Get-LastMonthInstallExtractAssetNameFromFileName {
    param(
        [Parameter(Mandatory)][string]$FileName,
        [string]$Pattern = ''
    )

    if ([string]::IsNullOrWhiteSpace($Pattern)) {
        $Pattern = Get-LastMonthInstallExtractDefaultFileNamePattern
    }

    if ($FileName -cnotmatch $Pattern) {
        return [pscustomobject]@{
            IsValid = $false
            AssetName = ''
            Reason = "ファイル名形式不一致: $FileName / 期待形式: [任意の文字列]_PCXX-[数字2桁]-[数字3桁].csv"
        }
    }

    return [pscustomobject]@{
        IsValid = $true
        AssetName = $Matches[1]
        Reason = ''
    }
}

function Test-LastMonthInstallExtractRequiredHeadersExact {
    param(
        [Parameter(Mandatory)][string[]]$Headers,
        [Parameter(Mandatory)][string[]]$RequiredHeaders
    )

    $matchedHeaders = @(
        $Headers |
            Where-Object { $RequiredHeaders -ccontains $_ } |
            Select-Object -Unique
    )

    $missingHeaders = @($RequiredHeaders | Where-Object { $Headers -cnotcontains $_ })
    $extraHeaders = @($Headers | Where-Object { $RequiredHeaders -cnotcontains $_ })
    $duplicateHeaders = @(
        $Headers |
            Group-Object |
            Where-Object { $_.Count -gt 1 } |
            Select-Object -ExpandProperty Name
    )

    $sameCount = $Headers.Count -eq $RequiredHeaders.Count
    $sameOrder = $true

    if ($sameCount) {
        for ($i = 0; $i -lt $RequiredHeaders.Count; $i++) {
            if ($Headers[$i] -cne $RequiredHeaders[$i]) {
                $sameOrder = $false
                break
            }
        }
    }
    else {
        $sameOrder = $false
    }

    $isValid = (
        $sameCount -and
        $sameOrder -and
        $missingHeaders.Count -eq 0 -and
        $extraHeaders.Count -eq 0 -and
        $duplicateHeaders.Count -eq 0
    )

    return [pscustomobject]@{
        IsValid = $isValid
        MatchedHeaders = @($matchedHeaders)
        MissingHeaders = @($missingHeaders)
        ExtraHeaders = @($extraHeaders)
        DuplicateHeaders = @($duplicateHeaders)
        SameOrder = $sameOrder
    }
}

function ConvertTo-LastMonthInstallExtractInstallDateOrNull {
    param([AllowEmptyString()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }

    $trimmed = $Value.Trim()
    $culture = [System.Globalization.CultureInfo]::GetCultureInfo('ja-JP')
    $styles = [System.Globalization.DateTimeStyles]::AllowWhiteSpaces

    $formats = @(
        'yyyy-MM-dd',
        'yyyy-M-d',
        'yyyy/MM/dd',
        'yyyy/M/d',
        'yyyy-MM-dd HH:mm:ss',
        'yyyy-M-d H:mm:ss',
        'yyyy/MM/dd HH:mm:ss',
        'yyyy/M/d H:mm:ss',
        'yyyy年MM月dd日',
        'yyyy年M月d日'
    )

    $parsed = [datetime]::MinValue

    if ([datetime]::TryParseExact($trimmed, $formats, $culture, $styles, [ref]$parsed)) {
        return $parsed.Date
    }

    if ([datetime]::TryParse($trimmed, $culture, $styles, [ref]$parsed)) {
        return $parsed.Date
    }

    return $null
}

function Test-LastMonthInstallExtractDateInRange {
    param(
        [Parameter(Mandatory)][datetime]$Date,
        [Parameter(Mandatory)][datetime]$StartInclusive,
        [Parameter(Mandatory)][datetime]$EndExclusive
    )

    return ($Date -ge $StartInclusive -and $Date -lt $EndExclusive)
}
