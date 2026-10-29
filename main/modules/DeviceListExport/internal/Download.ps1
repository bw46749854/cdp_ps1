$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

function ConvertTo-DeviceListExportSafeFileNamePart {
    param([Parameter(Mandatory)][string]$Value)

    $safe = $Value.Trim()
    foreach ($c in [System.IO.Path]::GetInvalidFileNameChars()) {
        $safe = $safe.Replace([string]$c, '_')
    }

    $safe = $safe -replace '[\s\u00a0\u3000]+', '_'
    if ([string]::IsNullOrWhiteSpace($safe)) {
        return 'UNKNOWN'
    }

    return $safe
}

function Test-DeviceListExportFileReady {
    param([Parameter(Mandatory)][string]$Path)

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

function Get-DeviceListExportUniqueFilePath {
    param([Parameter(Mandatory)][string]$Path)

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

function New-DeviceListExportDownloadWaitRuntime {
    [pscustomobject]@{
        Now = { Get-Date }
        SleepMilliseconds = { param([int]$Milliseconds) Start-Sleep -Milliseconds $Milliseconds }
        SleepSeconds = { param([int]$Seconds) Start-Sleep -Seconds $Seconds }
    }
}

function Get-DeviceListExportDownloadWaitRuntimeScriptBlock {
    param(
        [Parameter(Mandatory)][object]$Runtime,
        [Parameter(Mandatory)][string]$Name
    )

    $property = $Runtime.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value -or -not ($property.Value -is [scriptblock])) {
        throw "DeviceListExport download wait runtime に必要な scriptblock がありません: $Name"
    }

    return $property.Value
}

function Resolve-DeviceListExportDownloadWaitRuntime {
    param([AllowNull()][object]$Runtime)

    if ($null -eq $Runtime) {
        $Runtime = New-DeviceListExportDownloadWaitRuntime
    }

    [void](Get-DeviceListExportDownloadWaitRuntimeScriptBlock -Runtime $Runtime -Name 'Now')
    [void](Get-DeviceListExportDownloadWaitRuntimeScriptBlock -Runtime $Runtime -Name 'SleepMilliseconds')
    [void](Get-DeviceListExportDownloadWaitRuntimeScriptBlock -Runtime $Runtime -Name 'SleepSeconds')
    return $Runtime
}

function Get-DeviceListExportDownloadWaitNow {
    param([Parameter(Mandatory)][object]$Runtime)

    $nowCallback = Get-DeviceListExportDownloadWaitRuntimeScriptBlock -Runtime $Runtime -Name 'Now'
    $now = & $nowCallback
    if ($null -eq $now) {
        throw 'DeviceListExport download wait runtime の Now が null を返しました。'
    }

    return [datetime]$now
}

function Invoke-DeviceListExportDownloadSleepMilliseconds {
    param([Parameter(Mandatory)][object]$Runtime,[int]$Milliseconds)

    $sleepCallback = Get-DeviceListExportDownloadWaitRuntimeScriptBlock -Runtime $Runtime -Name 'SleepMilliseconds'
    & $sleepCallback $Milliseconds
}

function Invoke-DeviceListExportDownloadSleepSeconds {
    param([Parameter(Mandatory)][object]$Runtime,[int]$Seconds)

    $sleepCallback = Get-DeviceListExportDownloadWaitRuntimeScriptBlock -Runtime $Runtime -Name 'SleepSeconds'
    & $sleepCallback $Seconds
}

function Assert-DeviceListExportDownloadDirectoryExists {
    param([Parameter(Mandatory)][string]$Directory)

    if (-not (Test-Path -LiteralPath $Directory)) {
        throw "一時ダウンロードフォルダが見つかりません: $Directory"
    }
}

function Get-DeviceListExportPartialDownloadFiles {
    param([Parameter(Mandatory)][string]$Directory)

    Get-ChildItem -LiteralPath $Directory -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -like '*.crdownload' -or
            $_.Name -like '*.tmp' -or
            $_.Name -like '*.download'
        }
}

function Get-DeviceListExportDownloadedCsvCandidates {
    param(
        [Parameter(Mandatory)][string]$Directory,
        [string]$FileNamePattern = '^.+\.csv$'
    )

    Get-ChildItem -LiteralPath $Directory -File -Filter '*.csv' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match $FileNamePattern } |
        Sort-Object LastWriteTime -Descending
}

function Resolve-DeviceListExportSingleDownloadedCsvCandidate {
    param(
        [AllowNull()][object[]]$CsvFiles,
        [Parameter(Mandatory)][string]$Directory
    )

    $files = @($CsvFiles)
    if ($files.Count -gt 1) {
        $names = ($files | Select-Object -ExpandProperty Name) -join ', '
        throw "一時ダウンロードフォルダにCSV候補が複数存在します。Directory=$Directory Files=$names"
    }

    if ($files.Count -eq 0) {
        return $null
    }

    $file = $files[0]
    if ([string]::Compare([string]$file.Extension, '.csv', $true) -ne 0) {
        throw "ダウンロード成果物の拡張子がCSVではありません: $($file.FullName)"
    }

    if ($file.Length -le 0) {
        throw "ダウンロード成果物CSVが0 byteです: $($file.FullName)"
    }

    return $file
}

