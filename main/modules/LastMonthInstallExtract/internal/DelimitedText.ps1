$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

function Get-LastMonthInstallExtractDelimiterFromText {
    param([Parameter(Mandatory)][string]$Text)

    if ([string]::IsNullOrEmpty($Text)) { throw 'CSV内容が空です。' }

    $lfIndex = $Text.IndexOf("`n")
    if ($lfIndex -ge 0) {
        $firstLine = $Text.Substring(0, $lfIndex).TrimEnd("`r")
    }
    else {
        $firstLine = $Text
    }

    if ([string]::IsNullOrWhiteSpace($firstLine)) { throw '1行目が空です。' }

    if ($firstLine.Contains("`t")) { return "`t" }
    return ','
}

function ConvertFrom-LastMonthInstallExtractDelimitedTextRecords {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Delimiter
    )

    if ($Delimiter -eq "`t") {
        $delimiterChar = [char]9
    }
    elseif ($Delimiter -eq ',') {
        $delimiterChar = [char]44
    }
    else {
        throw "未対応の区切り文字です: '$Delimiter'"
    }

    $records = New-Object System.Collections.ArrayList
    $record = New-Object System.Collections.ArrayList
    $field = New-Object System.Text.StringBuilder
    $inQuotes = $false
    $lineNumber = 1
    $recordStartLine = 1
    $i = 0

    while ($i -lt $Text.Length) {
        $ch = $Text[$i]

        if ($ch -eq '"') {
            if ($inQuotes -and ($i + 1) -lt $Text.Length -and $Text[$i + 1] -eq '"') {
                [void]$field.Append('"')
                $i += 2
                continue
            }

            $inQuotes = -not $inQuotes
            $i++
            continue
        }

        if (-not $inQuotes -and $ch -eq $delimiterChar) {
            [void]$record.Add($field.ToString())
            [void]$field.Clear()
            $i++
            continue
        }

        if (-not $inQuotes -and ($ch -eq "`r" -or $ch -eq "`n")) {
            [void]$record.Add($field.ToString())
            [void]$field.Clear()

            [void]$records.Add([pscustomobject]@{
                LineNumber = $recordStartLine
                Fields = @($record)
            })

            $record = New-Object System.Collections.ArrayList

            if ($ch -eq "`r" -and ($i + 1) -lt $Text.Length -and $Text[$i + 1] -eq "`n") {
                $i += 2
            }
            else {
                $i++
            }

            $lineNumber++
            $recordStartLine = $lineNumber
            continue
        }

        [void]$field.Append([string]$ch)

        if ($ch -eq "`r" -or $ch -eq "`n") { $lineNumber++ }
        $i++
    }

    if ($inQuotes) { throw "引用符が閉じていません。開始行=$recordStartLine" }

    if ($field.Length -gt 0 -or $record.Count -gt 0) {
        [void]$record.Add($field.ToString())
        [void]$records.Add([pscustomobject]@{
            LineNumber = $recordStartLine
            Fields = @($record)
        })
    }

    return @($records)
}

function Import-LastMonthInstallExtractDelimitedText {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Delimiter
    )

    $records = @(ConvertFrom-LastMonthInstallExtractDelimitedTextRecords -Text $Text -Delimiter $Delimiter)

    if ($records.Count -eq 0) { throw 'CSVヘッダーが存在しません。' }

    $headers = @($records[0].Fields | ForEach-Object { [string]$_ })
    if ($headers.Count -eq 0) { throw 'CSVヘッダーが空です。' }
    $headers[0] = $headers[0].TrimStart([char]0xFEFF)

    $duplicateHeaders = @(
        $headers |
            Group-Object |
            Where-Object { $_.Count -gt 1 } |
            Select-Object -ExpandProperty Name
    )
    $hasDuplicateHeaders = $duplicateHeaders.Count -gt 0

    $rows = New-Object System.Collections.ArrayList

    for ($r = 1; $r -lt $records.Count; $r++) {
        $recordInfo = $records[$r]
        $fields = @($recordInfo.Fields | ForEach-Object { [string]$_ })

        if ($fields.Count -eq 1 -and [string]::IsNullOrWhiteSpace($fields[0])) { continue }

        if ($fields.Count -ne $headers.Count) {
            [void]$rows.Add([pscustomobject]@{
                LineNumber = $recordInfo.LineNumber
                IsMalformed = $true
                MalformedReason = "ヘッダー列数=$($headers.Count), 行の列数=$($fields.Count)"
                Data = $null
            })
            continue
        }

        if ($hasDuplicateHeaders) {
            [void]$rows.Add([pscustomobject]@{
                LineNumber = $recordInfo.LineNumber
                IsMalformed = $true
                MalformedReason = "ヘッダー名が重複しています: $(($duplicateHeaders | ForEach-Object { "'$_'" }) -join ', ')"
                Data = $null
            })
            continue
        }

        $props = [ordered]@{}
        for ($i = 0; $i -lt $headers.Count; $i++) {
            $props[$headers[$i]] = $fields[$i]
        }

        [void]$rows.Add([pscustomobject]@{
            LineNumber = $recordInfo.LineNumber
            IsMalformed = $false
            MalformedReason = $null
            Data = [pscustomobject]$props
        })
    }

    return [pscustomobject]@{
        Headers = @($headers)
        Rows = @($rows)
    }
}
