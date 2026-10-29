$ErrorActionPreference = "Stop"
$repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
Import-Module -Name (Join-Path $repositoryRoot 'modules\InstalledAppExport\InstalledAppExport.psm1') -Force

Describe 'InstalledAppExport workflow dependency boundary behavior' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestSupport.ps1')
    }

    It 'resolves InstalledAppExport Workflow port from Context.Services instead of requiring source-text inspection' {
        $workflowService = New-TestWorkflowService
        $context = [pscustomobject]@{
            Logger = $null
            Services = [pscustomobject]@{
                Workflow = $workflowService
                Logger = [pscustomobject]@{ WriteWarning = { param([string]$Message) } }
            }
        }

        InModuleScope InstalledAppExport -Parameters @{ Context = $context; WorkflowService = $workflowService } {
            $port = New-InstalledAppExportWorkflowPort -Context $Context
            [object]::ReferenceEquals($port, $WorkflowService) | Should -BeTrue
        }
    }


    It 'preserves explicitly injected InstalledAppExport dependencies when resolving workflow dependencies' {
        $dependencies = [pscustomobject]@{
            ListTraversal = [pscustomobject]@{
                GetVisibleRows = { @() }
                GetRowKey = { param($row) '' }
                ScrollDown = { [pscustomobject]@{ Scrolled = $false } }
            }
            RowAction = [pscustomobject]@{
                ExportForRow = { param($Context, [string]$DataId, [string]$AssetName) [pscustomobject]@{} }
                NewFailure = { param([string]$DataId, [string]$AssetName, [string]$Reason) [pscustomobject]@{} }
            }
            Logger = [pscustomobject]@{
                WriteWarning = { param([string]$Message) }
            }
            Workflow = New-TestWorkflowService
        }
        $context = [pscustomobject]@{ Logger = $null; Services = [pscustomobject]@{} }

        InModuleScope InstalledAppExport -Parameters @{ Context = $context; Dependencies = $dependencies } {
            $resolved = Resolve-InstalledAppExportWorkflowDependencies -Context $Context -Dependencies $Dependencies
            [object]::ReferenceEquals($resolved.ListTraversal, $Dependencies.ListTraversal) | Should -BeTrue
            [object]::ReferenceEquals($resolved.RowAction, $Dependencies.RowAction) | Should -BeTrue
            [object]::ReferenceEquals($resolved.Logger, $Dependencies.Logger) | Should -BeTrue
            [object]::ReferenceEquals($resolved.Workflow, $Dependencies.Workflow) | Should -BeTrue
        }
    }
}