function Resolve-DeviceListExportStableDownloadedCsvCandidate {
    param(
        [Parameter(Mandatory)][System.IO.FileInfo]$CandidateFile,
        [Parameter(Mandatory)][string]$Directory,
        [string]$FileNamePattern = '^.+\.csv$',
        [int]$StableSeconds = 2,
        [Parameter(Mandatory)][object]$Runtime
    )

    $path = $CandidateFile.FullName
    $sizeBeforeWait = (Get-Item -LiteralPath $path).Length
    if ($sizeBeforeWait -le 0) {
        throw "ダウンロード成果物CSVが0 byteです: $path"
    }

    Invoke-DeviceListExportDownloadSleepSeconds -Runtime $Runtime -Seconds $StableSeconds

    $partialFilesAfterWait = @(Get-DeviceListExportPartialDownloadFiles -Directory $Directory)
    if ($partialFilesAfterWait.Count -gt 0) {
        return $null
    }

    $csvFilesAfterWait = @(Get-DeviceListExportDownloadedCsvCandidates -Directory $Directory -FileNamePattern $FileNamePattern)
    $candidateAfterWait = Resolve-DeviceListExportSingleDownloadedCsvCandidate -CsvFiles $csvFilesAfterWait -Directory $Directory
    if ($null -eq $candidateAfterWait) {
        return $null
    }

    $refreshed = Get-Item -LiteralPath $candidateAfterWait.FullName
    $sizeAfterWait = $refreshed.Length

    if ($sizeAfterWait -le 0) {
        throw "ダウンロード成果物CSVが0 byteです: $($refreshed.FullName)"
    }

    if ($sizeBeforeWait -eq $sizeAfterWait -and (Test-DeviceListExportFileReady -Path $refreshed.FullName)) {
        return $refreshed
    }

    return $null
}

function Wait-DeviceListExportDownloadedCsv {
    param(
        [Parameter(Mandatory)][string]$Directory,
        [string]$FileNamePattern = '^.+\.csv$',
        [int]$TimeoutSeconds = 120,
        [int]$StableSeconds = 2,
        [AllowNull()][object]$Runtime = $null
    )

    $Runtime = Resolve-DeviceListExportDownloadWaitRuntime -Runtime $Runtime
    Assert-DeviceListExportDownloadDirectoryExists -Directory $Directory
    $deadline = (Get-DeviceListExportDownloadWaitNow -Runtime $Runtime).AddSeconds($TimeoutSeconds)

    while ((Get-DeviceListExportDownloadWaitNow -Runtime $Runtime) -lt $deadline) {
        $partialFiles = @(Get-DeviceListExportPartialDownloadFiles -Directory $Directory)
        if ($partialFiles.Count -gt 0) {
            Invoke-DeviceListExportDownloadSleepMilliseconds -Runtime $Runtime -Milliseconds 500
            continue
        }

        $csvFiles = @(Get-DeviceListExportDownloadedCsvCandidates -Directory $Directory -FileNamePattern $FileNamePattern)
        $candidate = Resolve-DeviceListExportSingleDownloadedCsvCandidate -CsvFiles $csvFiles -Directory $Directory

        if ($null -ne $candidate) {
            $stableCandidate = Resolve-DeviceListExportStableDownloadedCsvCandidate `
                -CandidateFile $candidate `
                -Directory $Directory `
                -FileNamePattern $FileNamePattern `
                -StableSeconds $StableSeconds `
                -Runtime $Runtime

            if ($null -ne $stableCandidate) {
                return $stableCandidate
            }
        }

        Invoke-DeviceListExportDownloadSleepMilliseconds -Runtime $Runtime -Milliseconds 500
    }

    throw "CSVダウンロード完了待ちがタイムアウトしました。Directory=$Directory Pattern=$FileNamePattern"
}

function Rename-DeviceListExportDownloadedCsv {
    param(
        [Parameter(Mandatory)][System.IO.FileInfo]$CsvFile,
        [Parameter(Mandatory)][string]$DestinationDirectory,
        [Parameter(Mandatory)][string]$FileNameTemplate,
        [Parameter(Mandatory)][string]$TimestampText
    )

    if ([string]::Compare([string]$CsvFile.Extension, '.csv', $true) -ne 0) {
        throw "ダウンロード成果物の拡張子がCSVではありません: $($CsvFile.FullName)"
    }

    if ($CsvFile.Length -le 0) {
        throw "ダウンロード成果物CSVが0 byteです: $($CsvFile.FullName)"
    }

    if (-not (Test-DeviceListExportFileReady -Path $CsvFile.FullName)) {
        throw "ダウンロード成果物CSVを読み取り専有で開けません。まだ未完了の可能性があります: $($CsvFile.FullName)"
    }

    if (-not (Test-Path -LiteralPath $DestinationDirectory)) {
        New-Item -ItemType Directory -Path $DestinationDirectory -Force | Out-Null
    }

    $safeTimestamp = ConvertTo-DeviceListExportSafeFileNamePart -Value $TimestampText
    $fileName = [string]::Format($FileNameTemplate, $safeTimestamp)
    if ([string]::IsNullOrWhiteSpace($fileName) -or $fileName -notlike '*.csv') {
        throw "DeviceListExport 出力ファイル名テンプレートは .csv 名を生成する必要があります: $FileNameTemplate"
    }

    foreach ($invalidChar in [System.IO.Path]::GetInvalidFileNameChars()) {
        if ($fileName.IndexOf($invalidChar) -ge 0) {
            throw "DeviceListExport 出力ファイル名に使用できない文字が含まれています: $fileName"
        }
    }

    $destinationPath = Join-Path $DestinationDirectory $fileName
    $destinationPath = Get-DeviceListExportUniqueFilePath -Path $destinationPath
    Move-Item -LiteralPath $CsvFile.FullName -Destination $destinationPath -ErrorAction Stop

    $renamed = Get-Item -LiteralPath $destinationPath
    if ($renamed.Length -le 0) {
        throw "リネーム後CSVが0 byteです: $destinationPath"
    }

    return $renamed
}
