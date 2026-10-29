$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。


function Open-FoundationPage {
    param(
        [Parameter(Mandatory)][string]$DebuggerUrl,
        [int]$ConnectTimeoutSeconds = 15,
        [int]$CommandTimeoutSeconds = 30,
        [AllowNull()][object]$Runtime
    )

    $targetArgs = @{ DebuggerUrl = $DebuggerUrl }
    if ($PSBoundParameters.ContainsKey('Runtime')) {
        $targetArgs.Runtime = $Runtime
    }

    $wsUrl = Get-TargetPageWebSocketUrl @targetArgs

    $connectionArgs = @{
        WebSocketUrl = $wsUrl
        ConnectTimeoutSeconds = $ConnectTimeoutSeconds
        CommandTimeoutSeconds = $CommandTimeoutSeconds
    }
    if ($PSBoundParameters.ContainsKey('Runtime')) {
        $connectionArgs.Runtime = $Runtime
    }

    $session = Open-CDPConnection @connectionArgs

    return [pscustomobject]@{
        DebuggerUrl = $DebuggerUrl
        WebSocketUrl = $wsUrl
        CdpSession = $session
    }
}


function Open-FoundationPageMatchingIdentity {
    param(
        [Parameter(Mandatory)][string]$DebuggerUrl,
        [Parameter(Mandatory)][scriptblock]$PageIdentityMatcher,
        [int]$ConnectTimeoutSeconds = 15,
        [int]$CommandTimeoutSeconds = 30,
        [AllowNull()][object]$Runtime
    )

    $targetArgs = @{
        DebuggerUrl = $DebuggerUrl
        PageIdentityMatcher = $PageIdentityMatcher
        ConnectTimeoutSeconds = $ConnectTimeoutSeconds
        CommandTimeoutSeconds = $CommandTimeoutSeconds
    }
    if ($PSBoundParameters.ContainsKey('Runtime')) {
        $targetArgs.Runtime = $Runtime
    }

    $wsUrl = Get-TargetPageWebSocketUrlMatchingIdentity @targetArgs

    $connectionArgs = @{
        WebSocketUrl = $wsUrl
        ConnectTimeoutSeconds = $ConnectTimeoutSeconds
        CommandTimeoutSeconds = $CommandTimeoutSeconds
    }
    if ($PSBoundParameters.ContainsKey('Runtime')) {
        $connectionArgs.Runtime = $Runtime
    }

    $session = Open-CDPConnection @connectionArgs

    return [pscustomobject]@{
        DebuggerUrl = $DebuggerUrl
        WebSocketUrl = $wsUrl
        CdpSession = $session
    }
}

function Invoke-FoundationJavaScript {
    param(
        [Parameter(Mandatory)][string]$Expression,
        [int]$TimeoutSeconds = 30
    )

    return Invoke-CDPJS -Expression $Expression -TimeoutSeconds $TimeoutSeconds
}

function Wait-FoundationJavaScript {
    param(
        [Parameter(Mandatory)][string]$Expression,
        [int]$TimeoutSeconds = 10,
        [string]$Description = "JavaScript condition"
    )

    Wait-CDPJS -Expression $Expression -TimeoutSeconds $TimeoutSeconds -Description $Description
}

function Set-FoundationDownloadDirectory {
    param(
        [Parameter(Mandatory)][string]$Directory,
        [AllowNull()][object]$Runtime
    )

    $args = @{ Directory = $Directory }
    if ($PSBoundParameters.ContainsKey('Runtime')) {
        $args.Runtime = $Runtime
    }

    Set-CDPDownloadDirectory @args
}
