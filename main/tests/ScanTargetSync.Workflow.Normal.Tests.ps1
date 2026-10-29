$ErrorActionPreference = "Stop"
$repositoryRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$modulePath = Join-Path $repositoryRoot 'modules\ScanTargetSync\ScanTargetSync.psm1'
Import-Module -Name $modulePath -Force

InModuleScope ScanTargetSync {
    Describe 'ScanTargetSync sync workflow normal path' {
        BeforeAll {
            function New-TestScanTargetSyncCallList {
                $list = New-Object System.Collections.ArrayList
                return ,$list
            }

            function Get-TestScanTargetSyncCallCount {
                param(
                    [Parameter(Mandatory)]$Calls,
                    [Parameter(Mandatory)][string]$Name
                )

                return @($Calls | Where-Object { $_.Name -eq $Name }).Count
            }

            function New-TestScanTargetSyncWorkflowContext {
                param([Parameter(Mandatory)][string]$OutputDirectory)

                return [pscustomobject]@{
                    Logger = $null
                    RootPath = $OutputDirectory
                    JobName = 'ScanTargetSync'
                    Services = [pscustomobject]@{}
                    CommonSettings = [pscustomobject]@{
                        DebuggerUrl = 'http://127.0.0.1:9222'
                        Cdp = [pscustomobject]@{
                            ConnectTimeoutSeconds = 1
                            CommandTimeoutSeconds = 1
                        }
                    }
                    JobSettings = [pscustomobject]@{
                        InputCsvPath = Join-Path $OutputDirectory 'input.csv'
                        OutputDirectory = $OutputDirectory
                        CsvErrorFileName = 'csv_error.csv'
                        FailureCsvFileName = 'failure.csv'
                        DaysThreshold = 30
                        MaxScanLoops = 3
                        SameScrollLimit = 2
                    }
                }
            }

            function New-TestScanTargetSyncCsvRow {
                param(
                    [string]$Endpoint,
                    [string]$ScanCompleted = '-'
                )

                return [pscustomobject]@{
                    Endpoint = $Endpoint
                    User = 'user-' + $Endpoint
                    Status = 'normal'
                    LastConnected = '2026/01/01'
                    ScanStarted = ''
                    ScanCompleted = $ScanCompleted
                }
            }

            function New-TestScanTargetSyncSyncRow {
                param(
                    [string]$Endpoint,
                    [string]$DesiredState,
                    [bool]$DesiredChecked
                )

                return [pscustomobject]@{
                    Endpoint = $Endpoint
                    DesiredState = $DesiredState
                    DesiredChecked = $DesiredChecked
                    User = 'user-' + $Endpoint
                    Status = 'normal'
                    LastConnected = '2026/01/01'
                    ScanStarted = ''
                    ScanCompleted = '-'
                    Reason = 'test plan'
                }
            }

            function New-TestScanTargetSyncWorkflowDependencies {
                param(
                    [Parameter(Mandatory)][int]$DeviceListTotalCount,
                    [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$VisibleRows,
                    [bool]$PostSelectionThrows = $false
                )

                $browserCalls = New-TestScanTargetSyncCallList
                $fileSystemCalls = New-TestScanTargetSyncCallList
                $domCalls = New-TestScanTargetSyncCallList
                $endpointActionCalls = New-TestScanTargetSyncCallList

                $recordCall = {
                    param(
                        [Parameter(Mandatory)]$Calls,
                        [Parameter(Mandatory)][string]$Name,
                        [hashtable]$Arguments = @{}
                    )

                    [void]$Calls.Add([pscustomobject]@{
                        Name = $Name
                        Arguments = $Arguments
                    })
                }.GetNewClosure()

                return [pscustomobject]@{
                    Calls = [pscustomobject]@{
                        Browser = $browserCalls
                        FileSystem = $fileSystemCalls
                        Dom = $domCalls
                        EndpointAction = $endpointActionCalls
                    }
                    Browser = [pscustomobject]@{
                        OpenPage = {
                            param(
                                [Parameter(Mandatory)][string]$DebuggerUrl,
                                [int]$ConnectTimeoutSeconds = 15,
                                [int]$CommandTimeoutSeconds = 30
                            )

                            & $recordCall -Calls $browserCalls -Name 'OpenPage' -Arguments @{
                                DebuggerUrl = $DebuggerUrl
                                ConnectTimeoutSeconds = $ConnectTimeoutSeconds
                                CommandTimeoutSeconds = $CommandTimeoutSeconds
                            }
                        }.GetNewClosure()
                        OpenPageMatchingIdentity = {
                            param(
                                [Parameter(Mandatory)][string]$DebuggerUrl,
                                [int]$ConnectTimeoutSeconds = 15,
                                [int]$CommandTimeoutSeconds = 30,
                                [Parameter(Mandatory)][scriptblock]$PageIdentityMatcher
                            )
                            & $recordCall -Calls $browserCalls -Name 'OpenPageMatchingIdentity' -Arguments @{
                                DebuggerUrl = $DebuggerUrl
                                ConnectTimeoutSeconds = $ConnectTimeoutSeconds
                                CommandTimeoutSeconds = $CommandTimeoutSeconds
                                PageIdentityMatcher = $PageIdentityMatcher
                            }
                        }.GetNewClosure()
                        SetDownloadDirectory = {
                            param([Parameter(Mandatory)][string]$Directory)
                            & $recordCall -Calls $browserCalls -Name 'SetDownloadDirectory' -Arguments @{ Directory = $Directory }
                            throw 'ScanTargetSync workflow should not set a download directory.'
                        }.GetNewClosure()
                    }
                    FileSystem = [pscustomobject]@{
                        InitializeOutputDirectory = {
                            param([Parameter(Mandatory)][string]$Directory, [string]$Purpose = '出力')
                            & $recordCall -Calls $fileSystemCalls -Name 'InitializeOutputDirectory' -Arguments @{ Directory = $Directory; Purpose = $Purpose }
                            if (-not (Test-Path -LiteralPath $Directory)) {
                                New-Item -ItemType Directory -Path $Directory -Force | Out-Null
                            }
                            return $Directory
                        }.GetNewClosure()
                        ClearDirectory = {
                            param([Parameter(Mandatory)][string]$Directory, [string]$Purpose = '作業')
                            & $recordCall -Calls $fileSystemCalls -Name 'ClearDirectory' -Arguments @{ Directory = $Directory; Purpose = $Purpose }
                        }.GetNewClosure()
                        TestPathUnderDirectory = {
                            param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Directory)
                            & $recordCall -Calls $fileSystemCalls -Name 'TestPathUnderDirectory' -Arguments @{ Path = $Path; Directory = $Directory }
                            return $true
                        }.GetNewClosure()
                        RemoveFileIfExists = {
                            param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$AllowedDirectory)
                            & $recordCall -Calls $fileSystemCalls -Name 'RemoveFileIfExists' -Arguments @{ Path = $Path; AllowedDirectory = $AllowedDirectory }
                            return $false
                        }.GetNewClosure()
                    }
                    Logger = [pscustomobject]@{}
                    Dom = [pscustomobject]@{
                        RegisterAdapter = {
                            & $recordCall -Calls $domCalls -Name 'RegisterAdapter'
                        }.GetNewClosure()
                        AssertPage = {
                            & $recordCall -Calls $domCalls -Name 'AssertPage'
                            return [pscustomobject]@{ ok = $true }
                        }.GetNewClosure()
                        TestPageIdentity = {
                            & $recordCall -Calls $domCalls -Name 'TestPageIdentity'
                            return [pscustomobject]@{ Matched = $true; Reason = 'test' }
                        }.GetNewClosure()
                        AssertDeviceList = {
                            & $recordCall -Calls $domCalls -Name 'AssertDeviceList'
                            return [pscustomobject]@{
                                details = [pscustomobject]@{ totalCount = $DeviceListTotalCount }
                            }
                        }.GetNewClosure()
                        PrepareOperationScope = {
                            & $recordCall -Calls $domCalls -Name 'PrepareOperationScope'
                            return [pscustomobject]@{ ok = $true }
                        }.GetNewClosure()
                        GetVisibleRows = {
                            & $recordCall -Calls $domCalls -Name 'GetVisibleRows'
                            return @($VisibleRows)
                        }.GetNewClosure()
                        ScrollToTop = {
                            & $recordCall -Calls $domCalls -Name 'ScrollToTop'
                        }.GetNewClosure()
                        ScrollDown = {
                            & $recordCall -Calls $domCalls -Name 'ScrollDown'
                            return [pscustomobject]@{ changed = $false }
                        }.GetNewClosure()
                        AssertPostSelectionContract = {
                            & $recordCall -Calls $domCalls -Name 'AssertPostSelectionContract'
                            if ($PostSelectionThrows) { throw 'post selection contract failed' }
                            return [pscustomobject]@{ ok = $true }
                        }.GetNewClosure()
                    }
                    EndpointAction = [pscustomobject]@{
                        SetDesiredState = {
                            param(
                                [Parameter(Mandatory)][string]$Endpoint,
                                [Parameter(Mandatory)][bool]$DesiredChecked
                            )

                            & $recordCall -Calls $endpointActionCalls -Name 'SetDesiredState' -Arguments @{
                                Endpoint = $Endpoint
                                DesiredChecked = $DesiredChecked
                            }
                            return [pscustomobject]@{
                                ok = $true
                                endpoint = $Endpoint
                                dataId = 'row-' + $Endpoint.ToLowerInvariant()
                                desiredChecked = $DesiredChecked
                                effectiveCheckedNow = $DesiredChecked
                                changed = $true
                                alreadyAligned = $false
                            }
                        }.GetNewClosure()
                        TestFoundationFatalError = {
                            param([AllowEmptyString()][string]$Message = '')
                            & $recordCall -Calls $endpointActionCalls -Name 'TestFoundationFatalError' -Arguments @{ Message = $Message }
                            return $false
                        }.GetNewClosure()
                    }
                }
            }

            function Set-TestScanTargetSyncCsvPlanMocks {
                param(
                    [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$CsvRows,
                    [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$OnRows,
                    [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$OffRows,
                    [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$CsvErrorRows,
                    [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$SyncRows,
                    [AllowEmptyCollection()][object[]]$DuplicateRows = @()
                )

                $script:MockCsvRows = @($CsvRows)
                $script:MockOnRows = @($OnRows)
                $script:MockOffRows = @($OffRows)
                $script:MockCsvErrorRows = @($CsvErrorRows)
                $script:MockSyncRows = @($SyncRows)
                $script:MockDuplicateRows = @($DuplicateRows)

                Mock Import-ScanTargetSyncInputCsv { return @($script:MockCsvRows) }
                Mock Assert-ScanTargetSyncInputCsvContract {
                    if (@($script:MockCsvRows).Count -eq 0) { throw 'CSVにデータ行がありません。' }
                }
                Mock Get-ScanTargetSyncTargetExtraction {
                    return [pscustomobject]@{
                        OnRows = @($script:MockOnRows)
                        OffRows = @($script:MockOffRows)
                        CsvErrorRows = @($script:MockCsvErrorRows)
                    }
                }
                Mock Get-ScanTargetSyncDuplicateEndpointErrors { return @($script:MockDuplicateRows) }
                Mock Get-ScanTargetSyncSyncRows { return @($script:MockSyncRows) }
                Mock Assert-UniqueScanTargetSyncSyncRows { }
            }
        }

        BeforeEach {
            $script:LastCsvErrorRows = @()
            $script:LastFailureRows = @()

            $script:OnCsvRow = New-TestScanTargetSyncCsvRow -Endpoint 'PC-ON'
            $script:OffCsvRow = New-TestScanTargetSyncCsvRow -Endpoint 'PC-OFF' -ScanCompleted '2026/06/01'
            $script:OnSyncRow = New-TestScanTargetSyncSyncRow -Endpoint 'PC-ON' -DesiredState 'ON' -DesiredChecked $true
            $script:OffSyncRow = New-TestScanTargetSyncSyncRow -Endpoint 'PC-OFF' -DesiredState 'OFF' -DesiredChecked $false

            Mock Write-FoundationLog { }
            Mock Write-FoundationSection { }
            Mock Export-ScanTargetSyncCsvErrorCsv {
                param($ErrorRows, $OutputDirectory, $ErrorCsvFileName, $FileSystemService)
                $script:LastCsvErrorRows = @($ErrorRows)
                return [pscustomobject]@{
                    ErrorCsvCreated = (@($ErrorRows).Count -gt 0)
                    OldErrorCsvRemoved = $false
                    ErrorCsvPath = Join-Path $OutputDirectory $ErrorCsvFileName
                }
            }
            Mock Export-ScanTargetSyncFailureCsv {
                param($FailureRows, $OutputDirectory, $FailureCsvFileName, $FileSystemService)
                $script:LastFailureRows = @($FailureRows)
                return [pscustomobject]@{
                    FailureCsvCreated = (@($FailureRows).Count -gt 0)
                    OldFailureCsvRemoved = $false
                    FailureCsvPath = Join-Path $OutputDirectory $FailureCsvFileName
                }
            }
        }

        It 'completes without fatal output when CSV, UI, and checkbox sync counts all match' {
            Set-TestScanTargetSyncCsvPlanMocks `
                -CsvRows @($script:OnCsvRow, $script:OffCsvRow) `
                -OnRows @($script:OnCsvRow) `
                -OffRows @($script:OffCsvRow) `
                -CsvErrorRows @() `
                -SyncRows @($script:OnSyncRow, $script:OffSyncRow)

            $context = New-TestScanTargetSyncWorkflowContext -OutputDirectory $TestDrive
            $dependencies = New-TestScanTargetSyncWorkflowDependencies `
                -DeviceListTotalCount 2 `
                -VisibleRows @(
                    [pscustomobject]@{ endpoint = 'PC-ON'; dataId = 'row-on' },
                    [pscustomobject]@{ endpoint = 'PC-OFF'; dataId = 'row-off' }
                )

            { Invoke-ScanTargetSyncSyncWorkflow -Context $context -Dependencies $dependencies } | Should -Not -Throw

            $endpointCalls = @($dependencies.Calls.EndpointAction | Where-Object { $_.Name -eq 'SetDesiredState' })
            $sortedEndpointCalls = @($endpointCalls | ForEach-Object { $_.Arguments.Endpoint } | Sort-Object)
            $sortedEndpointCalls.Count | Should -Be 2
            $sortedEndpointCalls[0] | Should -Be 'PC-OFF'
            $sortedEndpointCalls[1] | Should -Be 'PC-ON'
            @($script:LastCsvErrorRows).Count | Should -Be 0
            @($script:LastFailureRows).Count | Should -Be 0
            Get-TestScanTargetSyncCallCount -Calls $dependencies.Calls.Browser -Name 'OpenPageMatchingIdentity' | Should -Be 1
            Get-TestScanTargetSyncCallCount -Calls $dependencies.Calls.Dom -Name 'AssertPostSelectionContract' | Should -Be 1
            Get-TestScanTargetSyncCallCount -Calls $dependencies.Calls.Dom -Name 'ScrollDown' | Should -Be 0
            Should -Invoke -CommandName Export-ScanTargetSyncCsvErrorCsv -Times 1 -Exactly
            Should -Invoke -CommandName Export-ScanTargetSyncFailureCsv -Times 1 -Exactly
        }
    }
}
