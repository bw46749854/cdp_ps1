$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

# ============================================================
# CDP runtime and transport ports
#   Concrete browser/CDP dependencies are gathered here so CDP
#   protocol code can depend on a small runtime contract.
# ============================================================

function Get-CDPCallbackScriptBlock {
    param(
        [AllowNull()][object]$Owner,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$OwnerName
    )

    if (-not $Owner) {
        throw "$OwnerName が設定されていません。"
    }

    $callback = $Owner.$Name

    if ($callback -isnot [scriptblock]) {
        throw "$OwnerName.$Name は scriptblock である必要があります。"
    }

    return $callback
}

function New-CDPWebSocketTransport {
    return [pscustomobject]@{
        NewWebSocket = {
            New-Object System.Net.WebSockets.ClientWebSocket
        }
        NewCancellationTokenSource = {
            New-Object System.Threading.CancellationTokenSource
        }
        Connect = {
            param(
                [Parameter(Mandatory)][object]$Session,
                [Parameter(Mandatory)][string]$WebSocketUrl,
                [Parameter(Mandatory)][int]$TimeoutMilliseconds,
                [Parameter(Mandatory)][string]$Description
            )

            $connectTask = $Session.WebSocket.ConnectAsync([Uri]$WebSocketUrl, $Session.CancellationTokenSource.Token)
            Wait-CDPTask `
                -Task $connectTask `
                -TimeoutMilliseconds $TimeoutMilliseconds `
                -Description $Description `
                -Session $Session
        }
        SendText = {
            param(
                [Parameter(Mandatory)][object]$Session,
                [Parameter(Mandatory)][string]$Text,
                [Parameter(Mandatory)][int]$TimeoutMilliseconds,
                [Parameter(Mandatory)][string]$Description
            )

            $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
            $segment = New-Object "System.ArraySegment[System.Byte]" -ArgumentList (, $bytes)
            $sendTask = $Session.WebSocket.SendAsync(
                $segment,
                [System.Net.WebSockets.WebSocketMessageType]::Text,
                $true,
                $Session.CancellationTokenSource.Token
            )

            Wait-CDPTask `
                -Task $sendTask `
                -TimeoutMilliseconds $TimeoutMilliseconds `
                -Description $Description `
                -Session $Session
        }
        ReceiveText = {
            param(
                [Parameter(Mandatory)][object]$Session,
                [Parameter(Mandatory)][int]$TimeoutMilliseconds,
                [Parameter(Mandatory)][string]$Description
            )

            $runtime = Resolve-CDPRuntime -Runtime $null -Session $Session
            $nowCallback = Get-CDPCallbackScriptBlock -Owner $runtime.Timing -Name 'Now' -OwnerName 'CDP Runtime.Timing'
            $buffer = New-Object byte[] 1048576
            $ms = New-Object System.IO.MemoryStream
            $deadline = (& $nowCallback).AddMilliseconds($TimeoutMilliseconds)

            do {
                $remainingMilliseconds = Get-RemainingMilliseconds -Deadline $deadline -Runtime $runtime

                if ($remainingMilliseconds -le 0) {
                    Stop-CDPConnectionDueToTimeout -Session $Session
                    throw "CDPタイムアウト: $Description / WebSocket受信待ちが期限を超過しました。"
                }

                $segment = New-Object "System.ArraySegment[System.Byte]" -ArgumentList (, $buffer)
                $receiveTask = $Session.WebSocket.ReceiveAsync($segment, $Session.CancellationTokenSource.Token)

                Wait-CDPTask `
                    -Task $receiveTask `
                    -TimeoutMilliseconds $remainingMilliseconds `
                    -Description $Description `
                    -Session $Session

                $result = $receiveTask.Result

                if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
                    return $null
                }

                $ms.Write($buffer, 0, $result.Count)
            }
            while (-not $result.EndOfMessage)

            return [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
        }
        Close = {
            param(
                [Parameter(Mandatory)][object]$Session,
                [Parameter(Mandatory)][int]$TimeoutMilliseconds,
                [Parameter(Mandatory)][string]$Description
            )

            if ($Session.WebSocket -and $Session.WebSocket.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
                $closeTask = $Session.WebSocket.CloseAsync(
                    [System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure,
                    "Done",
                    [System.Threading.CancellationToken]::None
                )

                Wait-CDPTask `
                    -Task $closeTask `
                    -TimeoutMilliseconds $TimeoutMilliseconds `
                    -Description $Description `
                    -Session $Session
            }
        }
        Abort = {
            param([AllowNull()][object]$Session)

            try {
                if ($Session -and $Session.CancellationTokenSource) {
                    $Session.CancellationTokenSource.Cancel()
                }
            }
            catch {
                # timeout の原因例外を優先するため、後始末の失敗は握り潰す。
            }

            try {
                if ($Session -and $Session.WebSocket) {
                    $Session.WebSocket.Abort()
                }
            }
            catch {
                # timeout の原因例外を優先するため、後始末の失敗は握り潰す。
            }
        }
        Dispose = {
            param([AllowNull()][object]$Session)

            if (-not $Session) {
                return
            }

            if ($Session.WebSocket) {
                $Session.WebSocket.Dispose()
                $Session.WebSocket = $null
            }

            if ($Session.CancellationTokenSource) {
                $Session.CancellationTokenSource.Dispose()
                $Session.CancellationTokenSource = $null
            }
        }
    }
}

function New-CDPHttpClientPort {
    return [pscustomobject]@{
        GetContent = {
            param(
                [Parameter(Mandatory)][string]$Uri,
                [Parameter(Mandatory)][int]$TimeoutSeconds
            )

            Invoke-WebRequest -Uri $Uri -UseBasicParsing -TimeoutSec $TimeoutSeconds |
                Select-Object -ExpandProperty Content
        }
    }
}

function New-CDPConsolePort {
    return [pscustomobject]@{
        WriteLine = {
            param([AllowNull()][object]$Message = '')
            Write-Host $Message
        }
        WriteWarning = {
            param([AllowNull()][object]$Message = '')
            Write-Warning $Message
        }
    }
}

function New-CDPTimingPort {
    return [pscustomobject]@{
        Now = {
            Get-Date
        }
        SleepMilliseconds = {
            param([int]$Milliseconds)
            Start-Sleep -Milliseconds $Milliseconds
        }
    }
}

function New-CDPRuntime {
    param(
        [AllowNull()][object]$Transport,
        [AllowNull()][object]$HttpClient,
        [AllowNull()][object]$Console,
        [AllowNull()][object]$Timing
    )

    if (-not $Transport) {
        $Transport = New-CDPWebSocketTransport
    }

    if (-not $HttpClient) {
        $HttpClient = New-CDPHttpClientPort
    }

    if (-not $Console) {
        $Console = New-CDPConsolePort
    }

    if (-not $Timing) {
        $Timing = New-CDPTimingPort
    }

    $runtime = [pscustomobject]@{
        Transport = $Transport
        HttpClient = $HttpClient
        Console = $Console
        Timing = $Timing
    }

    Assert-CDPRuntimeContract -Runtime $runtime
    return $runtime
}

function Assert-CDPRuntimeContract {
    param(
        [AllowNull()][object]$Runtime
    )

    if (-not $Runtime) {
        throw "CDP Runtime が設定されていません。"
    }

    foreach ($name in @('NewWebSocket', 'NewCancellationTokenSource', 'Connect', 'SendText', 'ReceiveText', 'Close', 'Abort', 'Dispose')) {
        [void](Get-CDPCallbackScriptBlock -Owner $Runtime.Transport -Name $name -OwnerName 'CDP Runtime.Transport')
    }

    [void](Get-CDPCallbackScriptBlock -Owner $Runtime.HttpClient -Name 'GetContent' -OwnerName 'CDP Runtime.HttpClient')
    [void](Get-CDPCallbackScriptBlock -Owner $Runtime.Console -Name 'WriteLine' -OwnerName 'CDP Runtime.Console')
    [void](Get-CDPCallbackScriptBlock -Owner $Runtime.Console -Name 'WriteWarning' -OwnerName 'CDP Runtime.Console')
    [void](Get-CDPCallbackScriptBlock -Owner $Runtime.Timing -Name 'Now' -OwnerName 'CDP Runtime.Timing')
    [void](Get-CDPCallbackScriptBlock -Owner $Runtime.Timing -Name 'SleepMilliseconds' -OwnerName 'CDP Runtime.Timing')
}

function Resolve-CDPRuntime {
    param(
        [AllowNull()][object]$Runtime,
        [AllowNull()][object]$Session
    )

    if ($Runtime) {
        Assert-CDPRuntimeContract -Runtime $Runtime
        return $Runtime
    }

    if ($Session -and $Session.PSObject.Properties.Name -contains 'Runtime' -and $Session.Runtime) {
        Assert-CDPRuntimeContract -Runtime $Session.Runtime
        return $Session.Runtime
    }

    return New-CDPRuntime
}
