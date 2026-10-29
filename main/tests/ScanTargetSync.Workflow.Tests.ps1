$ErrorActionPreference = "Stop"
$modulePath = Join-Path $PSScriptRoot '..\modules\ScanTargetSync\ScanTargetSync.psm1'
Import-Module -Name $modulePath -Force

InModuleScope ScanTargetSync {
    Describe 'ScanTargetSync workflow helpers' {
        It 'tracks failure rows in workflow state without losing existing rows' {
            $state = New-ScanTargetSyncWorkflowState
            Add-ScanTargetSyncFailureRow -State $state -FailureRow ([pscustomobject]@{ Endpoint = 'PC-001' })
            Add-ScanTargetSyncFailureRow -State $state -FailureRow ([pscustomobject]@{ Endpoint = 'PC-002' })
            @($state.FailureRows).Count | Should -Be 2
            $state.FailureRows[0].Endpoint | Should -Be 'PC-001'
            $state.FailureRows[1].Endpoint | Should -Be 'PC-002'
        }

        It 'summarizes success rows by desired state and change status' {
            $rows = @(
                [pscustomobject]@{ desiredChecked = $true; effectiveCheckedNow = $true; changed = $true; alreadyAligned = $false },
                [pscustomobject]@{ desiredChecked = $false; effectiveCheckedNow = $false; changed = $false; alreadyAligned = $true },
                [pscustomobject]@{ desiredChecked = $true; effectiveCheckedNow = $false; changed = $false; alreadyAligned = $false }
            )
            $breakdown = Get-ScanTargetSyncSuccessBreakdown -SuccessRows $rows
            @($breakdown.OnSuccessRows).Count | Should -Be 2
            @($breakdown.OffSuccessRows).Count | Should -Be 1
            @($breakdown.ChangedRows).Count | Should -Be 1
            @($breakdown.AlreadyAlignedRows).Count | Should -Be 1
            @($breakdown.MisalignedSuccessRows).Count | Should -Be 1
        }

        It 'adds success-count validation failures when ON/OFF counts do not match the plan' {
            $state = New-ScanTargetSyncWorkflowState
            $plan = [pscustomobject]@{
                OnRows = @([pscustomobject]@{ Endpoint = 'PC-ON' })
                OffRows = @([pscustomobject]@{ Endpoint = 'PC-OFF' })
            }
            $breakdown = [pscustomobject]@{
                OnSuccessRows = @()
                OffSuccessRows = @()
                MisalignedSuccessRows = @()
            }
            Add-ScanTargetSyncSuccessValidationFailures -State $state -Plan $plan -Breakdown $breakdown
            @($state.FailureRows).Count | Should -Be 2
            $state.FailureRows[0].Endpoint | Should -Be '__ON_SUCCESS_COUNT_MISMATCH__'
            $state.FailureRows[1].Endpoint | Should -Be '__OFF_SUCCESS_COUNT_MISMATCH__'
        }

        It 'initializes UI scan state with isolated maps and loop limit metadata' {
            $scanState = New-ScanTargetSyncUiScanState -MaxScanLoops 7
            $scanState.MaxScanLoops | Should -Be 7
            $scanState.LoopReachedLimit | Should -Be $true
            $scanState.ProcessedEndpointMap.Count | Should -Be 0
            $scanState.SeenUiEndpointSet.Count | Should -Be 0
            @($scanState.SuccessRows).Count | Should -Be 0
        }

        It 'updates UI scan state from visible rows and returns only unprocessed sync endpoints' {
            $scanState = New-ScanTargetSyncUiScanState -MaxScanLoops 10
            $scanState.ProcessedEndpointMap['PC-002'] = $true
            $syncIndex = [pscustomobject]@{
                SyncEndpointSet = @{
                    'PC-001' = $true
                    'PC-002' = $true
                    'PC-003' = $true
                }
                SyncRowByEndpoint = @{}
            }
            $visibleRows = @(
                [pscustomobject]@{ endpoint = 'PC-001'; dataId = 'row-001-a' },
                [pscustomobject]@{ endpoint = 'PC-002'; dataId = 'row-002' },
                [pscustomobject]@{ endpoint = 'PC-999'; dataId = 'row-999' },
                [pscustomobject]@{ endpoint = ''; dataId = 'row-empty-endpoint' },
                [pscustomobject]@{ endpoint = 'PC-001'; dataId = 'row-001-b' }
            )

            $visibleSyncEndpoints = Update-ScanTargetSyncUiScanStateFromVisibleRows -ScanState $scanState -SyncIndex $syncIndex -VisibleRows $visibleRows

            $visibleSyncEndpoints.Count | Should -Be 1
            $visibleSyncEndpoints.ContainsKey('PC-001') | Should -Be $true
            $visibleSyncEndpoints.ContainsKey('PC-002') | Should -Be $false
            $scanState.SeenUiEndpointSet.ContainsKey('PC-001') | Should -Be $true
            $scanState.SeenUiEndpointSet.ContainsKey('PC-999') | Should -Be $true
            $scanState.UiBadRowMap.Count | Should -Be 1
            $scanState.UiEndpointConflictMap.ContainsKey('PC-001') | Should -Be $true
        }

        It 'reports UI scan completion only when UI seen count and processed sync count are both sufficient' {
            $scanState = New-ScanTargetSyncUiScanState -MaxScanLoops 10
            $plan = [pscustomobject]@{
                SyncRows = @(
                    [pscustomobject]@{ Endpoint = 'PC-001' },
                    [pscustomobject]@{ Endpoint = 'PC-002' }
                )
            }

            $scanState.SeenUiEndpointSet['PC-001'] = $true
            $scanState.SeenUiEndpointSet['PC-002'] = $true
            $scanState.ProcessedEndpointMap['PC-001'] = $true
            Test-ScanTargetSyncUiScanCompleted -ScanState $scanState -Plan $plan -DeviceListTotalCount 2 | Should -Be $false

            $scanState.ProcessedEndpointMap['PC-002'] = $true
            Test-ScanTargetSyncUiScanCompleted -ScanState $scanState -Plan $plan -DeviceListTotalCount 2 | Should -Be $true

            Test-ScanTargetSyncUiScanCompleted -ScanState $scanState -Plan $plan -DeviceListTotalCount 3 | Should -Be $false
        }

        It 'treats zero sync rows as a no-CDP workflow branch' {
            $state = New-ScanTargetSyncWorkflowState
            $script:NoSyncExportCount = 0
            $script:NoSyncCsvErrorRows = @()
            $script:NoSyncFailureRows = @()
            $context = [pscustomobject]@{
                Logger = $null
                JobSettings = [pscustomobject]@{
                    OutputDirectory = $TestDrive
                    CsvErrorFileName = 'csv_error.csv'
                    FailureCsvFileName = 'failure.csv'
                }
            }
            $dependencies = [pscustomobject]@{
                FileSystem = [pscustomobject]@{
                    InitializeOutputDirectory = { param($Directory, $Purpose) return $Directory }
                    TestPathUnderDirectory = { param($Path, $Directory) return $true }
                    RemoveFileIfExists = { param($Path, $AllowedDirectory) return $false }
                }
            }
            $plan = [pscustomobject]@{ SyncRows = @() }

            Mock Write-FoundationLog { }
            Mock Export-ScanTargetSyncEndCsvFiles {
                param($Context, $CsvErrorRows, $FailureRows, $FileSystemService)
                $script:NoSyncCsvErrorRows = @($CsvErrorRows)
                $script:NoSyncFailureRows = @($FailureRows)
                $script:NoSyncExportCount++
            }

            Test-ScanTargetSyncNoSyncTarget -Context $context -State $state -Plan $plan -Dependencies $dependencies | Should -Be $true

            $state.EndCsvExportCompleted | Should -Be $true
            $script:NoSyncExportCount | Should -Be 1
            @($script:NoSyncCsvErrorRows).Count | Should -Be 0
            @($script:NoSyncFailureRows).Count | Should -Be 0
        }
    }
}

