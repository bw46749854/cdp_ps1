$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

function Get-CheckboxDesiredStateDisplay {
    param([Parameter(Mandatory)][string]$DesiredState)
    if ($DesiredState -eq "ON") { return "ON（手動スキャン対象）" }
    if ($DesiredState -eq "OFF") { return "OFF（手動スキャン対象外）" }
    return $DesiredState
}

function Get-CheckboxChangeResultDisplay {
    param([Parameter(Mandatory)][pscustomobject]$Result)
    if ($Result.changed -eq $true) { return "変更済み" }
    if ($Result.alreadyAligned -eq $true) { return "変更不要" }
    return "目的状態確認済み"
}
