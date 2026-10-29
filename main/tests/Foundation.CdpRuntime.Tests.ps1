$ErrorActionPreference = "Stop"
$repositoryRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$modulePath = Join-Path $repositoryRoot 'modules\Foundation\Foundation.psm1'
Import-Module -Name $modulePath -Force

InModuleScope Foundation {
    Describe 'Foundation CDP Runtime.evaluate facade' {
        BeforeEach {
            $script:CapturedCdpMethod = $null
            $script:CapturedCdpParams = $null
            $script:CapturedCdpTimeoutSeconds = $null
        }

        It 'sends Runtime.evaluate with safe evaluation options and returns by-value result' {
            Mock Send-CDPCommand {
                param(
                    [string]$Method,
                    [hashtable]$Params,
                    [int]$TimeoutSeconds
                )

                $script:CapturedCdpMethod = $Method
                $script:CapturedCdpParams = $Params
                $script:CapturedCdpTimeoutSeconds = $TimeoutSeconds

                return [pscustomobject]@{
                    result = [pscustomobject]@{
                        result = [pscustomobject]@{
                            value = [pscustomobject]@{
                                ok = $true
                                value = 42
                            }
                        }
                    }
                }
            }

            $result = Invoke-CDPJS -Expression '(() => 42)()' -TimeoutSeconds 7

            $script:CapturedCdpMethod | Should -Be 'Runtime.evaluate'
            $script:CapturedCdpParams.expression | Should -Be '(() => 42)()'
            $script:CapturedCdpParams.returnByValue | Should -Be $true
            $script:CapturedCdpParams.awaitPromise | Should -Be $true
            $script:CapturedCdpParams.userGesture | Should -Be $true
            $script:CapturedCdpTimeoutSeconds | Should -Be 7
            $result.ok | Should -Be $true
            $result.value | Should -Be 42
        }

        It 'surfaces JavaScript exception descriptions from Runtime.evaluate responses' {
            Mock Send-CDPCommand {
                return [pscustomobject]@{
                    result = [pscustomobject]@{
                        exceptionDetails = [pscustomobject]@{
                            text = 'Uncaught'
                            exception = [pscustomobject]@{
                                description = 'TypeError: cannot read properties of undefined'
                            }
                        }
                        result = [pscustomobject]@{
                            value = $null
                        }
                    }
                }
            }

            try {
                Invoke-CDPJS -Expression '(() => { throw new TypeError("bad") })()' | Out-Null
                throw 'Invoke-CDPJS unexpectedly succeeded.'
            }
            catch {
                $_.Exception.Message | Should -Match 'JavaScript error: TypeError: cannot read properties of undefined'
            }
        }
    }

    Describe 'Foundation CDP download directory fallback' {
        It 'falls back from Browser.setDownloadBehavior to Page.setDownloadBehavior' {
            $script:CdpDownloadMethods = @()
            $script:CdpDownloadPaths = @()

            Mock Initialize-FoundationOutputDirectory {
                param([string]$Directory, [string]$Purpose)
                $Purpose | Should -Be 'CDPダウンロード'
                New-Item -ItemType Directory -Path $Directory -Force | Out-Null
                return $Directory
            }

            Mock Send-CDPCommand {
                param([string]$Method, [hashtable]$Params, [AllowNull()][object]$Runtime)

                $script:CdpDownloadMethods += $Method
                $script:CdpDownloadPaths += [string]$Params.downloadPath

                if ($Method -eq 'Browser.setDownloadBehavior') {
                    throw 'Browser domain unavailable'
                }

                return [pscustomobject]@{ ok = $true }
            }

            $downloadDirectory = Join-Path $TestDrive 'downloads'
            Set-CDPDownloadDirectory -Directory $downloadDirectory

            Test-Path -LiteralPath $downloadDirectory | Should -Be $true
            $script:CdpDownloadMethods.Count | Should -Be 2
            $script:CdpDownloadMethods[0] | Should -Be 'Browser.setDownloadBehavior'
            $script:CdpDownloadMethods[1] | Should -Be 'Page.setDownloadBehavior'
            $script:CdpDownloadPaths[0] | Should -Be $downloadDirectory
            $script:CdpDownloadPaths[1] | Should -Be $downloadDirectory
            Should -Invoke -CommandName Send-CDPCommand -Times 2 -Exactly
        }
    }

    Describe 'Foundation CDP session lifecycle' {
        It 'returns the CDP session opened for the target page' {
            $session = [pscustomobject]@{ Name = 'session-1' }

            Mock Get-TargetPageWebSocketUrl {
                param([string]$DebuggerUrl)
                $DebuggerUrl | Should -Be 'http://localhost:9222/json'
                return 'ws://localhost/devtools/page/1'
            }

            Mock Open-CDPConnection {
                param(
                    [string]$WebSocketUrl,
                    [int]$ConnectTimeoutSeconds,
                    [int]$CommandTimeoutSeconds
                )

                $WebSocketUrl | Should -Be 'ws://localhost/devtools/page/1'
                $ConnectTimeoutSeconds | Should -Be 3
                $CommandTimeoutSeconds | Should -Be 11
                return $session
            }

            $page = Open-FoundationPage `
                -DebuggerUrl 'http://localhost:9222/json' `
                -ConnectTimeoutSeconds 3 `
                -CommandTimeoutSeconds 11

            $page.WebSocketUrl | Should -Be 'ws://localhost/devtools/page/1'
            [object]::ReferenceEquals($page.CdpSession, $session) | Should -Be $true
        }

        It 'returns the CDP session opened for the page-identity matched target page' {
            $session = [pscustomobject]@{ Name = 'matched-session' }
            $probe = { $true }

            Mock Get-TargetPageWebSocketUrlMatchingIdentity {
                param(
                    [string]$DebuggerUrl,
                    [scriptblock]$PageIdentityMatcher,
                    [int]$ConnectTimeoutSeconds,
                    [int]$CommandTimeoutSeconds
                )

                $DebuggerUrl | Should -Be 'http://localhost:9222/json'
                [object]::ReferenceEquals($PageIdentityMatcher, $probe) | Should -Be $true
                $ConnectTimeoutSeconds | Should -Be 5
                $CommandTimeoutSeconds | Should -Be 13
                return 'ws://localhost/devtools/page/matched'
            }

            Mock Open-CDPConnection {
                param(
                    [string]$WebSocketUrl,
                    [int]$ConnectTimeoutSeconds,
                    [int]$CommandTimeoutSeconds
                )

                $WebSocketUrl | Should -Be 'ws://localhost/devtools/page/matched'
                $ConnectTimeoutSeconds | Should -Be 5
                $CommandTimeoutSeconds | Should -Be 13
                return $session
            }

            $page = Open-FoundationPageMatchingIdentity `
                -DebuggerUrl 'http://localhost:9222/json' `
                -ConnectTimeoutSeconds 5 `
                -CommandTimeoutSeconds 13 `
                -PageIdentityMatcher $probe

            $page.WebSocketUrl | Should -Be 'ws://localhost/devtools/page/matched'
            [object]::ReferenceEquals($page.CdpSession, $session) | Should -Be $true
        }

        It 'closes the page-owned CDP session when closing a run context' {
            $session = [pscustomobject]@{ Name = 'session-1' }
            $script:ClosedCdpSession = $null
            $script:ClosedQuietly = $false

            Mock Close-CDPConnection {
                param(
                    [AllowNull()][object]$Session,
                    [switch]$Quiet
                )

                $script:ClosedCdpSession = $Session
                $script:ClosedQuietly = $Quiet.IsPresent
            }

            Mock Close-FoundationLogger {}

            $context = [pscustomobject]@{
                Page = [pscustomobject]@{
                    CdpSession = $session
                }
                Logger = $null
            }

            Close-FoundationRunContext -Context $context

            [object]::ReferenceEquals($script:ClosedCdpSession, $session) | Should -Be $true
            $script:ClosedQuietly | Should -Be $true
        }
    }

    Describe 'Foundation CDP public runtime facades' {
        It 'delegates JavaScript evaluation to the split CDP command helper' {
            $script:CapturedExpression = $null
            $script:CapturedTimeoutSeconds = $null

            Mock Invoke-CDPJS {
                param([string]$Expression, [int]$TimeoutSeconds)
                $script:CapturedExpression = $Expression
                $script:CapturedTimeoutSeconds = $TimeoutSeconds
                return [pscustomobject]@{ ok = $true }
            }

            $result = Invoke-FoundationJavaScript -Expression '1 + 1' -TimeoutSeconds 12

            $script:CapturedExpression | Should -Be '1 + 1'
            $script:CapturedTimeoutSeconds | Should -Be 12
            $result.ok | Should -Be $true
            Should -Invoke -CommandName Invoke-CDPJS -Times 1 -Exactly
        }

        It 'delegates JavaScript waiting to the split CDP command helper' {
            $script:CapturedWaitExpression = $null
            $script:CapturedWaitTimeoutSeconds = $null
            $script:CapturedWaitDescription = $null

            Mock Wait-CDPJS {
                param([string]$Expression, [int]$TimeoutSeconds, [string]$Description)
                $script:CapturedWaitExpression = $Expression
                $script:CapturedWaitTimeoutSeconds = $TimeoutSeconds
                $script:CapturedWaitDescription = $Description
            }

            Wait-FoundationJavaScript `
                -Expression 'window.ready === true' `
                -TimeoutSeconds 13 `
                -Description 'ready check'

            $script:CapturedWaitExpression | Should -Be 'window.ready === true'
            $script:CapturedWaitTimeoutSeconds | Should -Be 13
            $script:CapturedWaitDescription | Should -Be 'ready check'
            Should -Invoke -CommandName Wait-CDPJS -Times 1 -Exactly
        }
    }


    Describe 'Foundation CDP target discovery seam' {
        BeforeAll {
            function New-TestCDPBrowserRuntimeFixture {
                param(
                    [Parameter(Mandatory)][string]$TargetInfoJson,
                    [AllowNull()][scriptblock]$GetContent
                )

                $state = [pscustomobject]@{
                    Output = New-Object System.Collections.ArrayList
                    Warnings = New-Object System.Collections.ArrayList
                    RequestedUri = $null
                    RequestedTimeoutSeconds = $null
                }

                if (-not $GetContent) {
                    $GetContent = {
                        param($Uri, $TimeoutSeconds)
                        $state.RequestedUri = $Uri
                        $state.RequestedTimeoutSeconds = $TimeoutSeconds
                        return $TargetInfoJson
                    }.GetNewClosure()
                }

                $runtime = New-CDPRuntime `
                    -Transport (New-CDPWebSocketTransport) `
                    -HttpClient ([pscustomobject]@{ GetContent = $GetContent }) `
                    -Console ([pscustomobject]@{
                        WriteLine = {
                            param($Message)
                            [void]$state.Output.Add([string]$Message)
                        }.GetNewClosure()
                        WriteWarning = {
                            param($Message)
                            [void]$state.Warnings.Add([string]$Message)
                        }.GetNewClosure()
                    }) `
                    -Timing ([pscustomobject]@{ Now = { Get-Date }; SleepMilliseconds = { param([int]$Milliseconds) } })

                return [pscustomobject]@{
                    Runtime = $runtime
                    State = $state
                }
            }
        }

        It 'selects one target page while filtering browser-internal targets' {
            $targets = @(
                [pscustomobject]@{ type = 'page'; title = 'DevTools'; url = 'devtools://devtools/bundled/inspector.html'; webSocketDebuggerUrl = 'ws://devtools' },
                [pscustomobject]@{ type = 'page'; title = 'Extension'; url = 'chrome-extension://abc/index.html'; webSocketDebuggerUrl = 'ws://extension' },
                [pscustomobject]@{ type = 'page'; title = 'Devices'; url = 'https://example.test/devices'; webSocketDebuggerUrl = 'ws://page' },
                [pscustomobject]@{ type = 'service_worker'; title = 'Worker'; url = 'https://example.test/sw.js'; webSocketDebuggerUrl = 'ws://worker' }
            )

            $target = Select-FoundationPageTarget -TargetInfo $targets

            $target.title | Should -Be 'Devices'
            $target.webSocketDebuggerUrl | Should -Be 'ws://page'
        }

        It 'retrieves target json through the runtime HTTP port and writes selected target through the runtime console port' {
            $targetInfoJson = @(
                [pscustomobject]@{
                    type = 'page'
                    title = 'Devices'
                    url = 'https://example.test/devices'
                    webSocketDebuggerUrl = 'ws://localhost/devtools/page/1'
                }
            ) | ConvertTo-Json -Depth 5
            $fixture = New-TestCDPBrowserRuntimeFixture -TargetInfoJson $targetInfoJson

            $wsUrl = Get-TargetPageWebSocketUrl `
                -DebuggerUrl 'http://localhost:9222/json' `
                -Runtime $fixture.Runtime

            $wsUrl | Should -Be 'ws://localhost/devtools/page/1'
            $fixture.State.RequestedUri | Should -Be 'http://localhost:9222/json'
            $fixture.State.RequestedTimeoutSeconds | Should -Be 10
            ($fixture.State.Output -join "`n") | Should -Match '操作対象ページ:'
            ($fixture.State.Output -join "`n") | Should -Match 'Devices'
        }

        It 'reports ambiguous page targets through the runtime console before throwing' {
            $targetInfoJson = @(
                [pscustomobject]@{ type = 'page'; title = 'One'; url = 'https://example.test/one'; webSocketDebuggerUrl = 'ws://one' },
                [pscustomobject]@{ type = 'page'; title = 'Two'; url = 'https://example.test/two'; webSocketDebuggerUrl = 'ws://two' }
            ) | ConvertTo-Json -Depth 5
            $fixture = New-TestCDPBrowserRuntimeFixture -TargetInfoJson $targetInfoJson

            { Get-TargetPageWebSocketUrl -DebuggerUrl 'http://localhost:9222/json' -Runtime $fixture.Runtime } |
                Should -Throw '対象タブだけを残し、操作対象の page が1つだけの状態で再実行してください。'
            ($fixture.State.Output -join "`n") | Should -Match '複数見つかりました'
            ($fixture.State.Output -join "`n") | Should -Match 'One'
            ($fixture.State.Output -join "`n") | Should -Match 'Two'
        }


        It 'selects one page target from multiple tabs when exactly one page identity matcher matches' {
            $targets = @(
                [pscustomobject]@{ type = 'page'; title = 'Mail'; url = 'https://example.test/mail'; webSocketDebuggerUrl = 'ws://mail' },
                [pscustomobject]@{ type = 'page'; title = 'InstalledAppExport'; url = 'https://example.test/asset'; webSocketDebuggerUrl = 'ws://asset' }
            )
            $fixture = New-TestCDPBrowserRuntimeFixture -TargetInfoJson '[]'
            $script:OpenedTargets = @()
            $script:ClosedTargets = @()

            Mock Open-CDPConnection {
                param([string]$WebSocketUrl, [int]$ConnectTimeoutSeconds, [int]$CommandTimeoutSeconds, [AllowNull()][object]$Runtime)
                $script:OpenedTargets += $WebSocketUrl
                return [pscustomobject]@{ WebSocketUrl = $WebSocketUrl }
            }

            Mock Close-CDPConnection {
                param([object]$Session, [switch]$Quiet, [AllowNull()][object]$Runtime)
                $script:ClosedTargets += $Session.WebSocketUrl
            }

            $probe = {
                param($PageTarget, $Session)
                return [pscustomobject]@{
                    Matched = ($PageTarget.title -eq 'InstalledAppExport')
                    Reason = 'test probe'
                }
            }

            $target = Select-FoundationPageTargetMatchingIdentity `
                -TargetInfo $targets `
                -PageIdentityMatcher $probe `
                -Runtime $fixture.Runtime

            $target.title | Should -Be 'InstalledAppExport'
            ($script:OpenedTargets -join '|') | Should -Be 'ws://mail|ws://asset'
            ($script:ClosedTargets -join '|') | Should -Be 'ws://mail|ws://asset'
        }

        It 'rejects multiple tabs when no page target matches the page identity matcher' {
            $targets = @(
                [pscustomobject]@{ type = 'page'; title = 'Mail'; url = 'https://example.test/mail'; webSocketDebuggerUrl = 'ws://mail' },
                [pscustomobject]@{ type = 'page'; title = 'Wiki'; url = 'https://example.test/wiki'; webSocketDebuggerUrl = 'ws://wiki' }
            )
            $fixture = New-TestCDPBrowserRuntimeFixture -TargetInfoJson '[]'

            Mock Open-CDPConnection { param([string]$WebSocketUrl, [int]$ConnectTimeoutSeconds, [int]$CommandTimeoutSeconds, [AllowNull()][object]$Runtime) return [pscustomobject]@{ WebSocketUrl = $WebSocketUrl } }
            Mock Close-CDPConnection { param([object]$Session, [switch]$Quiet, [AllowNull()][object]$Runtime) }

            $probe = { [pscustomobject]@{ Matched = $false; Reason = 'not target page' } }

            { Select-FoundationPageTargetMatchingIdentity -TargetInfo $targets -PageIdentityMatcher $probe -Runtime $fixture.Runtime } |
                Should -Throw '対象画面のページ識別に一致するタブが見つかりませんでした*'
            ($fixture.State.Output -join "`n") | Should -Match 'not matched'
            ($fixture.State.Output -join "`n") | Should -Match 'Mail'
            ($fixture.State.Output -join "`n") | Should -Match 'Wiki'
        }

        It 'treats page identity matcher execution exceptions as fatal infrastructure errors' {
            $targets = @(
                [pscustomobject]@{ type = 'page'; title = 'InstalledAppExport'; url = 'https://example.test/asset'; webSocketDebuggerUrl = 'ws://asset' }
            )
            $fixture = New-TestCDPBrowserRuntimeFixture -TargetInfoJson '[]'
            $script:ClosedTargets = @()

            Mock Open-CDPConnection {
                param([string]$WebSocketUrl, [int]$ConnectTimeoutSeconds, [int]$CommandTimeoutSeconds, [AllowNull()][object]$Runtime)
                return [pscustomobject]@{ WebSocketUrl = $WebSocketUrl }
            }
            Mock Close-CDPConnection {
                param([object]$Session, [switch]$Quiet, [AllowNull()][object]$Runtime)
                $script:ClosedTargets += $Session.WebSocketUrl
            }

            $probe = { throw 'probe function is not bound' }

            { Select-FoundationPageTargetMatchingIdentity -TargetInfo $targets -PageIdentityMatcher $probe -Runtime $fixture.Runtime } |
                Should -Throw '*PageIdentityMatcher*probe function is not bound*'
            ($fixture.State.Output -join "`n") | Should -Match 'matcher の実行中に例外'
            ($script:ClosedTargets -join '|') | Should -Be 'ws://asset'
        }

        It 'rejects multiple tabs when more than one page target matches the page identity matcher' {
            $targets = @(
                [pscustomobject]@{ type = 'page'; title = 'InstalledAppExport A'; url = 'https://example.test/asset-a'; webSocketDebuggerUrl = 'ws://asset-a' },
                [pscustomobject]@{ type = 'page'; title = 'InstalledAppExport B'; url = 'https://example.test/asset-b'; webSocketDebuggerUrl = 'ws://asset-b' }
            )
            $fixture = New-TestCDPBrowserRuntimeFixture -TargetInfoJson '[]'

            Mock Open-CDPConnection { param([string]$WebSocketUrl, [int]$ConnectTimeoutSeconds, [int]$CommandTimeoutSeconds, [AllowNull()][object]$Runtime) return [pscustomobject]@{ WebSocketUrl = $WebSocketUrl } }
            Mock Close-CDPConnection { param([object]$Session, [switch]$Quiet, [AllowNull()][object]$Runtime) }

            $probe = { [pscustomobject]@{ Matched = $true; Reason = 'target page' } }

            { Select-FoundationPageTargetMatchingIdentity -TargetInfo $targets -PageIdentityMatcher $probe -Runtime $fixture.Runtime } |
                Should -Throw '対象画面のページ識別に一致するタブが複数見つかりました*'
            ($fixture.State.Output -join "`n") | Should -Match 'matched'
            ($fixture.State.Output -join "`n") | Should -Match 'InstalledAppExport A'
            ($fixture.State.Output -join "`n") | Should -Match 'InstalledAppExport B'
        }
    }
}
