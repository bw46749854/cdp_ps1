$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

# ============================================================
# CDP browser/page operations
#   Target page resolution and browser/page-scoped CDP operations.
# ============================================================

function ConvertFrom-CDPTargetInfoJson {
    param(
        [Parameter(Mandatory)]
        [string]$TargetInfoJson
    )

    try {
        return $TargetInfoJson | ConvertFrom-Json
    }
    catch {
        throw "CDP target 情報の JSON 解析に失敗しました。詳細: $($_.Exception.Message)"
    }
}

function Get-CDPOperablePageTargetCandidates {
    param(
        [AllowNull()][object[]]$TargetInfo
    )

    return @(
        $TargetInfo |
            Where-Object {
                $_.type -eq "page" -and
                -not [string]::IsNullOrWhiteSpace($_.webSocketDebuggerUrl) -and
                $_.url -notlike "chrome-extension://*" -and
                $_.url -notlike "devtools://*" -and
                $_.url -notlike "chrome://*" -and
                $_.url -notlike "edge://*" -and
                $_.title -notlike "Service Worker*"
            }
    )
}

function Select-FoundationPageTarget {
    param(
        [AllowNull()][object[]]$TargetInfo
    )

    $pageTargets = @(Get-CDPOperablePageTargetCandidates -TargetInfo $TargetInfo)

    if ($pageTargets.Count -eq 0) {
        throw "操作可能な page ターゲットが見つかりませんでした。対象画面を開いてから再実行してください。"
    }

    if ($pageTargets.Count -gt 1) {
        throw "対象タブだけを残し、操作対象の page が1つだけの状態で再実行してください。"
    }

    $pageTarget = $pageTargets[0]
    $wsUrl = [string]$pageTarget.webSocketDebuggerUrl

    if ([string]::IsNullOrWhiteSpace($wsUrl)) {
        throw "page ターゲットの webSocketDebuggerUrl を取得できませんでした。"
    }

    return $pageTarget
}

function Write-CDPPageTargetCandidates {
    param(
        [Parameter(Mandatory)][object[]]$PageTargets,
        [Parameter(Mandatory)][object]$Runtime
    )

    $writeLine = Get-CDPCallbackScriptBlock -Owner $Runtime.Console -Name 'WriteLine' -OwnerName 'CDP Runtime.Console'

    & $writeLine "操作対象候補の page ターゲットが複数見つかりました。誤操作防止のため停止します。"
    & $writeLine ""
    & $writeLine "検出された page ターゲット:"

    $tableText = @($PageTargets | Select-Object title, url | Format-Table -AutoSize | Out-String).TrimEnd()
    if ($tableText) {
        & $writeLine $tableText
    }

    & $writeLine ""
}

function Write-CDPSelectedPageTarget {
    param(
        [Parameter(Mandatory)][object]$PageTarget,
        [Parameter(Mandatory)][string]$WebSocketUrl,
        [Parameter(Mandatory)][object]$Runtime
    )

    $writeLine = Get-CDPCallbackScriptBlock -Owner $Runtime.Console -Name 'WriteLine' -OwnerName 'CDP Runtime.Console'

    & $writeLine "操作対象ページ:"
    & $writeLine "  Title: $($PageTarget.title)"
    & $writeLine "  URL  : $($PageTarget.url)"
    & $writeLine "  WS   : $WebSocketUrl"
    & $writeLine ""
}

function ConvertTo-CDPPageIdentityMatchOutcome {
    param(
        [AllowNull()][object]$MatchResult,
        [AllowEmptyString()][string]$DefaultReason = ''
    )

    if ($MatchResult -is [bool]) {
        return [pscustomobject]@{
            Matched = [bool]$MatchResult
            Reason = $DefaultReason
            Result = $MatchResult
        }
    }

    $matchedProperty = $null
    $reasonProperty = $null
    if ($null -ne $MatchResult) {
        $matchedProperty = $MatchResult.PSObject.Properties['Matched']
        $reasonProperty = $MatchResult.PSObject.Properties['Reason']
    }

    if ($null -ne $matchedProperty) {
        $reason = $DefaultReason
        if ($null -ne $reasonProperty -and -not [string]::IsNullOrWhiteSpace([string]$reasonProperty.Value)) {
            $reason = [string]$reasonProperty.Value
        }

        return [pscustomobject]@{
            Matched = ([bool]$matchedProperty.Value)
            Reason = $reason
            Result = $MatchResult
        }
    }

    $okProperty = $null
    if ($null -ne $MatchResult) {
        $okProperty = $MatchResult.PSObject.Properties['ok']
    }

    if ($null -ne $okProperty) {
        return [pscustomobject]@{
            Matched = ([bool]$okProperty.Value)
            Reason = $DefaultReason
            Result = $MatchResult
        }
    }

    return [pscustomobject]@{
        Matched = $false
        Reason = $DefaultReason
        Result = $MatchResult
    }
}

