$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

# ============================================================
# CDP session state
#   CDP session object, default session cache, and session contract checks.
# ============================================================

$script:CdpDefaultSession = $null

function New-CDPSessionState {
    param(
        [int]$CommandTimeoutSeconds = 30,
        [AllowNull()][object]$Runtime
    )

    return [pscustomobject]@{
        WebSocket = $null
        CancellationTokenSource = $null
        Runtime = $Runtime
        CommandId = 0
        CommandTimeoutSeconds = $CommandTimeoutSeconds
        IsClosed = $false
    }
}

function Get-CDPCommandTimeoutSeconds {
    param(
        [AllowNull()]
        [object]$Session = $script:CdpDefaultSession
    )

    if ($Session -and $Session.CommandTimeoutSeconds) {
        return [int]$Session.CommandTimeoutSeconds
    }

    return 30
}

function Assert-CDPSession {
    param(
        [AllowNull()]
        [object]$Session = $script:CdpDefaultSession
    )

    if (-not $Session -or -not $Session.WebSocket) {
        throw "CDP WebSocket が初期化されていません。"
    }

    return $Session
}
