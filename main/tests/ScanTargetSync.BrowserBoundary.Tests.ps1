$ErrorActionPreference = "Stop"
Describe 'ScanTargetSync Browser service boundary' {
    BeforeAll {
        $repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
        . (Join-Path $PSScriptRoot 'TestSupport.ps1')
        Import-Module -Name (Join-Path $repositoryRoot 'modules\ScanTargetSync\ScanTargetSync.psm1') -Force
    }

    BeforeEach {
        $script:ScanTargetSyncBrowser = New-TestBrowserService
        $script:ScanTargetSyncFileSystem = New-TestFileSystemService
        $script:ScanTargetSyncDomCalls = New-TestCallList
        $script:ScanTargetSyncContext = [pscustomobject]@{
            Logger = $null
            CommonSettings = [pscustomobject]@{
                DebuggerUrl = 'http://localhost:9222'
                Cdp = [pscustomobject]@{
                    ConnectTimeoutSeconds = 13
                    CommandTimeoutSeconds = 31
                }
            }
            JobSettings = [pscustomobject]@{}
        }
        $script:ScanTargetSyncState = [pscustomobject]@{
            FailureRows = @()
            CsvErrorRowsForExport = @()
            EndCsvExportCompleted = $false
        }
        $script:ScanTargetSyncPlan = [pscustomobject]@{
            CsvRows = @(
                [pscustomobject]@{ Endpoint = 'PC-001' },
                [pscustomobject]@{ Endpoint = 'PC-002' }
            )
            SyncRows = @(
                [pscustomobject]@{ Endpoint = 'PC-001' },
                [pscustomobject]@{ Endpoint = 'PC-002' }
            )
            OnRows = @([pscustomobject]@{ Endpoint = 'PC-001' })
            OffRows = @([pscustomobject]@{ Endpoint = 'PC-002' })
        }

        $domCalls = $script:ScanTargetSyncDomCalls
        $script:ScanTargetSyncDependencies = [pscustomobject]@{
            Browser = $script:ScanTargetSyncBrowser
            FileSystem = $script:ScanTargetSyncFileSystem
            Dom = [pscustomobject]@{
                RegisterAdapter = {
                    [void]$domCalls.Add([pscustomobject]@{ Name = 'RegisterAdapter'; Arguments = @{} })
                }.GetNewClosure()
                AssertPage = {
                    [void]$domCalls.Add([pscustomobject]@{ Name = 'AssertPage'; Arguments = @{} })
                    [pscustomobject]@{ ok = $true }
                }.GetNewClosure()
                TestPageIdentity = {
                    [void]$domCalls.Add([pscustomobject]@{ Name = 'TestPageIdentity'; Arguments = @{} })
                    [pscustomobject]@{ Matched = $true; Reason = 'test' }
                }.GetNewClosure()
                AssertDeviceList = {
                    [void]$domCalls.Add([pscustomobject]@{ Name = 'AssertDeviceList'; Arguments = @{} })
                    [pscustomobject]@{ ok = $true; details = [pscustomobject]@{ totalCount = 2 } }
                }.GetNewClosure()
                PrepareOperationScope = {
                    [void]$domCalls.Add([pscustomobject]@{ Name = 'PrepareOperationScope'; Arguments = @{} })
                    [pscustomobject]@{ ok = $true }
                }.GetNewClosure()
                ScrollToTop = {
                    [void]$domCalls.Add([pscustomobject]@{ Name = 'ScrollToTop'; Arguments = @{} })
                }.GetNewClosure()
            }
        }
    }

    It 'creates a self-contained page identity matcher through ScanTargetSync dependencies' {
        $context = $script:ScanTargetSyncContext
        $dependencies = [pscustomobject]@{
            Dom = [pscustomobject]@{
                TestPageIdentity = {
                    return [pscustomobject]@{ Matched = $true; Reason = 'scan-target-sync dependency-bound probe' }
                }
            }
        }

        $probe = InModuleScope ScanTargetSync -Parameters @{ Context = $context; Dependencies = $dependencies } {
            New-ScanTargetSyncPageIdentityMatcher -Context $Context -Dependencies $Dependencies
        }

        $result = & $probe ([pscustomobject]@{ title = 'ignored' }) ([pscustomobject]@{})

        $result.Matched | Should -BeTrue
        $result.Reason | Should -Be 'scan-target-sync dependency-bound probe'
    }

    It 'matches page identity through a lightweight DOM operation without readiness assertions' {
        $result = InModuleScope ScanTargetSync -Parameters @{ Context = $script:ScanTargetSyncContext } {
            Mock Register-ScanTargetSyncDomAdapter { }
            Mock Invoke-ScanTargetSyncDomOperation {
                param([string]$Operation, [int]$TimeoutSeconds, [object]$MissingValue)
                $Operation | Should -Be 'DetectPageIdentity'
                $TimeoutSeconds | Should -Be 2
                return [pscustomobject]@{ ok = $true; fatalCount = 0 }
            }
            Mock Assert-ScanTargetSyncPage { throw 'readiness assertion must not run during identity matching' }
            Mock Assert-ScanTargetSyncDeviceList { throw 'list assertion must not run during identity matching' }

            Test-ScanTargetSyncPageIdentity -Context $Context
        }

        $result.Matched | Should -BeTrue
    }

    It 'opens the page by DOM contract through the injected Browser port and then validates through DOM ports' {
        $totalCount = InModuleScope ScanTargetSync -Parameters @{
            Context = $script:ScanTargetSyncContext
            State = $script:ScanTargetSyncState
            Plan = $script:ScanTargetSyncPlan
            Dependencies = $script:ScanTargetSyncDependencies
        } {
            Open-ScanTargetSyncPageAndValidate -Context $Context -State $State -Plan $Plan -Dependencies $Dependencies
        }

        $totalCount | Should -Be 2
        Get-TestCallCount -Calls $script:ScanTargetSyncBrowser.Calls -Name 'OpenPageMatchingIdentity' | Should -Be 1
        $openPageCall = @($script:ScanTargetSyncBrowser.Calls | Where-Object { $_.Name -eq 'OpenPageMatchingIdentity' })[0]
        $openPageCall.Arguments.DebuggerUrl | Should -Be 'http://localhost:9222'
        $openPageCall.Arguments.ConnectTimeoutSeconds | Should -Be 13
        $openPageCall.Arguments.CommandTimeoutSeconds | Should -Be 31

        ($script:ScanTargetSyncDomCalls | ForEach-Object { $_.Name }) -join ',' | Should -Be 'RegisterAdapter,AssertPage,AssertDeviceList,PrepareOperationScope,ScrollToTop'
        @($script:ScanTargetSyncState.FailureRows).Count | Should -Be 0
    }

    It 'stops before scrolling when CSV and UI counts do not match' {
        $script:ScanTargetSyncPlan.SyncRows = @([pscustomobject]@{ Endpoint = 'PC-001' })

        InModuleScope ScanTargetSync -Parameters @{
            Context = $script:ScanTargetSyncContext
            State = $script:ScanTargetSyncState
            Plan = $script:ScanTargetSyncPlan
            Dependencies = $script:ScanTargetSyncDependencies
        } {
            {
                Open-ScanTargetSyncPageAndValidate -Context $Context -State $State -Plan $Plan -Dependencies $Dependencies
            } | Should -Throw '*チェック状態整合対象件数とUI一覧件数が一致しません*'
        }

        Get-TestCallCount -Calls $script:ScanTargetSyncBrowser.Calls -Name 'OpenPageMatchingIdentity' | Should -Be 1
        Get-TestCallCount -Calls $script:ScanTargetSyncDomCalls -Name 'ScrollToTop' | Should -Be 0
        @($script:ScanTargetSyncState.FailureRows).Count | Should -Be 1
        $script:ScanTargetSyncState.FailureRows[0].Endpoint | Should -Be '__SYNC_UI_COUNT_MISMATCH__'
    }
}
