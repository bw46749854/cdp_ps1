$ErrorActionPreference = "Stop"
$modulePath = Join-Path $PSScriptRoot '..\modules\Foundation\Foundation.psm1'
Import-Module -Name $modulePath -Force

InModuleScope Foundation {
    Describe 'Foundation DOM contract result formatting' {
        BeforeAll {
            function New-TestDomContractResult {
                param(
                    [int]$FatalCount = 0,
                    [int]$WarningCount = 0,
                    [object[]]$Checks = @()
                )

                [pscustomobject]@{
                    scope = 'testScope'
                    ok = ($FatalCount -eq 0)
                    fatalCount = $FatalCount
                    warningCount = $WarningCount
                    checks = $Checks
                    details = [pscustomobject]@{ source = 'test' }
                }
            }
        }

        It 'formats failed checks with compact JSON details' {
            $result = New-TestDomContractResult -FatalCount 1 -Checks @(
                [pscustomobject]@{
                    name = 'selector.unique'
                    ok = $false
                    severity = 'fatal'
                    message = 'selector must be unique'
                    details = [pscustomobject]@{ candidateCount = 2; selector = 'button' }
                },
                [pscustomobject]@{
                    name = 'selector.visible'
                    ok = $true
                    severity = 'fatal'
                    message = 'selector must be visible'
                    details = [pscustomobject]@{ }
                }
            )

            $formatted = Format-DomContractResult -Result $result

            $formatted | Should -Match 'scope=testScope ok=False fatalCount=1 warningCount=0'
            $formatted | Should -Match '\[fatal\] selector\.unique: selector must be unique details='
            $formatted | Should -Match '"candidateCount":2'
            $formatted | Should -Not -Match 'selector\.visible'
        }

        It 'throws when the result is null' {
            { Assert-DomContractResult -Result $null -Description 'empty result' } | Should -Throw
        }

        It 'throws when fatal checks exist' {
            $result = New-TestDomContractResult -FatalCount 1 -Checks @(
                [pscustomobject]@{
                    name = 'fatal.check'
                    ok = $false
                    severity = 'fatal'
                    message = 'fatal failure'
                    details = [pscustomobject]@{ selector = '#missing' }
                }
            )

            { Assert-DomContractResult -Result $result -Description 'fatal contract' } | Should -Throw
        }

        It 'writes a warning without throwing when only warnings exist' {
            $result = New-TestDomContractResult -WarningCount 1 -Checks @(
                [pscustomobject]@{
                    name = 'warning.check'
                    ok = $false
                    severity = 'warning'
                    message = 'warning failure'
                    details = [pscustomobject]@{ selector = '#ambiguous' }
                }
            )

            Mock Write-Warning { }

            { Assert-DomContractResult -Result $result -Description 'warning contract' } | Should -Not -Throw
            Should -Invoke -CommandName Write-Warning -Times 1 -Exactly -ParameterFilter { $Message -match 'DOM契約 warning: warning contract' }
        }

        It 'does not warn or throw when the contract result has no failures' {
            $result = New-TestDomContractResult
            Mock Write-Warning { }

            { Assert-DomContractResult -Result $result -Description 'successful contract' } | Should -Not -Throw
            Should -Invoke -CommandName Write-Warning -Times 0 -Exactly
        }
    }
}
