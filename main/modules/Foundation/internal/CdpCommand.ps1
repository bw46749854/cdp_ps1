$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

# ============================================================
# CDP command dispatch
#   CDP protocol orchestration depends on CdpRuntime transport
#   ports instead of concrete WebSocket primitives.
# ============================================================

function New-CDPCommandRequest {
    param(
        [Parameter(Mandatory)]
        [int]$Id,

        [Parameter(Mandatory)]
        [string]$Method,

        [hashtable]$Params = @{}
    )

    return @{
        id     = $Id
        method = $Method
        params = $Params
    } | ConvertTo-Json -Compress -Depth 30
}

function ConvertFrom-CDPMessageJson {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter(Mandatory)]
        [string]$Description
    )

    try {
        return $Message | ConvertFrom-Json
    }
    catch {
        throw "CDP応答の JSON 解析に失敗しました: $Description / $($_.Exception.Message)"
    }
}

function Test-CDPResponseMatchesCommandId {
    param(
        [AllowNull()][object]$Response,
        [Parameter(Mandatory)][int]$Id
    )

    if (-not $Response) {
        return $false
    }

    return ($Response.id -eq $Id)
}

function Assert-CDPCommandSucceeded {
    param(
        [Parameter(Mandatory)][object]$Response,
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][int]$Id
    )

    if ($Response.error) {
        throw "CDP error: method=$Method id=$Id message=$($Response.error.message)"
    }

    return $Response
}

function Receive-CDPMessage {
    param(
        [Parameter(Mandatory)]
        [int]$TimeoutMilliseconds,

        [Parameter(Mandatory)]
        [string]$Description,

        [AllowNull()]
        [object]$Session = $script:CdpDefaultSession,

        [AllowNull()]
        [object]$Runtime
    )

    $Session = Assert-CDPSession -Session $Session
    $runtime = Resolve-CDPRuntime -Runtime $Runtime -Session $Session
    $receiveText = Get-CDPCallbackScriptBlock -Owner $runtime.Transport -Name 'ReceiveText' -OwnerName 'CDP Runtime.Transport'

    return (& $receiveText $Session $TimeoutMilliseconds $Description)
}

function Send-CDPCommand {
    param(
        [Parameter(Mandatory)]
        [string]$Method,

        [hashtable]$Params = @{},

        [int]$TimeoutSeconds = 0,

        [AllowNull()]
        [object]$Session = $script:CdpDefaultSession,

        [AllowNull()]
        [object]$Runtime
    )

    $Session = Assert-CDPSession -Session $Session
    $runtime = Resolve-CDPRuntime -Runtime $Runtime -Session $Session

    if ($TimeoutSeconds -lt 1) {
        $TimeoutSeconds = Get-CDPCommandTimeoutSeconds -Session $Session
    }

    $Session.CommandId++
    $id = $Session.CommandId
    $nowCallback = Get-CDPCallbackScriptBlock -Owner $runtime.Timing -Name 'Now' -OwnerName 'CDP Runtime.Timing'
    $deadline = (& $nowCallback).AddSeconds($TimeoutSeconds)

    $payload = New-CDPCommandRequest -Id $id -Method $Method -Params $Params
    $sendDescription = "CDP送信: method=$Method id=$id"
    $sendTimeoutMilliseconds = Get-RemainingMilliseconds -Deadline $deadline -Runtime $runtime

    if ($sendTimeoutMilliseconds -le 0) {
        Stop-CDPConnectionDueToTimeout -Session $Session -Runtime $runtime
        throw "CDPタイムアウト: $sendDescription / 送信前に期限を超過しました。"
    }

    $sendText = Get-CDPCallbackScriptBlock -Owner $runtime.Transport -Name 'SendText' -OwnerName 'CDP Runtime.Transport'
    & $sendText $Session $payload $sendTimeoutMilliseconds $sendDescription

    while ($true) {
        $remainingMilliseconds = Get-RemainingMilliseconds -Deadline $deadline -Runtime $runtime

        if ($remainingMilliseconds -le 0) {
            $description = "CDP応答待ち: method=$Method id=$id"
            Stop-CDPConnectionDueToTimeout -Session $Session -Runtime $runtime
            throw "CDPタイムアウト: $description / timeoutSeconds=$TimeoutSeconds"
        }

        $message = Receive-CDPMessage `
            -TimeoutMilliseconds $remainingMilliseconds `
            -Description "CDP受信: method=$Method id=$id" `
            -Session $Session `
            -Runtime $runtime

        if (-not $message) {
            throw "CDP WebSocket が閉じられました。method=$Method id=$id"
        }

        $obj = ConvertFrom-CDPMessageJson -Message $message -Description "method=$Method id=$id"

        # CDPイベントは id を持たないため無視する。
        if (Test-CDPResponseMatchesCommandId -Response $obj -Id $id) {
            return Assert-CDPCommandSucceeded -Response $obj -Method $Method -Id $id
        }
    }
}

