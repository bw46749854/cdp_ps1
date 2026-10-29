$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。


function Test-FoundationFatalError {
    param([AllowEmptyString()][string]$Message)

    if ([string]::IsNullOrWhiteSpace($Message)) { return $false }
    if ($Message -like '*CDPタイムアウト*') { return $true }
    if ($Message -like '*ClientWebSocket*') { return $true }
    if ($Message -like '*WebSocket*') { return $true }
    if ($Message -like '*破棄されたオブジェクト*') { return $true }
    if ($Message -like '*helper_not_registered*') { return $true }
    if ($Message -like '*DOM helper is not registered*') { return $true }
    if ($Message -like '*DOM helper method is not registered*') { return $true }
    return $false
}

