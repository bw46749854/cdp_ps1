$ErrorActionPreference = "Stop"
$repositoryRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$modulePath = Join-Path $repositoryRoot 'modules\Foundation\Foundation.psm1'
Import-Module -Name $modulePath -Force

InModuleScope Foundation {
    Describe 'Foundation CDP command and transport abnormal paths' {
        BeforeAll {
            function New-TestCDPSequenceTimingPort {
                param(
                    [AllowNull()][object[]]$NowValues = @()
                )

                $state = [pscustomobject]@{
                    NowValues = New-Object System.Collections.ArrayList
                    NowCallCount = 0
                    SleptMilliseconds = New-Object System.Collections.ArrayList
                }

                foreach ($value in @($NowValues)) {
                    [void]$state.NowValues.Add([datetime]$value)
                }

                $timing = [pscustomobject]@{
                    Now = {
                        if ($state.NowValues.Count -gt 0) {
                            $index = $state.NowCallCount
                            if ($index -ge $state.NowValues.Count) {
                                $index = $state.NowValues.Count - 1
                            }

                            $state.NowCallCount++
                            return [datetime]$state.NowValues[$index]
                        }

                        return Get-Date
                    }.GetNewClosure()
                    SleepMilliseconds = {
                        param([int]$Milliseconds)
                        [void]$state.SleptMilliseconds.Add($Milliseconds)
                    }.GetNewClosure()
                }

                return [pscustomobject]@{
                    Timing = $timing
                    State = $state
                }
            }

            function New-TestCDPTransportFixture {
                param(
                    [AllowNull()][object[]]$ReceiveMessages = @(),
                    [switch]$ThrowOnClose
                )

                $state = [pscustomobject]@{
                    WebSocket = [pscustomobject]@{ Name = 'fake-websocket' }
                    CancellationTokenSource = [pscustomobject]@{ Name = 'fake-cts' }
                    SentTexts = New-Object System.Collections.ArrayList
                    SendTimeoutMilliseconds = New-Object System.Collections.ArrayList
                    ReceiveMessages = New-Object System.Collections.ArrayList
                    ReceiveCount = 0
                    Closed = $false
                    Aborted = $false
                    Disposed = $false
                    Warnings = New-Object System.Collections.ArrayList
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
                    }.GetNewClosure()
                    SendText = {
                        param($Session, $Text, $TimeoutMilliseconds, $Description)
                        [void]$state.SentTexts.Add([string]$Text)
                        [void]$state.SendTimeoutMilliseconds.Add([int]$TimeoutMilliseconds)
                    }.GetNewClosure()
                    ReceiveText = {
                        param($Session, $TimeoutMilliseconds, $Description)
                        $state.ReceiveCount++

                        if ($state.ReceiveCount -le $state.ReceiveMessages.Count) {
                            $messageIndex = $state.ReceiveCount - 1
                            return [string]$state.ReceiveMessages[$messageIndex]
                        }

                        return $null
                    }.GetNewClosure()
                    Close = {
                        param($Session, $TimeoutMilliseconds, $Description)

                        if ($ThrowOnClose) {
                            throw 'simulated close failure'
                        }

                        $state.Closed = $true
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
                    [AllowNull()][object]$Transport,
                    [AllowNull()][object]$Timing
                )

                if (-not $Transport) {
                    $Transport = (New-TestCDPTransportFixture).Transport
                }

                if (-not $Timing) {
                    $Timing = (New-TestCDPSequenceTimingPort).Timing
                }

                return New-CDPRuntime `
                    -Transport $Transport `
                    -HttpClient ([pscustomobject]@{ GetContent = { param($Uri, $TimeoutSeconds) '[]' } }) `
                    -Console ([pscustomobject]@{
                        WriteLine = { param($Message) }
                        WriteWarning = {
                            param($Message)
                            if ($script:CurrentCdpTransportState) {
                                [void]$script:CurrentCdpTransportState.Warnings.Add([string]$Message)
                            }
                        }
                    }) `
                    -Timing $Timing
            }

            function New-TestInitializedCDPSession {
                param(
                    [Parameter(Mandatory)][object]$Runtime,
                    [Parameter(Mandatory)][object]$Fixture,
                    [int]$CommandTimeoutSeconds = 5
                )

                $session = New-CDPSessionState -CommandTimeoutSeconds $CommandTimeoutSeconds -Runtime $Runtime
                $session.WebSocket = $Fixture.State.WebSocket
                $session.CancellationTokenSource = $Fixture.State.CancellationTokenSource
                return $session
            }
        }

        BeforeEach {
            $script:CdpDefaultSession = $null
            $script:CurrentCdpTransportState = $null
        }

        It 'rejects malformed CDP response JSON with command context' {
            $fixture = New-TestCDPTransportFixture -ReceiveMessages @('{not-json')
            $runtime = New-TestCDPRuntimePort -Transport $fixture.Transport
            $session = New-TestInitializedCDPSession -Runtime $runtime -Fixture $fixture

            { Send-CDPCommand -Method 'Runtime.evaluate' -Params @{ expression = '1 + 1' } -Session $session -Runtime $runtime } |
                Should -Throw '*CDP応答の JSON 解析に失敗しました: method=Runtime.evaluate id=1*'
        }

        It 'surfaces CDP error responses with method and command id' {
            $fixture = New-TestCDPTransportFixture -ReceiveMessages @('{"id":1,"error":{"message":"permission denied"}}')
            $runtime = New-TestCDPRuntimePort -Transport $fixture.Transport
            $session = New-TestInitializedCDPSession -Runtime $runtime -Fixture $fixture

            { Send-CDPCommand -Method 'Runtime.evaluate' -Params @{ expression = '1 + 1' } -Session $session -Runtime $runtime } |
                Should -Throw 'CDP error: method=Runtime.evaluate id=1 message=permission denied'
        }

        It 'ignores unrelated CDP command responses until the requested id arrives' {
            $fixture = New-TestCDPTransportFixture -ReceiveMessages @(
                '{"id":99,"result":{"ignored":true}}',
                '{"id":1,"result":{"ok":true}}'
            )
            $runtime = New-TestCDPRuntimePort -Transport $fixture.Transport
            $session = New-TestInitializedCDPSession -Runtime $runtime -Fixture $fixture

            $response = Send-CDPCommand `
                -Method 'Runtime.evaluate' `
                -Params @{ expression = '1 + 1' } `
                -Session $session `
                -Runtime $runtime

            $fixture.State.ReceiveCount | Should -Be 2
            $response.result.ok | Should -Be $true
        }

        It 'treats a null receive result as a closed CDP WebSocket' {
            $fixture = New-TestCDPTransportFixture
            $runtime = New-TestCDPRuntimePort -Transport $fixture.Transport
            $session = New-TestInitializedCDPSession -Runtime $runtime -Fixture $fixture

            { Send-CDPCommand -Method 'Runtime.evaluate' -Params @{ expression = '1 + 1' } -Session $session -Runtime $runtime } |
                Should -Throw 'CDP WebSocket が閉じられました。method=Runtime.evaluate id=1'
        }

        It 'aborts the transport when a command deadline has elapsed before sending' {
            $now = Get-Date
            $timingFixture = New-TestCDPSequenceTimingPort -NowValues @($now, $now.AddSeconds(2))
            $fixture = New-TestCDPTransportFixture
            $runtime = New-TestCDPRuntimePort -Transport $fixture.Transport -Timing $timingFixture.Timing
            $session = New-TestInitializedCDPSession -Runtime $runtime -Fixture $fixture

            { Send-CDPCommand -Method 'Runtime.evaluate' -Params @{ expression = '1 + 1' } -TimeoutSeconds 1 -Session $session -Runtime $runtime } |
                Should -Throw '*CDPタイムアウト: CDP送信: method=Runtime.evaluate id=1 / 送信前に期限を超過しました。'

            $fixture.State.Aborted | Should -Be $true
            $fixture.State.SentTexts.Count | Should -Be 0
        }

        It 'aborts the transport when a CDP task times out and clamps non-positive timeout values' {
            $fixture = New-TestCDPTransportFixture
            $runtime = New-TestCDPRuntimePort -Transport $fixture.Transport
            $session = New-TestInitializedCDPSession -Runtime $runtime -Fixture $fixture
            $task = [System.Threading.Tasks.Task]::Delay(50)

            { Wait-CDPTask -Task $task -TimeoutMilliseconds 0 -Description 'slow task' -Session $session -Runtime $runtime } |
                Should -Throw 'CDPタイムアウト: slow task / timeoutMilliseconds=1'

            $fixture.State.Aborted | Should -Be $true
        }

        It 'disposes the session and warns when WebSocket close fails in non-quiet mode' {
            $fixture = New-TestCDPTransportFixture -ThrowOnClose
            $script:CurrentCdpTransportState = $fixture.State
            $runtime = New-TestCDPRuntimePort -Transport $fixture.Transport
            $session = New-TestInitializedCDPSession -Runtime $runtime -Fixture $fixture

            Close-CDPConnection -Session $session -Runtime $runtime

            $fixture.State.Disposed | Should -Be $true
            $fixture.State.Warnings.Count | Should -Be 1
            $fixture.State.Warnings[0] | Should -Be 'WebSocket close failed: simulated close failure'
            $session.IsClosed | Should -Be $true
            $session.WebSocket | Should -BeNullOrEmpty
            $session.CancellationTokenSource | Should -BeNullOrEmpty
        }

        It 'disposes a cancellation token source even when no WebSocket is attached' {
            $fixture = New-TestCDPTransportFixture
            $runtime = New-TestCDPRuntimePort -Transport $fixture.Transport
            $session = New-CDPSessionState -CommandTimeoutSeconds 5 -Runtime $runtime
            $session.WebSocket = $null
            $session.CancellationTokenSource = $fixture.State.CancellationTokenSource

            Close-CDPConnection -Session $session -Runtime $runtime

            $fixture.State.Closed | Should -Be $false
            $fixture.State.Disposed | Should -Be $true
            $session.IsClosed | Should -Be $true
            $session.CancellationTokenSource | Should -BeNullOrEmpty
        }
    }
}