InModuleScope ScanTargetSync {
    Describe 'ScanTargetSync sync workflow abnormal paths' {
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
                param([string]$Endpoint = 'PC-001')
                return [pscustomobject]@{
                    Endpoint = $Endpoint
                    User = 'user1'
                    Status = 'normal'
                    LastConnected = '2026/01/01'
                    ScanStarted = ''
                    ScanCompleted = '-'
                }
            }

            function New-TestScanTargetSyncSyncRow {
                param(
                    [string]$Endpoint = 'PC-001',
                    [string]$DesiredState = 'ON',
                    [bool]$DesiredChecked = $true
                )
                return [pscustomobject]@{
                    Endpoint = $Endpoint
                    DesiredState = $DesiredState
                    DesiredChecked = $DesiredChecked
                    User = 'user1'
                    Status = 'normal'
                    LastConnected = '2026/01/01'
                    ScanStarted = ''
                    ScanCompleted = '-'
                    Reason = 'test reason'
                }
            }

            function New-TestScanTargetSyncWorkflowDependencies {
                param(
                    [int]$DeviceListTotalCount = 1,
                    [AllowEmptyCollection()][object[]]$VisibleRows = @(),
                    [bool]$OperationScopeOk = $true,
                    [bool]$SetThrows = $false,
                    [string]$SetThrowMessage = 'fatal cdp error',
                    [bool]$SetThrowIsFatal = $false,
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
                            if ($OperationScopeOk) { return [pscustomobject]@{ ok = $true } }
                            return [pscustomobject]@{ ok = $false; reason = 'scope not safe' }
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
                            if ($SetThrows) { throw $SetThrowMessage }
                            return [pscustomobject]@{
                                ok = $true
                                endpoint = $Endpoint
                                dataId = 'row-' + $Endpoint.ToLowerInvariant()
                                desiredChecked = $DesiredChecked
                                effectiveCheckedNow = $DesiredChecked
                                changed = $false
                                alreadyAligned = $true
                            }
                        }.GetNewClosure()
                        TestFoundationFatalError = {
                            param([AllowEmptyString()][string]$Message = '')
                            & $recordCall -Calls $endpointActionCalls -Name 'TestFoundationFatalError' -Arguments @{ Message = $Message }
                            return $SetThrowIsFatal
                        }.GetNewClosure()
                    }
                }
            }

            function Set-TestScanTargetSyncCsvPlanMocks {
                param(
                    [AllowEmptyCollection()][object[]]$CsvRows,
                    [AllowEmptyCollection()][object[]]$OnRows,
                    [AllowEmptyCollection()][object[]]$OffRows,
                    [AllowEmptyCollection()][object[]]$CsvErrorRows,
                    [AllowEmptyCollection()][object[]]$SyncRows,
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

        It 'stops before CDP when CSV data errors exist' {
            $csvRow = New-TestScanTargetSyncCsvRow -Endpoint 'PC-001'
            $errorRow = [pscustomobject]@{ Endpoint = 'PC-001'; Reason = 'invalid date' }
            Set-TestScanTargetSyncCsvPlanMocks -CsvRows @($csvRow) -OnRows @() -OffRows @() -CsvErrorRows @($errorRow) -SyncRows @()
            $context = New-TestScanTargetSyncWorkflowContext -OutputDirectory $TestDrive
            $dependencies = New-TestScanTargetSyncWorkflowDependencies

            { Invoke-ScanTargetSyncSyncWorkflow -Context $context -Dependencies $dependencies } | Should -Throw

            @($script:LastCsvErrorRows).Count | Should -Be 1
            Get-TestScanTargetSyncCallCount -Calls $dependencies.Calls.Browser -Name 'OpenPageMatchingIdentity' | Should -Be 0
            Get-TestScanTargetSyncCallCount -Calls $dependencies.Calls.EndpointAction -Name 'SetDesiredState' | Should -Be 0
            Should -Invoke -CommandName Export-ScanTargetSyncCsvErrorCsv -Times 1 -Exactly
            Should -Invoke -CommandName Export-ScanTargetSyncFailureCsv -Times 1 -Exactly
        }

        It 'stops before CDP when CSV classification count is inconsistent' {
            $row1 = New-TestScanTargetSyncCsvRow -Endpoint 'PC-001'
            $row2 = New-TestScanTargetSyncCsvRow -Endpoint 'PC-002'
            $syncRow = New-TestScanTargetSyncSyncRow -Endpoint 'PC-001'
            Set-TestScanTargetSyncCsvPlanMocks -CsvRows @($row1, $row2) -OnRows @($row1) -OffRows @() -CsvErrorRows @() -SyncRows @($syncRow)
            $context = New-TestScanTargetSyncWorkflowContext -OutputDirectory $TestDrive
            $dependencies = New-TestScanTargetSyncWorkflowDependencies

            { Invoke-ScanTargetSyncSyncWorkflow -Context $context -Dependencies $dependencies } | Should -Throw

            @($script:LastFailureRows | Where-Object { $_.Endpoint -eq '__CSV_CLASSIFICATION_COUNT__' }).Count | Should -Be 1
            Get-TestScanTargetSyncCallCount -Calls $dependencies.Calls.Browser -Name 'OpenPageMatchingIdentity' | Should -Be 0
            Get-TestScanTargetSyncCallCount -Calls $dependencies.Calls.EndpointAction -Name 'SetDesiredState' | Should -Be 0
        }

        It 'stops before CDP when sync row count is inconsistent' {
            $row1 = New-TestScanTargetSyncCsvRow -Endpoint 'PC-001'
            $row2 = New-TestScanTargetSyncCsvRow -Endpoint 'PC-002'
            $syncRow = New-TestScanTargetSyncSyncRow -Endpoint 'PC-001'
            Set-TestScanTargetSyncCsvPlanMocks -CsvRows @($row1, $row2) -OnRows @($row1) -OffRows @($row2) -CsvErrorRows @() -SyncRows @($syncRow)
            $context = New-TestScanTargetSyncWorkflowContext -OutputDirectory $TestDrive
            $dependencies = New-TestScanTargetSyncWorkflowDependencies

            { Invoke-ScanTargetSyncSyncWorkflow -Context $context -Dependencies $dependencies } | Should -Throw

            @($script:LastFailureRows | Where-Object { $_.Endpoint -eq '__SYNC_COUNT__' }).Count | Should -Be 1
            Get-TestScanTargetSyncCallCount -Calls $dependencies.Calls.Browser -Name 'OpenPageMatchingIdentity' | Should -Be 0
            Get-TestScanTargetSyncCallCount -Calls $dependencies.Calls.EndpointAction -Name 'SetDesiredState' | Should -Be 0
        }

        It 'stops before CDP when input CSV has no data rows' {
            Set-TestScanTargetSyncCsvPlanMocks -CsvRows @() -OnRows @() -OffRows @() -CsvErrorRows @() -SyncRows @()
            $context = New-TestScanTargetSyncWorkflowContext -OutputDirectory $TestDrive
            $dependencies = New-TestScanTargetSyncWorkflowDependencies

            { Invoke-ScanTargetSyncSyncWorkflow -Context $context -Dependencies $dependencies } | Should -Throw '*CSVにデータ行がありません*'

            Get-TestScanTargetSyncCallCount -Calls $dependencies.Calls.Browser -Name 'OpenPageMatchingIdentity' | Should -Be 0
            Get-TestScanTargetSyncCallCount -Calls $dependencies.Calls.EndpointAction -Name 'SetDesiredState' | Should -Be 0
            @($script:LastFailureRows | Where-Object { $_.Endpoint -eq '__SCRIPT_FATAL__' }).Count | Should -Be 1
        }

        It 'stops after page validation and before checkbox changes when UI total count is zero' {
            $row = New-TestScanTargetSyncCsvRow -Endpoint 'PC-001'
            $syncRow = New-TestScanTargetSyncSyncRow -Endpoint 'PC-001'
            Set-TestScanTargetSyncCsvPlanMocks -CsvRows @($row) -OnRows @($row) -OffRows @() -CsvErrorRows @() -SyncRows @($syncRow)
            $context = New-TestScanTargetSyncWorkflowContext -OutputDirectory $TestDrive
            $dependencies = New-TestScanTargetSyncWorkflowDependencies -DeviceListTotalCount 0 -VisibleRows @()

            { Invoke-ScanTargetSyncSyncWorkflow -Context $context -Dependencies $dependencies } | Should -Throw

            @($script:LastFailureRows | Where-Object { $_.Endpoint -eq '__UI_TOTAL_COUNT__' }).Count | Should -Be 1
            Get-TestScanTargetSyncCallCount -Calls $dependencies.Calls.Browser -Name 'OpenPageMatchingIdentity' | Should -Be 1
            Get-TestScanTargetSyncCallCount -Calls $dependencies.Calls.EndpointAction -Name 'SetDesiredState' | Should -Be 0
        }

        It 'stops after page validation and before checkbox changes when CSV and UI counts differ' {
            $row = New-TestScanTargetSyncCsvRow -Endpoint 'PC-001'
            $syncRow = New-TestScanTargetSyncSyncRow -Endpoint 'PC-001'
            Set-TestScanTargetSyncCsvPlanMocks -CsvRows @($row) -OnRows @($row) -OffRows @() -CsvErrorRows @() -SyncRows @($syncRow)
            $context = New-TestScanTargetSyncWorkflowContext -OutputDirectory $TestDrive
            $dependencies = New-TestScanTargetSyncWorkflowDependencies -DeviceListTotalCount 2 -VisibleRows @()

            { Invoke-ScanTargetSyncSyncWorkflow -Context $context -Dependencies $dependencies } | Should -Throw

            @($script:LastFailureRows | Where-Object { $_.Endpoint -eq '__CSV_UI_COUNT_MISMATCH__' }).Count | Should -Be 1
            Get-TestScanTargetSyncCallCount -Calls $dependencies.Calls.Browser -Name 'OpenPageMatchingIdentity' | Should -Be 1
            Get-TestScanTargetSyncCallCount -Calls $dependencies.Calls.EndpointAction -Name 'SetDesiredState' | Should -Be 0
        }

        It 'stops before checkbox changes when operation scope validation fails' {
            $row = New-TestScanTargetSyncCsvRow -Endpoint 'PC-001'
            $syncRow = New-TestScanTargetSyncSyncRow -Endpoint 'PC-001'
            Set-TestScanTargetSyncCsvPlanMocks -CsvRows @($row) -OnRows @($row) -OffRows @() -CsvErrorRows @() -SyncRows @($syncRow)
            $context = New-TestScanTargetSyncWorkflowContext -OutputDirectory $TestDrive
            $dependencies = New-TestScanTargetSyncWorkflowDependencies -DeviceListTotalCount 1 -VisibleRows @() -OperationScopeOk $false

            { Invoke-ScanTargetSyncSyncWorkflow -Context $context -Dependencies $dependencies } | Should -Throw

            Get-TestScanTargetSyncCallCount -Calls $dependencies.Calls.Browser -Name 'OpenPageMatchingIdentity' | Should -Be 1
            Get-TestScanTargetSyncCallCount -Calls $dependencies.Calls.EndpointAction -Name 'SetDesiredState' | Should -Be 0
            @($script:LastFailureRows | Where-Object { $_.Endpoint -eq '__SCRIPT_FATAL__' }).Count | Should -Be 1
        }

        It 'exports failure rows when a fatal CDP error occurs during checkbox sync' {
            $row = New-TestScanTargetSyncCsvRow -Endpoint 'PC-001'
            $syncRow = New-TestScanTargetSyncSyncRow -Endpoint 'PC-001'
            Set-TestScanTargetSyncCsvPlanMocks -CsvRows @($row) -OnRows @($row) -OffRows @() -CsvErrorRows @() -SyncRows @($syncRow)
            $context = New-TestScanTargetSyncWorkflowContext -OutputDirectory $TestDrive
            $dependencies = New-TestScanTargetSyncWorkflowDependencies `
                -DeviceListTotalCount 1 `
                -VisibleRows @([pscustomobject]@{ endpoint = 'PC-001'; dataId = 'row-001' }) `
                -SetThrows $true `
                -SetThrowMessage 'CDP connection closed' `
                -SetThrowIsFatal $true

            { Invoke-ScanTargetSyncSyncWorkflow -Context $context -Dependencies $dependencies } | Should -Throw

            Get-TestScanTargetSyncCallCount -Calls $dependencies.Calls.EndpointAction -Name 'SetDesiredState' | Should -Be 1
            @($script:LastFailureRows | Where-Object { $_.Endpoint -eq 'PC-001' }).Count | Should -Be 1
            @($script:LastFailureRows | Where-Object { $_.Endpoint -eq '__SCRIPT_FATAL__' }).Count | Should -Be 1
        }

        It 'records post-selection contract failure without clicking normal search start' {
            $row = New-TestScanTargetSyncCsvRow -Endpoint 'PC-001'
            $syncRow = New-TestScanTargetSyncSyncRow -Endpoint 'PC-001'
            Set-TestScanTargetSyncCsvPlanMocks -CsvRows @($row) -OnRows @($row) -OffRows @() -CsvErrorRows @() -SyncRows @($syncRow)
            $context = New-TestScanTargetSyncWorkflowContext -OutputDirectory $TestDrive
            $dependencies = New-TestScanTargetSyncWorkflowDependencies `
                -DeviceListTotalCount 1 `
                -VisibleRows @([pscustomobject]@{ endpoint = 'PC-001'; dataId = 'row-001' }) `
                -PostSelectionThrows $true

            { Invoke-ScanTargetSyncSyncWorkflow -Context $context -Dependencies $dependencies } | Should -Throw

            Get-TestScanTargetSyncCallCount -Calls $dependencies.Calls.EndpointAction -Name 'SetDesiredState' | Should -Be 1
            Get-TestScanTargetSyncCallCount -Calls $dependencies.Calls.Dom -Name 'AssertPostSelectionContract' | Should -Be 1
            @($script:LastFailureRows | Where-Object { $_.Endpoint -eq '__POST_SELECTION_CONTRACT__' }).Count | Should -Be 1
            @($script:LastFailureRows | Where-Object { $_.Endpoint -eq '__SCRIPT_FATAL__' }).Count | Should -Be 0
        }
    }
}