function Invoke-CDPPageIdentityMatcher {
    param(
        [Parameter(Mandatory)][scriptblock]$PageIdentityMatcher,
        [Parameter(Mandatory)][object]$PageTarget,
        [Parameter(Mandatory)][object]$Session
    )

    $matchResult = & $PageIdentityMatcher $PageTarget $Session
    return ConvertTo-CDPPageIdentityMatchOutcome -MatchResult $matchResult
}

function Write-CDPPageIdentityMatcherDiagnostics {
    param(
        [Parameter(Mandatory)][object[]]$MatchResults,
        [Parameter(Mandatory)][object]$Runtime,
        [Parameter(Mandatory)][string]$Message
    )

    $writeLine = Get-CDPCallbackScriptBlock -Owner $Runtime.Console -Name 'WriteLine' -OwnerName 'CDP Runtime.Console'

    & $writeLine $Message
    & $writeLine ''
    & $writeLine '検出された page ターゲットとページ識別結果:'

    foreach ($match in @($MatchResults)) {
        $target = $match.PageTarget
        $status = 'not matched'
        if ($match.Matched -eq $true) { $status = 'matched' }

        & $writeLine "  - Title : $($target.title)"
        & $writeLine "    URL   : $($target.url)"
        & $writeLine "    Match : $status"
        if (-not [string]::IsNullOrWhiteSpace([string]$match.Reason)) {
            & $writeLine "    Reason: $($match.Reason)"
        }
    }

    & $writeLine ''
}

function Select-FoundationPageTargetMatchingIdentity {
    param(
        [AllowNull()][object[]]$TargetInfo,
        [Parameter(Mandatory)][scriptblock]$PageIdentityMatcher,
        [int]$ConnectTimeoutSeconds = 15,
        [int]$CommandTimeoutSeconds = 30,
        [AllowNull()][object]$Runtime
    )

    $runtime = Resolve-CDPRuntime -Runtime $Runtime -Session $null
    $pageTargets = @(Get-CDPOperablePageTargetCandidates -TargetInfo $TargetInfo)

    if ($pageTargets.Count -eq 0) {
        throw '操作可能な page ターゲットが見つかりませんでした。対象画面を開いてから再実行してください。'
    }

    $matchResults = @()
    foreach ($pageTarget in $pageTargets) {
        $session = $null
        $sessionOpened = $false
        $wsUrl = [string]$pageTarget.webSocketDebuggerUrl
        try {
            $session = Open-CDPConnection `
                -WebSocketUrl $wsUrl `
                -ConnectTimeoutSeconds $ConnectTimeoutSeconds `
                -CommandTimeoutSeconds $CommandTimeoutSeconds `
                -Runtime $runtime
            $sessionOpened = $true

            $outcome = Invoke-CDPPageIdentityMatcher `
                -PageIdentityMatcher $PageIdentityMatcher `
                -PageTarget $pageTarget `
                -Session $session

            $matchResults += [pscustomobject]@{
                PageTarget = $pageTarget
                WebSocketUrl = $wsUrl
                Matched = ([bool]$outcome.Matched)
                Reason = [string]$outcome.Reason
                Result = $outcome.Result
            }
        }
        catch {
            if ($sessionOpened) {
                $matchResults += [pscustomobject]@{
                    PageTarget = $pageTarget
                    WebSocketUrl = $wsUrl
                    Matched = $false
                    Reason = $_.Exception.Message
                    Result = $null
                }

                Write-CDPPageIdentityMatcherDiagnostics `
                    -MatchResults $matchResults `
                    -Runtime $runtime `
                    -Message '対象画面のページ識別 matcher の実行中に例外が発生しました。'
                throw "対象画面のページ識別 matcher の実行中に例外が発生しました。Feature 側の PageIdentityMatcher 実装を確認してください。詳細: $($_.Exception.Message)"
            }

            $matchResults += [pscustomobject]@{
                PageTarget = $pageTarget
                WebSocketUrl = $wsUrl
                Matched = $false
                Reason = $_.Exception.Message
                Result = $null
            }
        }
        finally {
            if ($session) {
                Close-CDPConnection -Session $session -Quiet -Runtime $runtime
            }
        }
    }

    $matchedTargets = @($matchResults | Where-Object { $_.Matched -eq $true })

    if ($matchedTargets.Count -eq 0) {
        Write-CDPPageIdentityMatcherDiagnostics `
            -MatchResults $matchResults `
            -Runtime $runtime `
            -Message '対象画面のページ識別に一致するタブが見つかりませんでした。'
        throw '対象画面のページ識別に一致するタブが見つかりませんでした。対象ジョブの画面を開いてから再実行してください。'
    }

    if ($matchedTargets.Count -gt 1) {
        Write-CDPPageIdentityMatcherDiagnostics `
            -MatchResults $matchResults `
            -Runtime $runtime `
            -Message '対象画面のページ識別に一致するタブが複数見つかりました。'
        throw '対象画面のページ識別に一致するタブが複数見つかりました。どのタブを操作すべきか決定できないため停止します。同じ対象画面を複数タブで開いている場合は、1つだけ残してください。'
    }

    return $matchedTargets[0].PageTarget
}

