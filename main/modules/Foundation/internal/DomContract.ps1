$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

function Format-DomContractResult {
    param(
        [Parameter(Mandatory)]
        [object]$Result
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("scope=$($Result.scope) ok=$($Result.ok) fatalCount=$($Result.fatalCount) warningCount=$($Result.warningCount)")

    foreach ($check in @($Result.checks)) {
        if ($check.ok -eq $true) {
            continue
        }

        $details = ""
        if ($check.details) {
            $details = ($check.details | ConvertTo-Json -Compress -Depth 12)
        }

        $lines.Add("[$($check.severity)] $($check.name): $($check.message) details=$details")
    }

    return ($lines -join "`n")
}

function Assert-DomContractResult {
    param(
        [Parameter(Mandatory)]
        [object]$Result,

        [Parameter(Mandatory)]
        [string]$Description
    )

    if (-not $Result) {
        throw "DOM契約チェック結果が空です: $Description"
    }

    $formatted = Format-DomContractResult -Result $Result

    if ([int]$Result.warningCount -gt 0) {
        Write-Warning "DOM契約 warning: $Description`n$formatted"
    }

    if ([int]$Result.fatalCount -gt 0) {
        throw "DOM契約違反: $Description`n$formatted"
    }
}