InModuleScope InstalledAppExport {
    Describe 'InstalledAppExport row processor result classification' {

        It 'builds default callback and dependency objects without executing DOM/CDP callbacks' {
            $context = [pscustomobject]@{
                Logger = $null
                JobSettings = [pscustomobject]@{}
            }

            $listTraversalCallbacks = New-InstalledAppExportListTraversalCallbacks
            ($listTraversalCallbacks.GetVisibleRows -is [scriptblock]) | Should -BeTrue
            ($listTraversalCallbacks.GetRowKey -is [scriptblock]) | Should -BeTrue
            ($listTraversalCallbacks.ScrollDown -is [scriptblock]) | Should -BeTrue

            $rowActionCallbacks = New-InstalledAppExportRowActionCallbacks -Context $context
            ($rowActionCallbacks.ExportForRow -is [scriptblock]) | Should -BeTrue
            ($rowActionCallbacks.NewFailure -is [scriptblock]) | Should -BeTrue

            $dependencies = Resolve-InstalledAppExportWorkflowDependencies -Context $context
            ($dependencies.ListTraversal.GetVisibleRows -is [scriptblock]) | Should -BeTrue
            ($dependencies.RowAction.ExportForRow -is [scriptblock]) | Should -BeTrue
            ($dependencies.Logger.WriteWarning -is [scriptblock]) | Should -BeTrue
            ($dependencies.Workflow.InvokeScrollableList -is [scriptblock]) | Should -BeTrue
        }

        It 'requires explicit row action and logger dependencies for row processor construction' {
            $context = [pscustomobject]@{
                Logger = $null
                JobSettings = [pscustomobject]@{}
            }
            $successResults = New-Object System.Collections.ArrayList
            $failureResults = New-Object System.Collections.ArrayList

            {
                New-InstalledAppExportRowProcessor `
                    -Context $context `
                    -SuccessResults $successResults `
                    -FailureResults $failureResults `
                    -RowAction ([pscustomobject]@{
                        NewFailure = { param([string]$DataId, [string]$AssetName, [string]$Reason) New-InstalledAppExportFailure -DataId $DataId -AssetName $AssetName -Reason $Reason }
                    }) `
                    -Logger ([pscustomobject]@{ WriteWarning = { param([string]$Message) } })
            } | Should -Throw "*ExportForRow*"

            {
                New-InstalledAppExportRowProcessor `
                    -Context $context `
                    -SuccessResults $successResults `
                    -FailureResults $failureResults `
                    -RowAction ([pscustomobject]@{
                        ExportForRow = { param($Context, [string]$DataId, [string]$AssetName) [pscustomobject]@{} }
                        NewFailure = { param([string]$DataId, [string]$AssetName, [string]$Reason) New-InstalledAppExportFailure -DataId $DataId -AssetName $AssetName -Reason $Reason }
                    }) `
                    -Logger $null
            } | Should -Throw "*Logger*"
        }

        It 'records successful exports and converts row exceptions into failure rows through injected row action and logger' {
            $context = [pscustomobject]@{
                Logger = $null
                JobSettings = [pscustomobject]@{}
            }
            $successResults = New-Object System.Collections.ArrayList
            $failureResults = New-Object System.Collections.ArrayList
            $warnings = New-Object System.Collections.ArrayList

            $logger = [pscustomobject]@{
                WriteWarning = {
                    param([string]$Message)
                    [void]$warnings.Add($Message)
                }.GetNewClosure()
            }

            $exportForRow = {
                param($Context, [string]$DataId, [string]$AssetName)

                if ($AssetName -eq 'PC-FAIL') {
                    throw 'download failed'
                }

                return New-InstalledAppExportProcessResult -DataId $DataId -AssetName $AssetName -CsvPath ("C:\out\$AssetName.csv")
            }

            $newFailure = {
                param([string]$DataId, [string]$AssetName, [string]$Reason)
                New-InstalledAppExportFailure -DataId $DataId -AssetName $AssetName -Reason $Reason
            }

            $rowAction = [pscustomobject]@{
                ExportForRow = $exportForRow
                NewFailure = $newFailure
            }

            $processor = New-InstalledAppExportRowProcessor `
                -Context $context `
                -SuccessResults $successResults `
                -FailureResults $failureResults `
                -RowAction $rowAction `
                -Logger $logger

            & $processor ([pscustomobject]@{ dataId = 'row-ok'; assetName = 'PC-OK' })
            & $processor ([pscustomobject]@{ dataId = 'row-fail'; assetName = 'PC-FAIL' })

            @($successResults).Count | Should -Be 1
            @($failureResults).Count | Should -Be 1
            @($warnings).Count | Should -Be 1
            $successResults[0].AssetName | Should -Be 'PC-OK'
            $successResults[0].CsvPath | Should -Be 'C:\out\PC-OK.csv'
            $failureResults[0].DataId | Should -Be 'row-fail'
            $failureResults[0].AssetName | Should -Be 'PC-FAIL'
            $failureResults[0].Reason | Should -Match 'download failed'
            $warnings[0] | Should -Match '処理失敗: PC-FAIL'
        }

        It 'resolves missing row action and logger only through Dependencies before constructing list operations' {
            $context = [pscustomobject]@{
                Logger = $null
                JobSettings = [pscustomobject]@{}
            }
            $successResults = New-Object System.Collections.ArrayList
            $failureResults = New-Object System.Collections.ArrayList

            $dependencies = [pscustomobject]@{
                ListTraversal = [pscustomobject]@{
                    GetVisibleRows = { @() }
                    GetRowKey = { param($row) '' }
                    ScrollDown = { [pscustomobject]@{ Scrolled = $false } }
                }
            }

            $operations = New-InstalledAppExportListOperations `
                -Context $context `
                -SuccessResults $successResults `
                -FailureResults $failureResults `
                -Dependencies $dependencies

            ($operations.ProcessRow -is [scriptblock]) | Should -BeTrue
        }

        It 'forwards injected dependency object through list operations' {
            $context = [pscustomobject]@{
                Logger = $null
                JobSettings = [pscustomobject]@{}
            }
            $successResults = New-Object System.Collections.ArrayList
            $failureResults = New-Object System.Collections.ArrayList
            $called = New-Object System.Collections.ArrayList

            $traversalCalls = New-Object System.Collections.ArrayList
            $listTraversalCallbacks = [pscustomobject]@{
                GetVisibleRows = {
                    [void]$traversalCalls.Add('GetVisibleRows')
                    @([pscustomobject]@{ dataId = 'row-injected'; assetName = 'PC-INJECTED' })
                }.GetNewClosure()
                GetRowKey = {
                    param($row)
                    [void]$traversalCalls.Add('GetRowKey')
                    return "$($row.dataId)|$($row.assetName)"
                }.GetNewClosure()
                ScrollDown = {
                    [void]$traversalCalls.Add('ScrollDown')
                    [pscustomobject]@{ Scrolled = $false }
                }.GetNewClosure()
            }

            $rowActionCallbacks = [pscustomobject]@{
                ExportForRow = {
                    param($Context, [string]$DataId, [string]$AssetName)
                    [void]$called.Add("$DataId|$AssetName")
                    [pscustomobject]@{
                        DataId       = $DataId
                        AssetName = $AssetName
                        CsvPath      = 'C:\out\PC-INJECTED.csv'
                    }
                }.GetNewClosure()
                NewFailure = {
                    param([string]$DataId, [string]$AssetName, [string]$Reason)
                    New-InstalledAppExportFailure -DataId $DataId -AssetName $AssetName -Reason $Reason
                }
            }

            $logger = [pscustomobject]@{
                WriteWarning = { param([string]$Message) throw "unexpected warning: $Message" }
            }

            $dependencies = [pscustomobject]@{
                ListTraversal = $listTraversalCallbacks
                RowAction = $rowActionCallbacks
                Logger = $logger
            }

            $operations = New-InstalledAppExportListOperations `
                -Context $context `
                -SuccessResults $successResults `
                -FailureResults $failureResults `
                -Dependencies $dependencies

            $visibleRows = @(& $operations.GetVisibleRows)
            $visibleRows.Count | Should -Be 1
            (& $operations.GetRowKey $visibleRows[0]) | Should -Be 'row-injected|PC-INJECTED'
            (& $operations.ScrollDown).Scrolled | Should -BeFalse

            & $operations.ProcessRow $visibleRows[0]

            @($traversalCalls).Count | Should -Be 3
            @($called).Count | Should -Be 1
            $called[0] | Should -Be 'row-injected|PC-INJECTED'
            @($successResults).Count | Should -Be 1
            @($failureResults).Count | Should -Be 0
        }

        It 'closes the detail panel through a DomAdapter cleanup wait instead of DomOperations directly' {
            $calls = New-Object System.Collections.ArrayList
            $context = [pscustomobject]@{
                Logger = [pscustomobject]@{ Console = $false; File = $false; RunId = 'test' }
                JobSettings = [pscustomobject]@{
                    DetailPanelCloseWaitSeconds = 7
                }
            }

            Mock Write-FoundationLog { }
            Mock Close-InstalledAppExportDetailPanel -MockWith ({
                [void]$calls.Add('CloseDetail')
                return [pscustomobject]@{ ok = $true; action = 'closed' }
            }.GetNewClosure())
            Mock Wait-InstalledAppExportDetailPanelClosed -MockWith ({
                param([int]$TimeoutSeconds)
                [void]$calls.Add("WaitClosed:$TimeoutSeconds")
                return $true
            }.GetNewClosure())
            Mock Wait-InstalledAppExportDomOperation { throw 'RowAction must not call DomOperations directly.' }

            Close-InstalledAppExportDetailPanelSafely -Context $context

            (@($calls) -join '|') | Should -Be 'CloseDetail|WaitClosed:7'
            Should -Invoke -CommandName Close-InstalledAppExportDetailPanel -Times 1 -Exactly
            Should -Invoke -CommandName Wait-InstalledAppExportDetailPanelClosed -Times 1 -Exactly
            Should -Invoke -CommandName Wait-InstalledAppExportDomOperation -Times 0 -Exactly
        }

        It 'keeps asset row export flow visible while delegating concrete steps to named helpers' {
            $calls = New-Object System.Collections.ArrayList
            $context = [pscustomobject]@{
                Logger = [pscustomobject]@{ Console = $false; File = $false; RunId = 'test' }
                JobSettings = [pscustomobject]@{
                    TempDirectory = 'C:\temp\asset'
                    DownloadFilePrefix = 'export'
                    DownloadTimeoutSeconds = 30
                    DownloadStableSeconds = 1
                    DownloadDirectory = 'C:\out\asset'
                }
                Services = [pscustomobject]@{
                    FileSystem = [pscustomobject]@{
                        ClearDirectory = { param([string]$Directory, [string]$Purpose) [void]$calls.Add('ClearTemp') }.GetNewClosure()
                    }
                }
            }

            Mock Write-FoundationLog { }
            Mock Write-FoundationObject { }
            Mock Open-InstalledAppExportDetailPanel -MockWith ({ [void]$calls.Add('OpenDetail'); [pscustomobject]@{ ok = $true } }.GetNewClosure())
            Mock Assert-InstalledAppExportDetailPanel -MockWith ({ [void]$calls.Add('AssertDetail'); [pscustomobject]@{ ok = $true } }.GetNewClosure())
            Mock Open-InstalledAppExportAppTab -MockWith ({ [void]$calls.Add('OpenAppTab'); [pscustomobject]@{ ok = $true } }.GetNewClosure())
            Mock Assert-InstalledAppExportAppList -MockWith ({ [void]$calls.Add('AssertAppList'); [pscustomobject]@{ ok = $true } }.GetNewClosure())
            Mock Assert-InstalledAppExportAppRadioChecked -MockWith ({ [void]$calls.Add('AssertRadio'); [pscustomobject]@{ ok = $true } }.GetNewClosure())
            Mock Get-InstalledAppExportDetailName -MockWith ({ [void]$calls.Add('GetDetailName'); 'PC-001' }.GetNewClosure())
            Mock Click-InstalledAppExportAppCsvButton -MockWith ({ [void]$calls.Add('ClickCsv'); [pscustomobject]@{ ok = $true } }.GetNewClosure())
            Mock Wait-InstalledAppExportDownloadedCsv -MockWith ({ [void]$calls.Add('WaitDownload'); New-Object System.IO.FileInfo 'C:\temp\asset\export.csv' }.GetNewClosure())
            Mock Rename-InstalledAppExportDownloadedCsv -MockWith ({ [void]$calls.Add('RenameCsv'); New-Object System.IO.FileInfo 'C:\out\asset\PC-001.csv' }.GetNewClosure())
            Mock Close-InstalledAppExportDetailPanelSafely -MockWith ({ [void]$calls.Add('Cleanup') }.GetNewClosure())

            $result = Invoke-InstalledAppExportCsvForRow -Context $context -DataId 'row-1' -AssetName 'PC-001'

            $result.DataId | Should -Be 'row-1'
            $result.AssetName | Should -Be 'PC-001'
            $result.CsvPath | Should -Be 'C:\out\asset\PC-001.csv'
            (@($calls) -join '|') | Should -Be 'OpenDetail|AssertDetail|OpenAppTab|AssertAppList|AssertRadio|GetDetailName|ClearTemp|ClickCsv|WaitDownload|RenameCsv|Cleanup'
        }

        It 'runs the export workflow through injected Workflow port instead of calling Foundation workflow directly' {
            $context = [pscustomobject]@{
                Logger = $null
                JobSettings = [pscustomobject]@{
                    MaxScanLoops = 10
                    SameScrollLimit = 2
                }
            }
            $workflowCalls = New-Object System.Collections.ArrayList

            $dependencies = [pscustomobject]@{
                ListTraversal = [pscustomobject]@{
                    GetVisibleRows = { @() }
                    GetRowKey = { param($row) '' }
                    ScrollDown = { [pscustomobject]@{ Scrolled = $false } }
                }
                RowAction = [pscustomobject]@{
                    ExportForRow = { param($Context, [string]$DataId, [string]$AssetName) throw 'not expected' }
                    NewFailure = { param([string]$DataId, [string]$AssetName, [string]$Reason) New-InstalledAppExportFailure -DataId $DataId -AssetName $AssetName -Reason $Reason }
                }
                Logger = [pscustomobject]@{
                    WriteWarning = { param([string]$Message) throw "unexpected warning: $Message" }
                }
                Workflow = [pscustomobject]@{
                    InvokeScrollableList = {
                        param([int]$TotalCount, $Operations, $Logger, [int]$MaxScanLoops, [int]$SameScrollLimit, [string]$EmptyRowsMessage)
                        [void]$workflowCalls.Add("$TotalCount|$MaxScanLoops|$SameScrollLimit|$EmptyRowsMessage|$($Operations.Name)")
                        [pscustomobject]@{ ProcessedCount = 0; TotalCount = $TotalCount; LoopCount = 0; Completed = $true; ProcessedKeys = @() }
                    }.GetNewClosure()
                }
            }

            $result = Invoke-InstalledAppExportCsvWorkflow -Context $context -TotalCount 0 -Dependencies $dependencies

            @($workflowCalls).Count | Should -Be 1
            $workflowCalls[0] | Should -Be '0|10|2|端末行を取得できませんでした。|InstalledAppExportListOperations'
            $result.ScanResult.TotalCount | Should -Be 0
            @($result.SuccessResults).Count | Should -Be 0
            @($result.FailureResults).Count | Should -Be 0
        }
    }
}
