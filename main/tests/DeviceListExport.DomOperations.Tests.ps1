$ErrorActionPreference = "Stop"
$repositoryRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Import-Module -Name (Join-Path $repositoryRoot 'modules\DeviceListExport\DeviceListExport.psm1') -Force

InModuleScope DeviceListExport {
    Describe 'DeviceListExport DOM adapter behavior' {
        It 'registers the configured Foundation DOM bundle through the common adapter entrypoint' {
            $context = [pscustomobject]@{ JobName = 'DeviceListExport' }
            Mock Register-FoundationDomBundle { }

            Register-DeviceListExportDomAdapter -Context $context

            Should -Invoke -CommandName Register-FoundationDomBundle -Times 1 -Exactly -ParameterFilter { $Context -eq $context }
        }
    }

    Describe 'DeviceListExport DOM operation registry' {
        It 'defines complete operation metadata' {
            $script:DeviceListExportDomOperations.Keys.Count | Should -BeGreaterThan 0

            foreach ($operation in $script:DeviceListExportDomOperations.Keys) {
                $definition = Get-DeviceListExportDomOperationDefinition -Operation $operation
                $definition.HelperName | Should -Be '__DeviceListExportDomHelper'
                $definition.MissingHelperMessage | Should -Be 'DeviceListExport DOM helper is not registered'
                [string]::IsNullOrWhiteSpace($definition.MethodName) | Should -BeFalse
                [string]::IsNullOrWhiteSpace($definition.MissingHelperBehavior) | Should -BeFalse
            }
        }

        It 'rejects an undefined operation key' {
            { Get-DeviceListExportDomOperationDefinition -Operation 'MissingOperation' } | Should -Throw
        }
        It 'treats helper absence as contract failure for DeviceListExport contract operations' {
            $expected = @{
                DetectPageIdentity = 'deviceListExportPageIdentity'
                ValidateInitialContract = 'deviceListExportInitial'
                ValidateExportPageContract = 'deviceListExportPage'
                ValidateExportPostcondition = 'deviceListExportPostcondition'
            }

            foreach ($operation in $expected.Keys) {
                $definition = Get-DeviceListExportDomOperationDefinition -Operation $operation
                $definition.MissingHelperBehavior | Should -Be 'ReturnContractFailure'
                $definition.ContractScope | Should -Be $expected[$operation]
            }
        }

        It 'keeps workflow actions and wait predicates in their intended missing-helper modes' {
            (Get-DeviceListExportDomOperationDefinition -Operation ClickTaskButton).MissingHelperBehavior | Should -Be 'Throw'
            (Get-DeviceListExportDomOperationDefinition -Operation ClickExportMenuItem).MissingHelperBehavior | Should -Be 'Throw'
            (Get-DeviceListExportDomOperationDefinition -Operation IsTaskMenuReady).MissingHelperBehavior | Should -Be 'ReturnValue'
            (Get-DeviceListExportDomOperationDefinition -Operation IsTaskMenuReady).MissingValue | Should -BeFalse
        }

        It 'applies Await from operation metadata for async DeviceListExport DOM actions' {
            $script:CapturedDeviceListExportDomParameters = $null
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
                $script:CapturedDeviceListExportDomParameters = [pscustomobject]@{
                    HelperName = $HelperName
                    MethodName = $MethodName
                    MissingHelperBehavior = $MissingHelperBehavior
                    MissingHelperMessage = $MissingHelperMessage
                    ContractScope = $ContractScope
                    Await = $Await
                }
                return [pscustomobject]@{ ok = $true }
            }

            Invoke-DeviceListExportDomOperation `
                -Operation ClickTaskButton | Out-Null

            Should -Invoke -CommandName Invoke-FoundationDomHelperMethod -Times 1 -Exactly
            $script:CapturedDeviceListExportDomParameters.HelperName | Should -Be '__DeviceListExportDomHelper'
            $script:CapturedDeviceListExportDomParameters.MethodName | Should -Be 'clickTaskButton'
            $script:CapturedDeviceListExportDomParameters.MissingHelperBehavior | Should -Be 'Throw'
            $script:CapturedDeviceListExportDomParameters.MissingHelperMessage | Should -Be 'DeviceListExport DOM helper is not registered'
            $script:CapturedDeviceListExportDomParameters.ContractScope | Should -Be 'domHelper'
            $script:CapturedDeviceListExportDomParameters.Await | Should -BeTrue
        }
    }
}
