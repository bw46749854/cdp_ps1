$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

function New-ScanTargetSyncWorkflowState {
    param([AllowNull()]$Timing = $null)

    return [pscustomobject]@{
        FailureRows           = @()
        CsvErrorRowsForExport = @()
        EndCsvExportCompleted = $false
        Timing                = $Timing
    }
}

function Get-ScanTargetSyncWorkflowTimestampText {
    param([AllowNull()]$State)

    if ($State -and $State.Timing -and ($State.Timing.TimestampText -is [scriptblock])) {
        return (& $State.Timing.TimestampText)
    }

    return ''
}

function Add-ScanTargetSyncFailureRow {
    param(
        [Parameter(Mandatory)]$State,
        [object]$FailureRow
    )

    if ($null -eq $FailureRow) { return }

    $timestampProperty = $FailureRow.PSObject.Properties['Timestamp']
    if (-not $timestampProperty) {
        $FailureRow | Add-Member -NotePropertyName 'Timestamp' -NotePropertyValue (Get-ScanTargetSyncWorkflowTimestampText -State $State)
    }
    elseif ([string]::IsNullOrWhiteSpace([string]$timestampProperty.Value)) {
        $timestampProperty.Value = Get-ScanTargetSyncWorkflowTimestampText -State $State
    }

    $rows = @($State.FailureRows)
    $rows += $FailureRow
    $State.FailureRows = @($rows)
}
