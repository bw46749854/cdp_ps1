$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

# ============================================================
# CDP connection lifecycle
#   WebSocket connection, timeout handling, and close behavior.
# ============================================================

function Stop-CDPConnectionDueToTimeout {
    param(
        [AllowNull()]
        [object]$Session = $script:CdpDefaultSession,

        [AllowNull()]
        [object]$Runtime
    )

    $runtime = Resolve-CDPRuntime -Runtime $Runtime -Session $Session
    $abort = Get-CDPCallbackScriptBlock -Owner $runtime.Transport -Name 'Abort' -OwnerName 'CDP Runtime.Transport'
    & $abort $Session
}

function Wait-CDPTask {
    param(
        [Parameter(Mandatory)]
        [System.Threading.Tasks.Task]$Task,

        [Parameter(Mandatory)]
        [int]$TimeoutMilliseconds,

        [Parameter(Mandatory)]
        [string]$Description,

        [AllowNull()]
        [object]$Session = $script:CdpDefaultSession,

        [AllowNull()]
        [object]$Runtime
    )

    if ($TimeoutMilliseconds -lt 1) {
        $TimeoutMilliseconds = 1
    }

    try {
        $completed = $Task.Wait($TimeoutMilliseconds)
    }
    catch [System.AggregateException] {
        $inner = $_.Exception.InnerException
        if ($inner) {
            throw "CDP処理に失敗しました: $Description / $($inner.Message)"
        }

        throw "CDP処理に失敗しました: $Description / $($_.Exception.Message)"
    }
    catch {
        throw "CDP処理に失敗しました: $Description / $($_.Exception.Message)"
    }

    if (-not $completed) {
        Stop-CDPConnectionDueToTimeout -Session $Session -Runtime $Runtime
        throw "CDPタイムアウト: $Description / timeoutMilliseconds=$TimeoutMilliseconds"
    }
}

function Get-RemainingMilliseconds {
    param(
        [Parameter(Mandatory)]
        [datetime]$Deadline,

        [AllowNull()]
        [object]$Runtime
    )

    $runtime = Resolve-CDPRuntime -Runtime $Runtime -Session $null
    $nowCallback = Get-CDPCallbackScriptBlock -Owner $runtime.Timing -Name 'Now' -OwnerName 'CDP Runtime.Timing'
    $now = & $nowCallback

    $remaining = [int][Math]::Ceiling(($Deadline - $now).TotalMilliseconds)

    if ($remaining -lt 1) {
        return 0
    }

    return $remaining
}

function Open-CDPConnection {
    param(
        [Parameter(Mandatory)]
        [string]$WebSocketUrl,

        [int]$ConnectTimeoutSeconds = 15,

        [int]$CommandTimeoutSeconds = 30,

        [AllowNull()]
        [object]$Runtime
    )

    $runtime = Resolve-CDPRuntime -Runtime $Runtime -Session $null

    Close-CDPConnection -Quiet

    $session = New-CDPSessionState -CommandTimeoutSeconds $CommandTimeoutSeconds -Runtime $runtime

    $newWebSocket = Get-CDPCallbackScriptBlock -Owner $runtime.Transport -Name 'NewWebSocket' -OwnerName 'CDP Runtime.Transport'
    $newCancellationTokenSource = Get-CDPCallbackScriptBlock -Owner $runtime.Transport -Name 'NewCancellationTokenSource' -OwnerName 'CDP Runtime.Transport'
    $connect = Get-CDPCallbackScriptBlock -Owner $runtime.Transport -Name 'Connect' -OwnerName 'CDP Runtime.Transport'

    $session.WebSocket = & $newWebSocket
    $session.CancellationTokenSource = & $newCancellationTokenSource
    $script:CdpDefaultSession = $session

    & $connect `
        $session `
        $WebSocketUrl `
        ($ConnectTimeoutSeconds * 1000) `
        'CDP WebSocket 接続'

    return $session
}

function Close-CDPConnection {
    param(
        [AllowNull()]
        [object]$Session = $script:CdpDefaultSession,

        [switch]$Quiet,

        [AllowNull()]
        [object]$Runtime
    )

    if (-not $Session) {
        return
    }

    $runtime = Resolve-CDPRuntime -Runtime $Runtime -Session $Session
    $close = Get-CDPCallbackScriptBlock -Owner $runtime.Transport -Name 'Close' -OwnerName 'CDP Runtime.Transport'
    $dispose = Get-CDPCallbackScriptBlock -Owner $runtime.Transport -Name 'Dispose' -OwnerName 'CDP Runtime.Transport'
    $writeWarning = Get-CDPCallbackScriptBlock -Owner $runtime.Console -Name 'WriteWarning' -OwnerName 'CDP Runtime.Console'

    if ($Session.WebSocket) {
        try {
            & $close $Session 3000 'CDP WebSocket クローズ'
        }
        catch {
            if (-not $Quiet) {
                & $writeWarning "WebSocket close failed: $($_.Exception.Message)"
            }
        }

        & $dispose $Session
    }
    elseif ($Session.CancellationTokenSource) {
        & $dispose $Session
    }

    $Session.IsClosed = $true

    if ([object]::ReferenceEquals($Session, $script:CdpDefaultSession)) {
        $script:CdpDefaultSession = $null
    }
}
