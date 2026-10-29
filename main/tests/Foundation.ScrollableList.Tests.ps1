$ErrorActionPreference = "Stop"
$modulePath = Join-Path $PSScriptRoot '..\modules\Foundation\Foundation.psm1'
Import-Module -Name $modulePath -Force

InModuleScope Foundation {
    Describe 'Foundation scrollable list workflow' {
        It 'requires all operation scriptblocks' {
            $operations = [pscustomobject]@{
                GetVisibleRows = { @() }
                GetRowKey = { param($row) $row.id }
                ProcessRow = { param($row) }
            }
            { Assert-ScrollableListOperations -Operations $operations } | Should -Throw
        }

        It 'processes unprocessed visible rows and reports completion' {
            $rows = @([pscustomobject]@{ id = 'a' }, [pscustomobject]@{ id = 'b' })
            $processed = New-Object System.Collections.ArrayList
            $operations = [pscustomobject]@{
                GetVisibleRows = { return $rows }
                GetRowKey = { param($row) return $row.id }
                ProcessRow = { param($row) [void]$processed.Add($row.id) }
                ScrollDown = { return [pscustomobject]@{ changed = $false } }
            }
            $logger = [pscustomobject]@{ Console = $false; File = $false; RunId = 'test' }
            $result = Invoke-ScrollableListWorkflow -TotalCount 2 -Operations $operations -Logger $logger -MaxScanLoops 3 -SameScrollLimit 1
            $result.Completed | Should -BeTrue
            $result.ProcessedCount | Should -Be 2
            @($processed).Count | Should -Be 2
        }

        It 'throws the configured message when no visible rows are available' {
            $operations = [pscustomobject]@{
                GetVisibleRows = { return @() }
                GetRowKey = { param($row) return $row.id }
                ProcessRow = { param($row) }
                ScrollDown = { return [pscustomobject]@{ changed = $false } }
            }
            { Invoke-ScrollableListWorkflow -TotalCount 1 -Operations $operations -Logger ([pscustomobject]@{ Console = $false; File = $false; RunId = 'test' }) -EmptyRowsMessage 'empty rows' } | Should -Throw
        }

        It 'uses an injected runtime when scrolling without unprocessed visible rows' {
            $scrollCalls = New-Object System.Collections.ArrayList
            $sleepCalls = New-Object System.Collections.ArrayList
            $rows = @([pscustomobject]@{ id = 'already-seen' })
            $operations = [pscustomobject]@{
                GetVisibleRows = { return $rows }
                GetRowKey = { param($row) return $row.id }
                ProcessRow = { param($row) throw 'ProcessRow should not be called for already processed row' }
                ScrollDown = {
                    [void]$scrollCalls.Add('ScrollDown')
                    return [pscustomobject]@{ changed = $false }
                }.GetNewClosure()
            }
            $runtime = [pscustomobject]@{
                SleepMilliseconds = {
                    param([int]$Milliseconds)
                    [void]$sleepCalls.Add($Milliseconds)
                }.GetNewClosure()
            }
            $logger = [pscustomobject]@{ Console = $false; File = $false; RunId = 'test' }

            $state = New-ScrollableListState -TotalCount 2
            $state.Processed['already-seen'] = $true
            $rowsFromStep = @(Get-ScrollableListVisibleRowsStep -Operations $operations -EmptyRowsMessage 'empty rows')
            $processedInStep = Invoke-ScrollableListUnprocessedRowsStep -State $state -Rows $rowsFromStep -Operations $operations
            $continue = Invoke-ScrollableListScrollStep -State $state -Operations $operations -Runtime $runtime -Logger $logger -SameScrollLimit 2

            $processedInStep | Should -Be 0
            $continue | Should -BeTrue
            @($scrollCalls).Count | Should -Be 1
            @($sleepCalls).Count | Should -Be 1
            $sleepCalls[0] | Should -Be 700
            $state.SameScrollCount | Should -Be 1
        }

        It 'rejects incomplete scrollable list runtime contracts before workflow polling' {
            $operations = [pscustomobject]@{
                GetVisibleRows = { return @([pscustomobject]@{ id = 'a' }) }
                GetRowKey = { param($row) return $row.id }
                ProcessRow = { param($row) }
                ScrollDown = { return [pscustomobject]@{ changed = $false } }
            }

            {
                Invoke-ScrollableListWorkflow `
                    -TotalCount 1 `
                    -Operations $operations `
                    -Logger ([pscustomobject]@{ Console = $false; File = $false; RunId = 'test' }) `
                    -Runtime ([pscustomobject]@{})
            } | Should -Throw '*SleepMilliseconds*'
        }

    }
}
