$ErrorActionPreference = "Stop"
$modulePath = Join-Path $PSScriptRoot '..\modules\ScanTargetSync\ScanTargetSync.psm1'
Import-Module -Name $modulePath -Force

InModuleScope ScanTargetSync {
    Describe 'ScanTargetSync workflow dependencies' {
        BeforeAll {
            $script:NewTestScanTargetSyncDependencyContext = {
                param([Parameter(Mandatory)][string]$OutputDirectory)

                return [pscustomobject]@{
                    Logger = $null
                    CommonSettings = [pscustomobject]@{
                        DebuggerUrl = 'http://127.0.0.1:9222'
                        Cdp = [pscustomobject]@{
                            ConnectTimeoutSeconds = 1
                            CommandTimeoutSeconds = 1
                        }
                    }
                    JobSettings = [pscustomobject]@{
                        OutputDirectory = $OutputDirectory
                        CsvErrorFileName = 'csv_error.csv'
                        FailureCsvFileName = 'failure.csv'
                        MaxScanLoops = 3
                        SameScrollLimit = 2
                    }
                    Services = [pscustomobject]@{
                        Browser = [pscustomobject]@{
                            OpenPage = { throw 'Context browser service must not be used when dependencies are supplied.' }; OpenPageMatchingIdentity = { throw 'Context browser service must not be used when dependencies are supplied.' }
                        }
                        FileSystem = [pscustomobject]@{
                            InitializeOutputDirectory = { param($Directory, $Purpose) return $Directory }
                            TestPathUnderDirectory = { param($Path, $Directory) return $true }
                            RemoveFileIfExists = { param($Path, $AllowedDirectory) return $false }
                        }
                        Timing = [pscustomobject]@{
                            TimestampText = { return '2026-01-02 03:04:05' }
                        }
                    }
                }
            }.GetNewClosure()
        }

        BeforeEach {
            Mock Write-FoundationLog { }
            Mock Write-FoundationSection { }
        }

        It 'preserves supplied dependency ports when resolving workflow dependencies' {
            $context = & $script:NewTestScanTargetSyncDependencyContext -OutputDirectory $TestDrive
            $browser = [pscustomobject]@{ OpenPage = { param($DebuggerUrl, $ConnectTimeoutSeconds, $CommandTimeoutSeconds) }; OpenPageMatchingIdentity = { param($DebuggerUrl, $ConnectTimeoutSeconds, $CommandTimeoutSeconds, $PageIdentityMatcher) } }
            $fileSystem = [pscustomobject]@{
                InitializeOutputDirectory = { param($Directory, $Purpose) return $Directory }
                TestPathUnderDirectory = { param($Path, $Directory) return $true }
                RemoveFileIfExists = { param($Path, $AllowedDirectory) return $false }
            }
            $dom = [pscustomobject]@{
                RegisterAdapter = { }
                TestPageIdentity = { return [pscustomobject]@{ Matched = $true; Reason = 'test' } }
                AssertPage = { return [pscustomobject]@{ ok = $true } }
                AssertDeviceList = { return [pscustomobject]@{ details = [pscustomobject]@{ totalCount = 1 } } }
                PrepareOperationScope = { return [pscustomobject]@{ ok = $true } }
                GetVisibleRows = { return @() }
                ScrollToTop = { }
                ScrollDown = { return [pscustomobject]@{ changed = $false } }
                AssertPostSelectionContract = { return [pscustomobject]@{ ok = $true } }
            }
            $endpointAction = [pscustomobject]@{
                SetDesiredState = { param($Endpoint, $DesiredChecked) return [pscustomobject]@{ ok = $true } }
                TestFoundationFatalError = { param($Message) return $false }
            }
            $timing = [pscustomobject]@{
                TimestampText = { return '2026-01-02 03:04:05' }
            }

            $resolved = Resolve-ScanTargetSyncWorkflowDependencies -Context $context -Dependencies ([pscustomobject]@{
                Browser = $browser
                FileSystem = $fileSystem
                Dom = $dom
                EndpointAction = $endpointAction
                Timing = $timing
            })

            $resolved.Browser | Should -Be $browser
            $resolved.FileSystem | Should -Be $fileSystem
            $resolved.Dom | Should -Be $dom
            $resolved.EndpointAction | Should -Be $endpointAction
            $resolved.Timing | Should -Be $timing
        }

        It 'opens and validates the ScanTargetSync page through injected Browser and Dom ports' {
            $context = & $script:NewTestScanTargetSyncDependencyContext -OutputDirectory $TestDrive
            $state = New-ScanTargetSyncWorkflowState
            $plan = [pscustomobject]@{
                CsvRows = @([pscustomobject]@{ Endpoint = 'PC-001' })
                SyncRows = @([pscustomobject]@{ Endpoint = 'PC-001' })
                OnRows = @([pscustomobject]@{ Endpoint = 'PC-001' })
            }
            $calls = [pscustomobject]@{
                OpenPageMatchingIdentity = 0
                RegisterAdapter = 0
                AssertPage = 0
                AssertDeviceList = 0
                PrepareOperationScope = 0
                ScrollToTop = 0
            }
            $dependencies = [pscustomobject]@{
                Browser = [pscustomobject]@{
                    OpenPage = {
                        param($DebuggerUrl, $ConnectTimeoutSeconds, $CommandTimeoutSeconds)
                    }.GetNewClosure()
                    OpenPageMatchingIdentity = {
                        param($DebuggerUrl, $ConnectTimeoutSeconds, $CommandTimeoutSeconds, $PageIdentityMatcher)
                        $calls.OpenPageMatchingIdentity++
                    }.GetNewClosure()
                }
                FileSystem = $context.Services.FileSystem
                Dom = [pscustomobject]@{
                    RegisterAdapter = { $calls.RegisterAdapter++ }.GetNewClosure()
                    TestPageIdentity = { return [pscustomobject]@{ Matched = $true; Reason = 'test' } }
                    AssertPage = { $calls.AssertPage++; return [pscustomobject]@{ ok = $true } }.GetNewClosure()
                    AssertDeviceList = { $calls.AssertDeviceList++; return [pscustomobject]@{ details = [pscustomobject]@{ totalCount = 1 } } }.GetNewClosure()
                    PrepareOperationScope = { $calls.PrepareOperationScope++; return [pscustomobject]@{ ok = $true } }.GetNewClosure()
                    GetVisibleRows = { return @() }
                    ScrollToTop = { $calls.ScrollToTop++ }.GetNewClosure()
                    ScrollDown = { return [pscustomobject]@{ changed = $false } }
                    AssertPostSelectionContract = { return [pscustomobject]@{ ok = $true } }
                }
                EndpointAction = [pscustomobject]@{
                    SetDesiredState = { param($Endpoint, $DesiredChecked) return [pscustomobject]@{ ok = $true } }
                    TestFoundationFatalError = { param($Message) return $false }
                }
            }

            $totalCount = Open-ScanTargetSyncPageAndValidate -Context $context -State $state -Plan $plan -Dependencies $dependencies

            $totalCount | Should -Be 1
            $calls.OpenPageMatchingIdentity | Should -Be 1
            $calls.RegisterAdapter | Should -Be 1
            $calls.AssertPage | Should -Be 1
            $calls.AssertDeviceList | Should -Be 1
            $calls.PrepareOperationScope | Should -Be 1
            $calls.ScrollToTop | Should -Be 1
        }

        It 'syncs visible endpoints through the injected endpoint action port' {
            $context = & $script:NewTestScanTargetSyncDependencyContext -OutputDirectory $TestDrive
            $workflowState = New-ScanTargetSyncWorkflowState
            $scanState = New-ScanTargetSyncUiScanState -MaxScanLoops 3
            $syncRow = [pscustomobject]@{
                Endpoint = 'PC-001'
                DesiredState = 'ON'
                DesiredChecked = $true
                User = 'user1'
                Status = 'normal'
                LastConnected = '2026/01/01'
                ScanStarted = ''
                ScanCompleted = '-'
                Reason = 'test'
            }
            $syncIndex = [pscustomobject]@{
                SyncRowByEndpoint = @{ 'PC-001' = $syncRow }
                SyncEndpointSet = @{ 'PC-001' = $true }
            }
            $visibleSyncEndpoints = @{ 'PC-001' = $true }
            $calls = [pscustomobject]@{ SetDesiredState = 0 }
            $dependencies = [pscustomobject]@{
                Browser = [pscustomobject]@{ OpenPage = { param($DebuggerUrl, $ConnectTimeoutSeconds, $CommandTimeoutSeconds) }; OpenPageMatchingIdentity = { param($DebuggerUrl, $ConnectTimeoutSeconds, $CommandTimeoutSeconds, $PageIdentityMatcher) } }
                FileSystem = $context.Services.FileSystem
                Dom = New-ScanTargetSyncDomPort -Context $context
                EndpointAction = [pscustomobject]@{
                    SetDesiredState = {
                        param($Endpoint, $DesiredChecked)
                        $calls.SetDesiredState++
                        return [pscustomobject]@{
                            ok = $true
                            endpoint = $Endpoint
                            dataId = 'row-001'
                            desiredChecked = $DesiredChecked
                            effectiveCheckedNow = $DesiredChecked
                            changed = $false
                            alreadyAligned = $true
                        }
                    }.GetNewClosure()
                    TestFoundationFatalError = { param($Message) return $false }
                }
            }

            Invoke-ScanTargetSyncVisibleEndpointSyncBatch `
                -Context $context `
                -WorkflowState $workflowState `
                -ScanState $scanState `
                -SyncIndex $syncIndex `
                -VisibleSyncEndpoints $visibleSyncEndpoints `
                -Dependencies $dependencies

            $calls.SetDesiredState | Should -Be 1
            $scanState.ProcessedEndpointMap.ContainsKey('PC-001') | Should -Be $true
            @($scanState.SuccessRows).Count | Should -Be 1
            @($workflowState.FailureRows).Count | Should -Be 0
        }
    }
}
