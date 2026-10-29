$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

function Convert-ToSafeFileNamePart {
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    $safe = $Value.Trim()

    foreach ($c in [System.IO.Path]::GetInvalidFileNameChars()) {
        $safe = $safe.Replace([string]$c, "_")
    }

    $safe = $safe -replace "\s+", "_"

    if ([string]::IsNullOrWhiteSpace($safe)) {
        return "UNKNOWN"
    }

    return $safe
}

function Test-FileReady {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    try {
        $stream = [System.IO.File]::Open(
            $Path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::None
        )

        $stream.Close()
        return $true
    }
    catch {
        return $false
    }
}

function Get-UniqueFilePath {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $Path
    }

    $directory = Split-Path -Parent $Path
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $extension = [System.IO.Path]::GetExtension($Path)

    for ($i = 1; $i -le 999; $i++) {
        $candidate = Join-Path $directory "$baseName ($i)$extension"

        if (-not (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }

    throw "重複しないファイル名を生成できませんでした: $Path"
}


function New-DownloadWaitRuntime {
    [pscustomobject]@{
        Now = { Get-Date }
        SleepMilliseconds = { param([int]$Milliseconds) Start-Sleep -Milliseconds $Milliseconds }
        SleepSeconds = { param([int]$Seconds) Start-Sleep -Seconds $Seconds }
    }
}

function Get-DownloadWaitRuntimeScriptBlock {
    param(
        [Parameter(Mandatory)]
        [object]$Runtime,

        [Parameter(Mandatory)]
        [string]$Name
    )

    $property = $Runtime.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value -or -not ($property.Value -is [scriptblock])) {
        throw "Download wait runtime に必要な scriptblock がありません: $Name"
    }

    return $property.Value
}

function Resolve-DownloadWaitRuntime {
    param(
        [AllowNull()]
        [object]$Runtime
    )

    if ($null -eq $Runtime) {
        $Runtime = New-DownloadWaitRuntime
    }

    [void](Get-DownloadWaitRuntimeScriptBlock -Runtime $Runtime -Name 'Now')
    [void](Get-DownloadWaitRuntimeScriptBlock -Runtime $Runtime -Name 'SleepMilliseconds')
    [void](Get-DownloadWaitRuntimeScriptBlock -Runtime $Runtime -Name 'SleepSeconds')

    return $Runtime
}

function Get-DownloadWaitNow {
    param(
        [Parameter(Mandatory)]
        [object]$Runtime
    )

    $nowCallback = Get-DownloadWaitRuntimeScriptBlock -Runtime $Runtime -Name 'Now'
    $now = & $nowCallback

    if ($null -eq $now) {
        throw 'Download wait runtime の Now が null を返しました。'
    }

    return [datetime]$now
}

function Invoke-DownloadWaitSleepMilliseconds {
    param(
        [Parameter(Mandatory)]
        [object]$Runtime,

        [int]$Milliseconds
    )

    $sleepCallback = Get-DownloadWaitRuntimeScriptBlock -Runtime $Runtime -Name 'SleepMilliseconds'
    & $sleepCallback $Milliseconds
}

function Invoke-DownloadWaitSleepSeconds {
    param(
        [Parameter(Mandatory)]
        [object]$Runtime,

        [int]$Seconds
    )

    $sleepCallback = Get-DownloadWaitRuntimeScriptBlock -Runtime $Runtime -Name 'SleepSeconds'
    & $sleepCallback $Seconds
}

function Assert-DownloadDirectoryExists {
    param(
        [Parameter(Mandatory)]
        [string]$Directory
    )

    if (-not (Test-Path -LiteralPath $Directory)) {
        throw "一時ダウンロードフォルダが見つかりません: $Directory"
    }
}

function Get-PartialDownloadFiles {
    param(
        [Parameter(Mandatory)]
        [string]$Directory
    )

    Get-ChildItem -LiteralPath $Directory -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -like "*.crdownload" -or
            $_.Name -like "*.tmp" -or
            $_.Name -like "*.download"
        }
}

function Get-DownloadedCsvCandidates {
    param(
        [Parameter(Mandatory)]
        [string]$Directory,

        [Parameter(Mandatory)]
        [string]$Prefix
    )

    Get-ChildItem -LiteralPath $Directory -File -Filter "$Prefix*.csv" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending
}

function Resolve-SingleDownloadedCsvCandidate {
    param(
        [AllowNull()]
        [object[]]$CsvFiles,

        [Parameter(Mandatory)]
        [string]$Directory
    )

    $files = @($CsvFiles)

    if ($files.Count -gt 1) {
        $names = ($files | Select-Object -ExpandProperty Name) -join ", "
        throw "一時ダウンロードフォルダにCSVが複数存在します。Directory=$Directory Files=$names"
    }

    if ($files.Count -eq 0) {
        return $null
    }

    return $files[0]
}

