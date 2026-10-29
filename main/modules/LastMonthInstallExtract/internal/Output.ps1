$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

function Assert-LastMonthInstallExtractOutputPathAllowed {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Purpose,
        [Parameter(Mandatory)]$FileSystemService
    )

    $directory = Split-Path -Parent $Path
    if ([string]::IsNullOrWhiteSpace($directory)) {
        throw "$Purpose の出力ディレクトリが空です: $Path"
    }

    $resolvedDirectory = @($FileSystemService.AssertSafeDirectory.Invoke($directory, $Purpose))[0]
    if (-not (@($FileSystemService.TestPathUnderDirectory.Invoke($Path, $resolvedDirectory))[0])) {
        throw "$Purpose の出力先が許可ディレクトリ配下ではありません: $Path"
    }

    return $resolvedDirectory
}

function Export-LastMonthInstallExtractInstallationCsv {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Rows,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$FileSystemService
    )

    $resolvedDirectory = Assert-LastMonthInstallExtractOutputPathAllowed `
        -Path $Path `
        -Purpose 'アプリインストールCSV' `
        -FileSystemService $FileSystemService

    $items = @($Rows)

    if ($items.Count -gt 0) {
        $items |
            Select-Object '端末名', 'アプリ名', 'バージョン', '導入日' |
            Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8
    }
    else {
        '"端末名","アプリ名","バージョン","導入日"' |
            Set-Content -LiteralPath $Path -Encoding UTF8
    }

    return [pscustomobject]@{
        Path = $Path
        FullName = (Get-Item -LiteralPath $Path).FullName
        Created = $true
        Count = $items.Count
        Directory = $resolvedDirectory
    }
}

function Export-LastMonthInstallExtractFailureCsv {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$FailureRows,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$FileSystemService
    )

    $resolvedDirectory = Assert-LastMonthInstallExtractOutputPathAllowed `
        -Path $Path `
        -Purpose 'アプリ失敗CSV' `
        -FileSystemService $FileSystemService

    $items = @($FailureRows)

    if ($items.Count -eq 0) {
        $removed = @($FileSystemService.RemoveFileIfExists.Invoke($Path, $resolvedDirectory))[0]
        return [pscustomobject]@{
            Path = $Path
            FullName = $Path
            Created = $false
            Count = 0
            OldFileRemoved = $removed
        }
    }

    $items |
        Select-Object FileName, AssetName, LineNumber, Reason, Timestamp |
        Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8

    return [pscustomobject]@{
        Path = $Path
        FullName = (Get-Item -LiteralPath $Path).FullName
        Created = $true
        Count = $items.Count
        OldFileRemoved = $false
    }
}
