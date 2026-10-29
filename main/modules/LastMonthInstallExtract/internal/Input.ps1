$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

function Get-LastMonthInstallExtractTargetCsvFileInfos {
    param(
        [Parameter(Mandatory)][string]$TargetDirectory,
        [Parameter(Mandatory)][string]$OutputCsvFileName,
        [AllowEmptyString()][string]$FailureCsvFileName = ''
    )

    if (-not (Test-Path -LiteralPath $TargetDirectory -PathType Container)) {
        throw "対象ディレクトリが見つかりません: $TargetDirectory"
    }

    $excluded = @($OutputCsvFileName)
    if (-not [string]::IsNullOrWhiteSpace($FailureCsvFileName)) {
        $excluded += $FailureCsvFileName
    }

    return @(
        Get-ChildItem -LiteralPath $TargetDirectory -File -Filter '*.csv' |
            Where-Object { $excluded -notcontains $_.Name } |
            Sort-Object Name |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Name
                    FullName = $_.FullName
                }
            }
    )
}

function Read-LastMonthInstallExtractFileBytes {
    param([Parameter(Mandatory)][string]$Path)

    return [System.IO.File]::ReadAllBytes($Path)
}