function Resolve-StableDownloadedCsvCandidate {
    param(
        [Parameter(Mandatory)]
        [System.IO.FileInfo]$CandidateFile,

        [Parameter(Mandatory)]
        [string]$Directory,

        [Parameter(Mandatory)]
        [string]$Prefix,

        [int]$StableSeconds,

        [Parameter(Mandatory)]
        [object]$Runtime
    )

    $path = $CandidateFile.FullName
    $sizeBeforeWait = (Get-Item -LiteralPath $path).Length

    Invoke-DownloadWaitSleepSeconds -Runtime $Runtime -Seconds $StableSeconds

    $partialFilesAfterWait = @(Get-PartialDownloadFiles -Directory $Directory)
    if ($partialFilesAfterWait.Count -gt 0) {
        return $null
    }

    $csvFilesAfterWait = @(Get-DownloadedCsvCandidates -Directory $Directory -Prefix $Prefix)
    $candidateAfterWait = Resolve-SingleDownloadedCsvCandidate -CsvFiles $csvFilesAfterWait -Directory $Directory

    if ($null -eq $candidateAfterWait) {
        return $null
    }

    $refreshed = Get-Item -LiteralPath $candidateAfterWait.FullName
    $sizeAfterWait = $refreshed.Length

    if ($sizeBeforeWait -eq $sizeAfterWait -and (Test-FileReady -Path $refreshed.FullName)) {
        return $refreshed
    }

    return $null
}

function New-DownloadedCsvTimeoutMessage {
    param(
        [Parameter(Mandatory)]
        [string]$Directory,

        [Parameter(Mandatory)]
        [string]$Prefix
    )

    return "CSVダウンロード完了待ちがタイムアウトしました。Directory=$Directory Prefix=$Prefix"
}

function Wait-DownloadedCsv {
    param(
        [Parameter(Mandatory)]
        [string]$Directory,

        [Parameter(Mandatory)]
        [string]$Prefix,

        [int]$TimeoutSeconds = 120,

        [int]$StableSeconds = 2,

        [AllowNull()]
        [object]$Runtime = $null
    )

    $Runtime = Resolve-DownloadWaitRuntime -Runtime $Runtime
    Assert-DownloadDirectoryExists -Directory $Directory

    $deadline = (Get-DownloadWaitNow -Runtime $Runtime).AddSeconds($TimeoutSeconds)

    while ((Get-DownloadWaitNow -Runtime $Runtime) -lt $deadline) {
        $partialFiles = @(Get-PartialDownloadFiles -Directory $Directory)

        if ($partialFiles.Count -gt 0) {
            Invoke-DownloadWaitSleepMilliseconds -Runtime $Runtime -Milliseconds 500
            continue
        }

        $csvFiles = @(Get-DownloadedCsvCandidates -Directory $Directory -Prefix $Prefix)
        $candidate = Resolve-SingleDownloadedCsvCandidate -CsvFiles $csvFiles -Directory $Directory

        if ($null -ne $candidate) {
            $stableCandidate = Resolve-StableDownloadedCsvCandidate `
                -CandidateFile $candidate `
                -Directory $Directory `
                -Prefix $Prefix `
                -StableSeconds $StableSeconds `
                -Runtime $Runtime

            if ($null -ne $stableCandidate) {
                return $stableCandidate
            }
        }

        Invoke-DownloadWaitSleepMilliseconds -Runtime $Runtime -Milliseconds 500
    }

    throw (New-DownloadedCsvTimeoutMessage -Directory $Directory -Prefix $Prefix)
}

function Rename-DownloadedCsvWithAssetName {
    param(
        [Parameter(Mandatory)]
        [System.IO.FileInfo]$CsvFile,

        [Parameter(Mandatory)]
        [string]$AssetName,

        [Parameter(Mandatory)]
        [string]$DestinationDirectory
    )

    if (-not (Test-Path -LiteralPath $DestinationDirectory)) {
        New-Item -ItemType Directory -Path $DestinationDirectory -Force | Out-Null
    }

    $safeAssetName = Convert-ToSafeFileNamePart -Value $AssetName

    # 例:
    #   app_list_20260604.csv
    #   app_list_20260604 (1).csv
    #
    # いずれも base を app_list_20260604 に正規化してから、
    # 最終保存先へ app_list_20260604_PCXX-19-008.csv の形で移動する。
    $normalizedBaseName = [regex]::Replace(
        $CsvFile.BaseName,
        "\s\(\d+\)$",
        ""
    )

    $newFileName = "$normalizedBaseName`_$safeAssetName$($CsvFile.Extension)"
    $newPath = Join-Path $DestinationDirectory $newFileName
    $newPath = Get-UniqueFilePath -Path $newPath

    Move-Item -LiteralPath $CsvFile.FullName -Destination $newPath -ErrorAction Stop

    return Get-Item -LiteralPath $newPath
}

function Wait-InstalledAppExportDownloadedCsv {
    param([string]$Directory,[string]$Prefix,[int]$TimeoutSeconds,[int]$StableSeconds)
    return Wait-DownloadedCsv -Directory $Directory -Prefix $Prefix -TimeoutSeconds $TimeoutSeconds -StableSeconds $StableSeconds
}
function Rename-InstalledAppExportDownloadedCsv { param([System.IO.FileInfo]$CsvFile,[string]$AssetName,[string]$DestinationDirectory) return Rename-DownloadedCsvWithAssetName -CsvFile $CsvFile -AssetName $AssetName -DestinationDirectory $DestinationDirectory }
