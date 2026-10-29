$ErrorActionPreference = "Stop"
$repositoryRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Import-Module -Name (Join-Path $repositoryRoot 'modules\InstalledAppExport\InstalledAppExport.psm1') -Force

InModuleScope InstalledAppExport {
    Describe 'InstalledAppExport DOM adapter behavior' {
        It 'registers the configured Foundation DOM bundle through the common adapter entrypoint' {
            $context = [pscustomobject]@{ JobName = 'InstalledAppExport' }
            Mock Register-FoundationDomBundle { }

            Register-InstalledAppExportDomAdapter -Context $context

            Should -Invoke -CommandName Register-FoundationDomBundle -Times 1 -Exactly -ParameterFilter { $Context -eq $context }
        }
    }

    Describe 'InstalledAppExport DOM operation registry' {
        It 'defines complete operation metadata' {
            $script:InstalledAppExportDomOperations.Keys.Count | Should -BeGreaterThan 0

            foreach ($operation in $script:InstalledAppExportDomOperations.Keys) {
                $definition = Get-InstalledAppExportDomOperationDefinition -Operation $operation
                $definition.HelperName | Should -Be '__InstalledAppExportDomHelper'
                $definition.MissingHelperMessage | Should -Be 'InstalledAppExport DOM helper is not registered'
                [string]::IsNullOrWhiteSpace($definition.MethodName) | Should -BeFalse
                [string]::IsNullOrWhiteSpace($definition.MissingHelperBehavior) | Should -BeFalse
            }
        }

        It 'rejects an undefined operation key' {
            { Get-InstalledAppExportDomOperationDefinition -Operation 'MissingOperation' } | Should -Throw
        }

        It 'treats helper absence as contract failure for page and detail contract operations' {
            $expected = @{
                DetectPageIdentity = 'assetPageIdentity'
                ValidatePageContract = 'assetPage'
                ValidateListContract = 'assetList'
                ValidateClickedRowContext = 'clickedRowContext'
                ValidateAppListContract = 'appList'
            }

            foreach ($operation in $expected.Keys) {
                $definition = Get-InstalledAppExportDomOperationDefinition -Operation $operation
                $definition.MissingHelperBehavior | Should -Be 'ReturnContractFailure'
                $definition.ContractScope | Should -Be $expected[$operation]
            }
        }

        It 'does not hide helper absence as a null total count or non-fatal operational scroll' {
            (Get-InstalledAppExportDomOperationDefinition -Operation GetListTotalCount).MissingHelperBehavior | Should -Be 'Throw'
            (Get-InstalledAppExportDomOperationDefinition -Operation ScrollToTop).MissingHelperBehavior | Should -Be 'Throw'
        }

        It 'dispatches a named operation through Foundation DOM helper parameters' {
            $script:CapturedInstalledAppExportDomParameters = $null
            Mock Invoke-FoundationDomHelperMethod {
                param(
                    [string]$HelperName,
                    [string]$MethodName,
                    [object[]]$Arguments = @(),
                    [int]$TimeoutSeconds = 30,
                    [string]$MissingHelperBehavior = 'Throw',
                    [object]$MissingValue = $null,
                    [string]$ContractScope = 'domHelper',
                    [string]$MissingHelperMessage = '',
                    [int]$JsonDepth = 30,
                    [switch]$Await
                )
                $script:CapturedInstalledAppExportDomParameters = [pscustomobject]@{
                    HelperName = $HelperName
                    MethodName = $MethodName
                    Arguments = @($Arguments)
                    MissingHelperBehavior = $MissingHelperBehavior
                    MissingHelperMessage = $MissingHelperMessage
                    ContractScope = $ContractScope
                    TimeoutSeconds = $TimeoutSeconds
                    Await = $Await
                }
                return [pscustomobject]@{ ok = $true }
            }

            Invoke-InstalledAppExportDomOperation `
                -Operation ClickNameCell `
                -Arguments @('row-1', 'PC-001') `
                -TimeoutSeconds 9 | Out-Null

            Should -Invoke -CommandName Invoke-FoundationDomHelperMethod -Times 1 -Exactly
            $script:CapturedInstalledAppExportDomParameters.HelperName | Should -Be '__InstalledAppExportDomHelper'
            $script:CapturedInstalledAppExportDomParameters.MethodName | Should -Be 'clickAssetNameCell'
            $script:CapturedInstalledAppExportDomParameters.MissingHelperBehavior | Should -Be 'Throw'
            $script:CapturedInstalledAppExportDomParameters.MissingHelperMessage | Should -Be 'InstalledAppExport DOM helper is not registered'
            $script:CapturedInstalledAppExportDomParameters.ContractScope | Should -Be 'domHelper'
            $script:CapturedInstalledAppExportDomParameters.TimeoutSeconds | Should -Be 9
            $script:CapturedInstalledAppExportDomParameters.Await | Should -BeFalse
            $script:CapturedInstalledAppExportDomParameters.Arguments[0] | Should -Be 'row-1'
            $script:CapturedInstalledAppExportDomParameters.Arguments[1] | Should -Be 'PC-001'
        }

        It 'dispatches page identity detection as a contract failure capable probe without wait-only description metadata' {
            $script:CapturedInstalledAppExportIdentityParameters = $null
            Mock Invoke-FoundationDomHelperMethod {
                param(
                    [string]$HelperName,
                    [string]$MethodName,
                    [object[]]$Arguments = @(),
                    [int]$TimeoutSeconds = 30,
                    [string]$MissingHelperBehavior = 'Throw',
                    [object]$MissingValue = $null,
                    [string]$ContractScope = 'domHelper',
                    [string]$MissingHelperMessage = '',
                    [int]$JsonDepth = 30,
                    [switch]$Await
                )
                $script:CapturedInstalledAppExportIdentityParameters = [pscustomobject]@{
                    HelperName = $HelperName
                    MethodName = $MethodName
                    TimeoutSeconds = $TimeoutSeconds
                    MissingHelperBehavior = $MissingHelperBehavior
                    MissingHelperMessage = $MissingHelperMessage
                    ContractScope = $ContractScope
                    Await = $Await
                }
                return [pscustomobject]@{ ok = $true }
            }

            Invoke-InstalledAppExportDomOperation `
                -Operation DetectPageIdentity `
                -TimeoutSeconds 2 | Out-Null

            Should -Invoke -CommandName Invoke-FoundationDomHelperMethod -Times 1 -Exactly
            $script:CapturedInstalledAppExportIdentityParameters.HelperName | Should -Be '__InstalledAppExportDomHelper'
            $script:CapturedInstalledAppExportIdentityParameters.MethodName | Should -Be 'detectAssetPageIdentity'
            $script:CapturedInstalledAppExportIdentityParameters.TimeoutSeconds | Should -Be 2
            $script:CapturedInstalledAppExportIdentityParameters.MissingHelperBehavior | Should -Be 'ReturnContractFailure'
            $script:CapturedInstalledAppExportIdentityParameters.MissingHelperMessage | Should -Be 'InstalledAppExport DOM helper is not registered'
            $script:CapturedInstalledAppExportIdentityParameters.ContractScope | Should -Be 'assetPageIdentity'
            $script:CapturedInstalledAppExportIdentityParameters.Await | Should -BeFalse
        }

        It 'waits for detail-panel cleanup through the operation registry rather than a raw helper call' {
            $script:WaitInstalledAppExportDomParameters = $null
            Mock Wait-FoundationDomHelperMethod {
                param(
                    [string]$HelperName,
                    [string]$MethodName,
                    [object[]]$Arguments = @(),
                    [int]$TimeoutSeconds = 10,
                    [string]$Description = 'DOM helper condition',
                    [string]$MissingHelperBehavior = 'Throw',
                    [object]$MissingValue = $null,
                    [string]$ContractScope = 'domHelper',
                    [string]$MissingHelperMessage = '',
                    [int]$JsonDepth = 30,
                    [switch]$Await
                )
                $script:WaitInstalledAppExportDomParameters = [pscustomobject]@{
                    HelperName = $HelperName
                    MethodName = $MethodName
                    MissingHelperBehavior = $MissingHelperBehavior
                    MissingValue = $MissingValue
                    MissingHelperMessage = $MissingHelperMessage
                    ContractScope = $ContractScope
                }
                return $true
            }

            Wait-InstalledAppExportDomOperation `
                -Operation IsDetailPanelClosed `
                -MissingValue $false | Out-Null

            Should -Invoke -CommandName Wait-FoundationDomHelperMethod -Times 1 -Exactly
            $script:WaitInstalledAppExportDomParameters.HelperName | Should -Be '__InstalledAppExportDomHelper'
            $script:WaitInstalledAppExportDomParameters.MethodName | Should -Be 'isDetailPanelClosed'
            $script:WaitInstalledAppExportDomParameters.MissingHelperBehavior | Should -Be 'ReturnValue'
            $script:WaitInstalledAppExportDomParameters.MissingValue | Should -BeFalse
            $script:WaitInstalledAppExportDomParameters.MissingHelperMessage | Should -Be 'InstalledAppExport DOM helper is not registered'
            $script:WaitInstalledAppExportDomParameters.ContractScope | Should -Be 'domHelper'
        }
    }
}