function Invoke-CDPJS {
    param(
        [Parameter(Mandatory)]
        [string]$Expression,

        [int]$TimeoutSeconds = 0,

        [AllowNull()]
        [object]$Session = $script:CdpDefaultSession,

        [AllowNull()]
        [object]$Runtime
    )

    if ($TimeoutSeconds -lt 1) {
        $TimeoutSeconds = Get-CDPCommandTimeoutSeconds -Session $Session
    }

    $commandArgs = @{
        Method = "Runtime.evaluate"
        Params = @{
            expression    = $Expression
            returnByValue = $true
            awaitPromise  = $true
            userGesture   = $true
        }
        TimeoutSeconds = $TimeoutSeconds
    }

    if ($PSBoundParameters.ContainsKey('Session')) {
        $commandArgs.Session = $Session
    }

    if ($PSBoundParameters.ContainsKey('Runtime')) {
        $commandArgs.Runtime = $Runtime
    }

    $res = Send-CDPCommand @commandArgs

    if ($res.result.exceptionDetails) {
        $details = $res.result.exceptionDetails
        $message = $details.text

        if ($details.exception) {
            if ($details.exception.description) {
                $message = $details.exception.description
            }
            elseif ($details.exception.value) {
                $message = $details.exception.value
            }
        }

        throw "JavaScript error: $message"
    }

    return $res.result.result.value
}

function Wait-CDPJS {
    param(
        [Parameter(Mandatory)]
        [string]$Expression,

        [int]$TimeoutSeconds = 10,

        [string]$Description = "JavaScript condition",

        [AllowNull()]
        [object]$Session = $script:CdpDefaultSession,

        [AllowNull()]
        [object]$Runtime = $null,

        [int]$PollIntervalMilliseconds = 250
    )

    $Session = Assert-CDPSession -Session $Session
    $runtime = Resolve-CDPRuntime -Runtime $Runtime -Session $Session
    $nowCallback = Get-CDPCallbackScriptBlock -Owner $runtime.Timing -Name 'Now' -OwnerName 'CDP Runtime.Timing'
    $sleepMilliseconds = Get-CDPCallbackScriptBlock -Owner $runtime.Timing -Name 'SleepMilliseconds' -OwnerName 'CDP Runtime.Timing'

    $deadline = (& $nowCallback).AddSeconds($TimeoutSeconds)
    $lastError = $null

    while ((& $nowCallback) -lt $deadline) {
        try {
            $remainingSeconds = [int][Math]::Ceiling(($deadline - (& $nowCallback)).TotalSeconds)

            if ($remainingSeconds -lt 1) {
                $remainingSeconds = 1
            }

            $value = Invoke-CDPJS `
                -Expression $Expression `
                -TimeoutSeconds $remainingSeconds `
                -Session $Session `
                -Runtime $runtime

            if ($value -eq $true) {
                return
            }
        }
        catch {
            # DOM構築中・画面遷移中・Angular再描画中の一時エラーは待機中だけ許容する。
            $lastError = $_.Exception.Message
        }

        if ((& $nowCallback) -lt $deadline) {
            & $sleepMilliseconds $PollIntervalMilliseconds
        }
    }

    if ($lastError) {
        throw "待機タイムアウト: $Description / last error: $lastError"
    }

    throw "待機タイムアウト: $Description"
}

function Wait-DomContractResult {
    param(
        [Parameter(Mandatory)]
        [string]$Expression,

        [int]$TimeoutSeconds = 20,

        [Parameter(Mandatory)]
        [string]$Description,

        [AllowNull()]
        [object]$Session = $script:CdpDefaultSession,

        [AllowNull()]
        [object]$Runtime = $null,

        [int]$PollIntervalMilliseconds = 250
    )

    $Session = Assert-CDPSession -Session $Session
    $runtime = Resolve-CDPRuntime -Runtime $Runtime -Session $Session
    $nowCallback = Get-CDPCallbackScriptBlock -Owner $runtime.Timing -Name 'Now' -OwnerName 'CDP Runtime.Timing'
    $sleepMilliseconds = Get-CDPCallbackScriptBlock -Owner $runtime.Timing -Name 'SleepMilliseconds' -OwnerName 'CDP Runtime.Timing'

    $deadline = (& $nowCallback).AddSeconds($TimeoutSeconds)
    $lastResult = $null
    $lastError = $null

    while ((& $nowCallback) -lt $deadline) {
        try {
            $remainingSeconds = [int][Math]::Ceiling(($deadline - (& $nowCallback)).TotalSeconds)

            if ($remainingSeconds -lt 1) {
                $remainingSeconds = 1
            }

            $result = Invoke-CDPJS `
                -Expression $Expression `
                -TimeoutSeconds $remainingSeconds `
                -Session $Session `
                -Runtime $runtime
            $lastResult = $result

            if ($result -and [int]$result.fatalCount -eq 0) {
                return $result
            }
        }
        catch {
            $lastError = $_.Exception.Message
        }

        if ((& $nowCallback) -lt $deadline) {
            & $sleepMilliseconds $PollIntervalMilliseconds
        }
    }

    if ($lastResult) {
        $formatted = Format-DomContractResult -Result $lastResult
        throw "待機タイムアウト: $Description`n$formatted"
    }

    if ($lastError) {
        throw "待機タイムアウト: $Description / last error: $lastError"
    }

    throw "待機タイムアウト: $Description"
}
