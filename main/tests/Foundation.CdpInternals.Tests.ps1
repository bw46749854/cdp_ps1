$ErrorActionPreference = "Stop"
$repositoryRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$modulePath = Join-Path $repositoryRoot 'modules\Foundation\Foundation.psm1'
Import-Module -Name $modulePath -Force

InModuleScope Foundation {
    Describe 'Foundation CDP internal split contracts' {
        BeforeEach {
            $script:CdpDefaultSession = $null
        }

        It 'creates an isolated CDP session state with the configured command timeout' {
            $session = New-CDPSessionState -CommandTimeoutSeconds 17

            $session.WebSocket | Should -BeNullOrEmpty
            $session.CancellationTokenSource | Should -BeNullOrEmpty
            $session.CommandId | Should -Be 0
            $session.CommandTimeoutSeconds | Should -Be 17
            $session.IsClosed | Should -Be $false
        }
        It 'uses the session command timeout when available and falls back to the default value' {
            $session = New-CDPSessionState -CommandTimeoutSeconds 9

            Get-CDPCommandTimeoutSeconds -Session $session | Should -Be 9
            Get-CDPCommandTimeoutSeconds -Session $null | Should -Be 30
        }

        It 'rejects CDP operations without an initialized WebSocket session' {
            $session = New-CDPSessionState

            { Assert-CDPSession -Session $session } | Should -Throw 'CDP WebSocket が初期化されていません。'
        }

        It 'returns zero remaining milliseconds for an elapsed deadline' {
            $deadline = (Get-Date).AddMilliseconds(-250)

            Get-RemainingMilliseconds -Deadline $deadline | Should -Be 0
        }
    }

    Describe 'Foundation CDP runtime and transport boundary' {
        BeforeAll {
            function New-TestCDPTransportFixture {
                param(
                    [AllowNull()][object[]]$ReceiveMessages = @()
                )

                $state = [pscustomobject]@{
                    WebSocket = [pscustomobject]@{ Name = 'fake-websocket' }
                    CancellationTokenSource = [pscustomobject]@{ Name = 'fake-cts' }
                    ConnectedWebSocketUrl = $null
                    ConnectTimeoutMilliseconds = $null
                    ConnectDescription = $null
                    SentTexts = New-Object System.Collections.ArrayList
                    SendTimeoutMilliseconds = New-Object System.Collections.ArrayList
                    SendDescriptions = New-Object System.Collections.ArrayList
                    ReceiveMessages = New-Object System.Collections.ArrayList
                    ReceiveCount = 0
                    ReceiveTimeoutMilliseconds = New-Object System.Collections.ArrayList
                    ReceiveDescriptions = New-Object System.Collections.ArrayList
                    Closed = $false
                    CloseTimeoutMilliseconds = $null
                    CloseDescription = $null
                    Aborted = $false
                    Disposed = $false
                }

                foreach ($message in @($ReceiveMessages)) {
                    [void]$state.ReceiveMessages.Add([string]$message)
                }

                $transport = [pscustomobject]@{
                    NewWebSocket = {
                        return $state.WebSocket
                    }.GetNewClosure()
                    NewCancellationTokenSource = {
                        return $state.CancellationTokenSource
                    }.GetNewClosure()
                    Connect = {
                        param($Session, $WebSocketUrl, $TimeoutMilliseconds, $Description)
                        $state.ConnectedWebSocketUrl = $WebSocketUrl
                        $state.ConnectTimeoutMilliseconds = $TimeoutMilliseconds
                        $state.ConnectDescription = $Description
                    }.GetNewClosure()
                    SendText = {
                        param($Session, $Text, $TimeoutMilliseconds, $Description)
                        [void]$state.SentTexts.Add([string]$Text)
                        [void]$state.SendTimeoutMilliseconds.Add([int]$TimeoutMilliseconds)
                        [void]$state.SendDescriptions.Add([string]$Description)
                    }.GetNewClosure()
                    ReceiveText = {
                        param($Session, $TimeoutMilliseconds, $Description)
                        [void]$state.ReceiveTimeoutMilliseconds.Add([int]$TimeoutMilliseconds)
                        [void]$state.ReceiveDescriptions.Add([string]$Description)
                        $state.ReceiveCount++

                        if ($state.ReceiveCount -le $state.ReceiveMessages.Count) {
                            $messageIndex = $state.ReceiveCount - 1
                            return [string]$state.ReceiveMessages[$messageIndex]
                        }

                        return $null
                    }.GetNewClosure()
                    Close = {
                        param($Session, $TimeoutMilliseconds, $Description)
                        $state.Closed = $true
                        $state.CloseTimeoutMilliseconds = $TimeoutMilliseconds
                        $state.CloseDescription = $Description
                    }.GetNewClosure()
                    Abort = {
                        param($Session)
                        $state.Aborted = $true
                    }.GetNewClosure()
                    Dispose = {
                        param($Session)
                        $state.Disposed = $true

                        if ($Session) {
                            $Session.WebSocket = $null
                            $Session.CancellationTokenSource = $null
                        }
                    }.GetNewClosure()
                }

                return [pscustomobject]@{
                    Transport = $transport
                    State = $state
                }
            }

            function New-TestCDPRuntimePort {
                param(
                    [AllowNull()][object]$Transport
                )

                if (-not $Transport) {
                    $Transport = (New-TestCDPTransportFixture).Transport
                }

                return New-CDPRuntime `
                    -Transport $Transport `
                    -HttpClient ([pscustomobject]@{ GetContent = { param($Uri, $TimeoutSeconds) '[]' } }) `
                    -Console ([pscustomobject]@{
                        WriteLine = { param($Message) }
                        WriteWarning = { param($Message) }
                    }) `
                    -Timing ([pscustomobject]@{ Now = { Get-Date }; SleepMilliseconds = { param([int]$Milliseconds) } })
            }
        }

        BeforeEach {
            $script:CdpDefaultSession = $null
        }

        It 'rejects runtimes that do not provide the full transport contract' {
            $runtime = [pscustomobject]@{
                Transport = [pscustomobject]@{
                    NewWebSocket = { }
                }
                HttpClient = [pscustomobject]@{ GetContent = { param($Uri, $TimeoutSeconds) '' } }
                Console = [pscustomobject]@{
                    WriteLine = { param($Message) }
                    WriteWarning = { param($Message) }
                }
                Timing = [pscustomobject]@{ Now = { Get-Date }; SleepMilliseconds = { param([int]$Milliseconds) } }
            }

            { Assert-CDPRuntimeContract -Runtime $runtime } | Should -Throw 'CDP Runtime.Transport.NewCancellationTokenSource は scriptblock である必要があります。'
        }

        It 'opens CDP connections through an injected transport instead of constructing WebSocket details in protocol code' {
            $fixture = New-TestCDPTransportFixture
            $runtime = New-TestCDPRuntimePort -Transport $fixture.Transport

            $session = Open-CDPConnection `
                -WebSocketUrl 'ws://localhost/devtools/page/1' `
                -ConnectTimeoutSeconds 4 `
                -CommandTimeoutSeconds 13 `
                -Runtime $runtime

            $fixture.State.ConnectedWebSocketUrl | Should -Be 'ws://localhost/devtools/page/1'
            $fixture.State.ConnectTimeoutMilliseconds | Should -Be 4000
            $fixture.State.ConnectDescription | Should -Be 'CDP WebSocket 接続'
            $session.CommandTimeoutSeconds | Should -Be 13
            $session.WebSocket.Name | Should -Be 'fake-websocket'
            $session.CancellationTokenSource.Name | Should -Be 'fake-cts'
            [object]::ReferenceEquals($session.Runtime, $runtime) | Should -Be $true
        }

        It 'sends command payloads and correlates responses through the injected transport' {
            $fixture = New-TestCDPTransportFixture -ReceiveMessages @(
                '{"method":"Runtime.consoleAPICalled","params":{}}',
                '{"id":1,"result":{"ok":true}}'
            )
            $runtime = New-TestCDPRuntimePort -Transport $fixture.Transport
            $session = New-CDPSessionState -CommandTimeoutSeconds 5 -Runtime $runtime
            $session.WebSocket = $fixture.State.WebSocket
            $session.CancellationTokenSource = $fixture.State.CancellationTokenSource

            $response = Send-CDPCommand `
                -Method 'Runtime.evaluate' `
                -Params @{ expression = '1 + 1' } `
                -Session $session `
                -Runtime $runtime

            $fixture.State.SentTexts.Count | Should -Be 1
            $fixture.State.SendDescriptions[0] | Should -Be 'CDP送信: method=Runtime.evaluate id=1'
            $payload = $fixture.State.SentTexts[0] | ConvertFrom-Json
            $payload.id | Should -Be 1
            $payload.method | Should -Be 'Runtime.evaluate'
            $payload.params.expression | Should -Be '1 + 1'
            $fixture.State.ReceiveCount | Should -Be 2
            $fixture.State.ReceiveDescriptions[0] | Should -Be 'CDP受信: method=Runtime.evaluate id=1'
            $response.result.ok | Should -Be $true
        }

        It 'closes and disposes CDP sessions through the injected transport' {
            $fixture = New-TestCDPTransportFixture
            $runtime = New-TestCDPRuntimePort -Transport $fixture.Transport
            $session = New-CDPSessionState -CommandTimeoutSeconds 5 -Runtime $runtime
            $session.WebSocket = $fixture.State.WebSocket
            $session.CancellationTokenSource = $fixture.State.CancellationTokenSource
            $script:CdpDefaultSession = $session

            Close-CDPConnection -Session $session

            $fixture.State.Closed | Should -Be $true
            $fixture.State.Disposed | Should -Be $true
            $fixture.State.CloseTimeoutMilliseconds | Should -Be 3000
            $fixture.State.CloseDescription | Should -Be 'CDP WebSocket クローズ'
            $session.IsClosed | Should -Be $true
            $session.WebSocket | Should -BeNullOrEmpty
            $session.CancellationTokenSource | Should -BeNullOrEmpty
            $script:CdpDefaultSession | Should -BeNullOrEmpty
        }
    }
}