function Get-TargetPageWebSocketUrl {
    param(
        [Parameter(Mandatory)]
        [string]$DebuggerUrl,

        [AllowNull()]
        [object]$Runtime
    )

    $runtime = Resolve-CDPRuntime -Runtime $Runtime -Session $null
    $getContent = Get-CDPCallbackScriptBlock -Owner $runtime.HttpClient -Name 'GetContent' -OwnerName 'CDP Runtime.HttpClient'

    try {
        $targetInfoJson = & $getContent $DebuggerUrl 10
        $targetInfo = ConvertFrom-CDPTargetInfoJson -TargetInfoJson $targetInfoJson
    }
    catch {
        throw "Edge / Chrome の CDP ポート 9222 に接続できません。ブラウザを --remote-debugging-port=9222 付きで起動してください。詳細: $($_.Exception.Message)"
    }

    $pageTargets = @(Get-CDPOperablePageTargetCandidates -TargetInfo $targetInfo)

    if ($pageTargets.Count -gt 1) {
        Write-CDPPageTargetCandidates -PageTargets $pageTargets -Runtime $runtime
    }

    $pageTarget = Select-FoundationPageTarget -TargetInfo $targetInfo
    $wsUrl = [string]$pageTarget.webSocketDebuggerUrl

    Write-CDPSelectedPageTarget -PageTarget $pageTarget -WebSocketUrl $wsUrl -Runtime $runtime

    return $wsUrl
}


function Get-TargetPageWebSocketUrlMatchingIdentity {
    param(
        [Parameter(Mandatory)]
        [string]$DebuggerUrl,

        [Parameter(Mandatory)]
        [scriptblock]$PageIdentityMatcher,

        [int]$ConnectTimeoutSeconds = 15,

        [int]$CommandTimeoutSeconds = 30,

        [AllowNull()]
        [object]$Runtime
    )

    $runtime = Resolve-CDPRuntime -Runtime $Runtime -Session $null
    $getContent = Get-CDPCallbackScriptBlock -Owner $runtime.HttpClient -Name 'GetContent' -OwnerName 'CDP Runtime.HttpClient'

    try {
        $targetInfoJson = & $getContent $DebuggerUrl 10
        $targetInfo = ConvertFrom-CDPTargetInfoJson -TargetInfoJson $targetInfoJson
    }
    catch {
        throw "Edge / Chrome の CDP ポート 9222 に接続できません。ブラウザを --remote-debugging-port=9222 付きで起動してください。詳細: $($_.Exception.Message)"
    }

    $pageTarget = Select-FoundationPageTargetMatchingIdentity `
        -TargetInfo $targetInfo `
        -PageIdentityMatcher $PageIdentityMatcher `
        -ConnectTimeoutSeconds $ConnectTimeoutSeconds `
        -CommandTimeoutSeconds $CommandTimeoutSeconds `
        -Runtime $runtime

    $wsUrl = [string]$pageTarget.webSocketDebuggerUrl
    if ([string]::IsNullOrWhiteSpace($wsUrl)) {
        throw 'page ターゲットの webSocketDebuggerUrl を取得できませんでした。'
    }

    Write-CDPSelectedPageTarget -PageTarget $pageTarget -WebSocketUrl $wsUrl -Runtime $runtime

    return $wsUrl
}

function Set-CDPDownloadDirectory {
    param(
        [Parameter(Mandatory)]
        [string]$Directory,

        [AllowNull()]
        [object]$Runtime
    )

    $runtime = Resolve-CDPRuntime -Runtime $Runtime -Session $script:CdpDefaultSession
    $writeLine = Get-CDPCallbackScriptBlock -Owner $runtime.Console -Name 'WriteLine' -OwnerName 'CDP Runtime.Console'
    $writeWarning = Get-CDPCallbackScriptBlock -Owner $runtime.Console -Name 'WriteWarning' -OwnerName 'CDP Runtime.Console'

    $resolvedPath = Initialize-FoundationOutputDirectory -Directory $Directory -Purpose "CDPダウンロード"

    try {
        Send-CDPCommand `
            -Method "Browser.setDownloadBehavior" `
            -Params @{
                behavior     = "allow"
                downloadPath = $resolvedPath
            } `
            -Runtime $runtime | Out-Null

        & $writeLine "CDPダウンロード先を設定しました: $resolvedPath"
        return
    }
    catch {
        & $writeWarning "Browser.setDownloadBehavior に失敗しました。Page.setDownloadBehavior を試行します。詳細: $($_.Exception.Message)"
    }

    Send-CDPCommand `
        -Method "Page.setDownloadBehavior" `
        -Params @{
            behavior     = "allow"
            downloadPath = $resolvedPath
        } `
        -Runtime $runtime | Out-Null

    & $writeLine "CDPダウンロード先を設定しました: $resolvedPath"
}
