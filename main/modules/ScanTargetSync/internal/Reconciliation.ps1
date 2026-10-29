$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

function Get-ScanTargetSyncDuplicateEndpointErrors {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$CsvRows,

        [Parameter(Mandatory)]
        [string]$Timestamp
    )

    $duplicateGroups = @(
        $CsvRows |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_."ホスト名") } |
            Group-Object -Property "ホスト名" |
            Where-Object { $_.Count -gt 1 }
    )

    $rows = @()

    foreach ($group in $duplicateGroups) {
        foreach ($row in @($group.Group)) {
            $rows += [pscustomobject]@{
                Endpoint      = $row."ホスト名"
                User          = $row."利用者"
                Status        = $row."接続状態"
                LastConnected = $row."最終通信日時"
                ScanStarted   = $row."手動スキャンの開始"
                ScanCompleted = $row."手動スキャンの完了"
                ElapsedDays   = $null
                Reason        = "ホスト名がCSV内で重複しています: $($group.Name)=$($group.Count)件"
                Timestamp     = $Timestamp
            }
        }
    }

    return @($rows)
}

function New-ScanTargetSyncSyncRow {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$SourceRow,

        [Parameter(Mandatory)]
        [bool]$DesiredChecked,

        [Parameter(Mandatory)]
        [string]$Classification
    )

    $desiredState = if ($DesiredChecked) { "ON" } else { "OFF" }

    [pscustomobject]@{
        Endpoint        = $SourceRow.Endpoint
        User            = $SourceRow.User
        Status          = $SourceRow.Status
        LastConnected   = $SourceRow.LastConnected
        ScanStarted     = $SourceRow.ScanStarted
        ScanCompleted   = $SourceRow.ScanCompleted
        ElapsedDays     = $SourceRow.ElapsedDays
        Reason          = $SourceRow.Reason
        DesiredChecked  = $DesiredChecked
        DesiredState    = $desiredState
        Classification  = $Classification
    }
}

function Get-ScanTargetSyncSyncRows {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$OnRows,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$OffRows,

        [AllowEmptyCollection()]
        [object[]]$CsvErrorRows = @()
    )

    if (@($CsvErrorRows).Count -gt 0) {
        throw "CSVデータエラー行がある状態ではチェック状態整合対象を生成できません。CDP接続前にCSVデータエラーCSVを出力して停止してください。CSVデータエラー件数=$(@($CsvErrorRows).Count)"
    }

    $syncRows = @()

    foreach ($row in @($OnRows)) {
        if ([string]::IsNullOrWhiteSpace($row.Endpoint)) { continue }
        $syncRows += New-ScanTargetSyncSyncRow -SourceRow $row -DesiredChecked $true -Classification "checkedOn"
    }

    foreach ($row in @($OffRows)) {
        if ([string]::IsNullOrWhiteSpace($row.Endpoint)) { continue }
        $syncRows += New-ScanTargetSyncSyncRow -SourceRow $row -DesiredChecked $false -Classification "checkedOff"
    }

    return @($syncRows)
}

function Assert-UniqueScanTargetSyncSyncRows {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$SyncRows
    )

    $duplicates = @(
        $SyncRows |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_.Endpoint) } |
            Group-Object Endpoint |
            Where-Object { $_.Count -gt 1 }
    )

    if ($duplicates.Count -gt 0) {
        $details = @(
            $duplicates | ForEach-Object {
                $states = @($_.Group | ForEach-Object { "$($_.DesiredState)/$($_.Classification)" }) -join ","
                "$($_.Name)=$($_.Count)件[$states]"
            }
        ) -join "; "

        throw "CSV上のホスト名が重複しています。ON/OFF整合の誤操作防止のため停止します: $details"
    }
}

