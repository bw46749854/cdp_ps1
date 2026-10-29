$ErrorActionPreference = "Stop"
$repositoryRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$modulePath = Join-Path $repositoryRoot 'modules\Foundation\Foundation.psm1'
Import-Module -Name $modulePath -Force

InModuleScope Foundation {
    Describe 'Foundation DOM helper expression builder' {
        It 'serializes helper name, method name, arguments, and await invocation into one expression' {
            $arguments = @(
                [pscustomobject]@{
                    Endpoint = 'PC "001"'
                    DesiredChecked = $true
                    Tags = @('alpha', 'beta')
                },
                $null
            )

            $expression = New-FoundationDomHelperMethodExpression `
                -HelperName '__ScanTargetSyncDomHelper' `
                -MethodName 'syncEndpointCheckbox' `
                -Arguments $arguments `
                -Await

            $expression | Should -Match 'const helperName = "__ScanTargetSyncDomHelper";'
            $expression | Should -Match 'const methodName = "syncEndpointCheckbox";'
            $expression | Should -Match '"Endpoint":"PC \\"001\\""'
            $expression | Should -Match '"DesiredChecked":true'
            $expression | Should -Match '"Tags":\["alpha","beta"\]'
            $expression | Should -Match ',null\]'
            $expression | Should -Match 'const result = helper\[methodName\]\.apply\(helper, args\); return await result;'
        }

        It 'rejects helper and method names that are not JavaScript identifiers' {
            { New-FoundationDomHelperMethodExpression -HelperName 'window.__Helper' -MethodName 'run' } | Should -Throw
            { New-FoundationDomHelperMethodExpression -HelperName '__Helper' -MethodName 'bad-method' } | Should -Throw
        }

        It 'builds a structured contract failure when the helper is missing and contract failure mode is requested' {
            $scriptText = New-FoundationDomHelperMissingScript `
                -HelperName '__MissingDomHelper' `
                -MethodName 'validatePageContract' `
                -MissingHelperBehavior 'ReturnContractFailure' `
                -MissingValue $null `
                -ContractScope 'page.contract' `
                -MissingHelperMessage 'helper not present'

            $scriptText | Should -Match '^return \{'
            $scriptText | Should -Match '"scope":"page.contract"'
            $scriptText | Should -Match '"ok":false'
            $scriptText | Should -Match '"helperName":"__MissingDomHelper"'
            $scriptText | Should -Match '"methodName":"validatePageContract"'
            $scriptText | Should -Match '"reason":"helper_not_registered"'
        }
    }

    Describe 'Foundation DOM helper invocation facade' {
        It 'delegates generated expressions to Invoke-FoundationJavaScript with the requested timeout' {
            $script:CapturedExpression = $null
            $script:CapturedTimeoutSeconds = $null

            Mock Invoke-FoundationJavaScript {
                param([string]$Expression, [int]$TimeoutSeconds)
                $script:CapturedExpression = $Expression
                $script:CapturedTimeoutSeconds = $TimeoutSeconds
                return [pscustomobject]@{ ok = $true }
            }

            $result = Invoke-FoundationDomHelperMethod `
                -HelperName '__InstalledAppExportDomHelper' `
                -MethodName 'findAssetRowsInfo' `
                -Arguments @('row-001') `
                -TimeoutSeconds 12

            $result.ok | Should -Be $true
            $script:CapturedTimeoutSeconds | Should -Be 12
            $script:CapturedExpression | Should -Match '__InstalledAppExportDomHelper'
            $script:CapturedExpression | Should -Match 'findAssetRowsInfo'
            $script:CapturedExpression | Should -Match '"row-001"'
            Should -Invoke -CommandName Invoke-FoundationJavaScript -Times 1 -Exactly
        }

        It 'waits for accepted DOM helper results through an injected timing runtime' {
            $script:DomHelperWaitNow = [datetime]'2026-01-01T00:00:00'
            $script:DomHelperWaitSleeps = New-Object System.Collections.Generic.List[int]
            $script:DomHelperWaitCallCount = 0
            $script:DomHelperWaitTimeouts = New-Object System.Collections.Generic.List[int]

            $timing = [pscustomobject]@{
                Now = { $script:DomHelperWaitNow }
                SleepMilliseconds = {
                    param([int]$Milliseconds)
                    [void]$script:DomHelperWaitSleeps.Add($Milliseconds)
                    $script:DomHelperWaitNow = $script:DomHelperWaitNow.AddMilliseconds($Milliseconds)
                }
            }

            Mock Start-Sleep { throw 'real Start-Sleep should not be called when Timing is injected' }
            Mock Invoke-FoundationDomHelperMethod {
                param(
                    [string]$HelperName,
                    [string]$MethodName,
                    [object[]]$Arguments,
                    [int]$TimeoutSeconds
                )

                $HelperName | Should -Be '__ScanTargetSyncDomHelper'
                $MethodName | Should -Be 'isReady'
                [void]$script:DomHelperWaitTimeouts.Add($TimeoutSeconds)
                $script:DomHelperWaitCallCount++
                return ($script:DomHelperWaitCallCount -ge 2)
            }

            $result = Wait-FoundationDomHelperMethodResult `
                -HelperName '__ScanTargetSyncDomHelper' `
                -MethodName 'isReady' `
                -TimeoutSeconds 3 `
                -PollIntervalMilliseconds 250 `
                -Timing $timing

            $result | Should -Be $true
            $script:DomHelperWaitCallCount | Should -Be 2
            $script:DomHelperWaitSleeps.Count | Should -Be 1
            $script:DomHelperWaitSleeps[0] | Should -Be 250
            $script:DomHelperWaitTimeouts[0] | Should -Be 3
            Should -Invoke -CommandName Start-Sleep -Times 0 -Exactly
        }

        It 'rejects incomplete DOM helper timing runtime contracts before polling' {
            $timing = [pscustomobject]@{
                Now = { Get-Date }
            }

            { Wait-FoundationDomHelperMethodResult -HelperName '__Helper' -MethodName 'ready' -Timing $timing } |
                Should -Throw '*SleepMilliseconds*'
        }

    }
}
