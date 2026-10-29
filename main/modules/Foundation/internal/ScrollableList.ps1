$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

function New-ScrollableListState {
    param([int]$TotalCount = 0)
    return [pscustomobject]@{
        TotalCount = $TotalCount
        Processed = @{}
        LoopCount = 0
        SameScrollCount = 0
    }
}

function Assert-ScrollableListOperations {
    param([Parameter(Mandatory)]$Operations)
    foreach ($name in @('GetVisibleRows','GetRowKey','ProcessRow','ScrollDown')) {
        if (-not ($Operations.PSObject.Properties.Name -contains $name)) {
            throw "ScrollableList Operations契約違反: 必須操作がありません: $name"
        }
        if (-not ($Operations.$name -is [scriptblock])) {
            throw "ScrollableList Operations契約違反: $name は scriptblock である必要があります。"
        }
    }
}

function New-ScrollableListRuntime {
    return [pscustomobject]@{
        SleepMilliseconds = { param([int]$Milliseconds) Start-Sleep -Milliseconds $Milliseconds }
    }
}

function Assert-ScrollableListRuntime {
    param([Parameter(Mandatory)]$Runtime)

    if (-not ($Runtime.PSObject.Properties.Name -contains 'SleepMilliseconds')) {
        throw "ScrollableList Runtime契約違反: SleepMilliseconds が定義されていません。"
    }
    if (-not ($Runtime.SleepMilliseconds -is [scriptblock])) {
        throw "ScrollableList Runtime契約違反: SleepMilliseconds は scriptblock である必要があります。"
    }
}

function Resolve-ScrollableListRuntime {
    param([AllowNull()]$Runtime = $null)

    if (-not $Runtime) {
        $Runtime = New-ScrollableListRuntime
    }
    Assert-ScrollableListRuntime -Runtime $Runtime
    return $Runtime
}

function Get-UnprocessedVisibleRows {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Rows,
        [Parameter(Mandatory)][hashtable]$Processed,
        [Parameter(Mandatory)][scriptblock]$GetRowKey
    )

    $result = @()
    foreach ($row in $Rows) {
        $key = [string](& $GetRowKey $row)
        if ([string]::IsNullOrWhiteSpace($key)) { continue }
        if (-not $Processed.ContainsKey($key)) { $result += $row }
    }
    return $result
}

function Get-ScrollableListVisibleRowsStep {
    param(
        [Parameter(Mandatory)]$Operations,
        [Parameter(Mandatory)][string]$EmptyRowsMessage
    )

    $rows = @(& $Operations.GetVisibleRows)
    if ($rows.Count -eq 0) { throw $EmptyRowsMessage }
    return $rows
}

function Invoke-ScrollableListUnprocessedRowsStep {
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)]$Rows,
        [Parameter(Mandatory)]$Operations
    )

    $unprocessedRows = @(Get-UnprocessedVisibleRows -Rows $Rows -Processed $State.Processed -GetRowKey $Operations.GetRowKey)
    foreach ($row in $unprocessedRows) {
        $key = [string](& $Operations.GetRowKey $row)
        if ([string]::IsNullOrWhiteSpace($key) -or $State.Processed.ContainsKey($key)) { continue }
        try { & $Operations.ProcessRow $row }
        finally { $State.Processed[$key] = $true }
    }
    return $unprocessedRows.Count
}

function Test-ScrollableListScrollMoved {
    param([AllowNull()]$ScrollResult = $null)

    if ($ScrollResult -and ($ScrollResult.moved -eq $true -or $ScrollResult.changed -eq $true)) {
        return $true
    }
    return $false
}

function Invoke-ScrollableListScrollStep {
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)]$Operations,
        [Parameter(Mandatory)]$Runtime,
        [AllowNull()]$Logger,
        [int]$SameScrollLimit
    )

    $scrollResult = & $Operations.ScrollDown
    & $Runtime.SleepMilliseconds 700
    $moved = Test-ScrollableListScrollMoved -ScrollResult $scrollResult

    if ($moved) {
        $State.SameScrollCount = 0
        Write-FoundationLog -Logger $Logger -Level Info -Message "下方向へスクロールしました。"
        return $true
    }

    $State.SameScrollCount++
    Write-FoundationLog -Logger $Logger -Level Info -Message "スクロール位置が変化しませんでした。sameScrollCount=$($State.SameScrollCount)"
    if ($State.SameScrollCount -ge $SameScrollLimit) {
        Write-FoundationLog -Logger $Logger -Level Info -Message "新規行がなく、これ以上スクロールできないため、走査を終了します。"
        return $false
    }

    return $true
}

function Assert-ScrollableListProgress {
    param(
        [Parameter(Mandatory)]$State,
        [int]$MaxScanLoops
    )

    if ($State.LoopCount -gt $MaxScanLoops) {
        throw "最大走査ループ数 $MaxScanLoops を超過しました。処理済み=$($State.Processed.Count) 期待件数=$($State.TotalCount)"
    }
}

function Complete-ScrollableListWorkflow {
    param([Parameter(Mandatory)]$State)
    return [pscustomobject]@{
        ProcessedCount = $State.Processed.Count
        TotalCount = $State.TotalCount
        LoopCount = $State.LoopCount
        Completed = ($State.Processed.Count -ge $State.TotalCount)
        ProcessedKeys = $State.Processed.Keys
    }
}

function Invoke-ScrollableListWorkflow {
    param(
        [Parameter(Mandatory)][int]$TotalCount,
        [Parameter(Mandatory)]$Operations,
        [object]$Logger = $script:FoundationLogger,
        [int]$MaxScanLoops = 500,
        [int]$SameScrollLimit = 2,
        [string]$EmptyRowsMessage = "表示行を取得できませんでした。",
        [AllowNull()]$Runtime = $null
    )

    Assert-ScrollableListOperations -Operations $Operations
    $runtimePort = Resolve-ScrollableListRuntime -Runtime $Runtime
    $state = New-ScrollableListState -TotalCount $TotalCount

    for ($loop = 0; $loop -lt $MaxScanLoops; $loop++) {
        $state.LoopCount = $loop + 1

        if ($state.Processed.Count -ge $TotalCount) {
            Write-FoundationLog -Logger $Logger -Level Info -Message "期待件数 $TotalCount 件に到達したため、走査を終了します。"
            break
        }

        $rows = @(Get-ScrollableListVisibleRowsStep -Operations $Operations -EmptyRowsMessage $EmptyRowsMessage)
        $processedInLoop = Invoke-ScrollableListUnprocessedRowsStep -State $state -Rows $rows -Operations $Operations
        if ($processedInLoop -gt 0) { continue }

        $shouldContinue = Invoke-ScrollableListScrollStep -State $state -Operations $Operations -Runtime $runtimePort -Logger $Logger -SameScrollLimit $SameScrollLimit
        if (-not $shouldContinue) { break }
    }

    Assert-ScrollableListProgress -State $state -MaxScanLoops $MaxScanLoops
    return Complete-ScrollableListWorkflow -State $state
}
