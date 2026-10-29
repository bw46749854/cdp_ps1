$ErrorActionPreference = "Stop"
$repositoryRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Import-Module -Name (Join-Path $repositoryRoot 'modules\ScanTargetSync\ScanTargetSync.psm1') -Force

InModuleScope ScanTargetSync {
    Describe 'ScanTargetSync DOM adapter behavior' {
        It 'registers the configured Foundation DOM bundle through the common adapter entrypoint' {
            $context = [pscustomobject]@{ JobName = 'ScanTargetSync' }
            Mock Register-FoundationDomBundle { }

            Register-ScanTargetSyncDomAdapter -Context $context

            Should -Invoke -CommandName Register-FoundationDomBundle -Times 1 -Exactly -ParameterFilter { $Context -eq $context }
        }
    }

    Describe 'ScanTargetSync DOM operation registry' {
        It 'defines complete operation metadata' {
            $script:ScanTargetSyncDomOperations.Keys.Count | Should -BeGreaterThan 0

            foreach ($operation in $script:ScanTargetSyncDomOperations.Keys) {
                $definition = Get-ScanTargetSyncDomOperationDefinition -Operation $operation
                $definition.HelperName | Should -Be '__ScanTargetSyncDomHelper'
                $definition.MissingHelperMessage | Should -Be 'ScanTargetSync DOM helper is not registered'
                [string]::IsNullOrWhiteSpace($definition.MethodName) | Should -BeFalse
                [string]::IsNullOrWhiteSpace($definition.MissingHelperBehavior) | Should -BeFalse
            }
        }

        It 'rejects an undefined operation key' {
            { Get-ScanTargetSyncDomOperationDefinition -Operation 'MissingOperation' } | Should -Throw
        }
        It 'treats helper absence as contract failure for page identity and contract validation operations' {
            $expected = @{
                DetectPageIdentity = 'scanTargetSyncDevicePageIdentity'
                ValidateDevicePageContract = 'scanTargetSyncDevicePage'
                ValidateDeviceListContract = 'scanTargetSyncDeviceList'
                ValidatePostSelectionContract = 'scanTargetSyncPostSelection'
            }

            foreach ($operation in $expected.Keys) {
                $definition = Get-ScanTargetSyncDomOperationDefinition -Operation $operation
                $definition.MissingHelperBehavior | Should -Be 'ReturnContractFailure'
                $definition.ContractScope | Should -Be $expected[$operation]
            }
        }

        It 'does not hide helper absence as an empty row collection' {
            $definition = Get-ScanTargetSyncDomOperationDefinition -Operation FindDeviceRowsInfo
            $definition.MissingHelperBehavior | Should -Be 'Throw'
            $definition.ContainsKey('MissingValue') | Should -BeFalse
        }

        It 'dispatches a checkbox sync operation through Foundation DOM helper parameters' {
            $script:CapturedScanTargetSyncDomParameters = $null
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
                $script:CapturedScanTargetSyncDomParameters = [pscustomobject]@{
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

            Invoke-ScanTargetSyncDomOperation `
                -Operation SyncEndpointCheckbox `
                -Arguments @('PC-001', $true) `
                -TimeoutSeconds 20 | Out-Null

            Should -Invoke -CommandName Invoke-FoundationDomHelperMethod -Times 1 -Exactly
            $script:CapturedScanTargetSyncDomParameters.HelperName | Should -Be '__ScanTargetSyncDomHelper'
            $script:CapturedScanTargetSyncDomParameters.MethodName | Should -Be 'syncEndpointCheckbox'
            $script:CapturedScanTargetSyncDomParameters.MissingHelperBehavior | Should -Be 'Throw'
            $script:CapturedScanTargetSyncDomParameters.MissingHelperMessage | Should -Be 'ScanTargetSync DOM helper is not registered'
            $script:CapturedScanTargetSyncDomParameters.ContractScope | Should -Be 'domHelper'
            $script:CapturedScanTargetSyncDomParameters.TimeoutSeconds | Should -Be 20
            $script:CapturedScanTargetSyncDomParameters.Await | Should -BeTrue
            $script:CapturedScanTargetSyncDomParameters.Arguments[0] | Should -Be 'PC-001'
            $script:CapturedScanTargetSyncDomParameters.Arguments[1] | Should -BeTrue
        }

        It 'dispatches page identity detection as a contract failure capable probe without wait-only description metadata' {
            $script:CapturedScanTargetSyncIdentityParameters = $null
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
                $script:CapturedScanTargetSyncIdentityParameters = [pscustomobject]@{
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

            Invoke-ScanTargetSyncDomOperation `
                -Operation DetectPageIdentity `
                -TimeoutSeconds 2 | Out-Null

            Should -Invoke -CommandName Invoke-FoundationDomHelperMethod -Times 1 -Exactly
            $script:CapturedScanTargetSyncIdentityParameters.HelperName | Should -Be '__ScanTargetSyncDomHelper'
            $script:CapturedScanTargetSyncIdentityParameters.MethodName | Should -Be 'detectDevicePageIdentity'
            $script:CapturedScanTargetSyncIdentityParameters.TimeoutSeconds | Should -Be 2
            $script:CapturedScanTargetSyncIdentityParameters.MissingHelperBehavior | Should -Be 'ReturnContractFailure'
            $script:CapturedScanTargetSyncIdentityParameters.MissingHelperMessage | Should -Be 'ScanTargetSync DOM helper is not registered'
            $script:CapturedScanTargetSyncIdentityParameters.ContractScope | Should -Be 'scanTargetSyncDevicePageIdentity'
            $script:CapturedScanTargetSyncIdentityParameters.Await | Should -BeFalse
        }

        It 'passes contract scope and helper diagnostics to Foundation contract assertion' {
            $script:CapturedScanTargetSyncContractParameters = $null
            Mock Assert-FoundationDomHelperContract {
                param(
                    [string]$HelperName,
                    [string]$MethodName,
                    [object[]]$Arguments = @(),
                    [int]$TimeoutSeconds = 20,
                    [string]$Description,
                    [string]$MissingHelperBehavior = 'Throw',
                    [object]$MissingValue = $null,
                    [string]$ContractScope = 'domHelper',
                    [string]$MissingHelperMessage = '',
                    [int]$JsonDepth = 30,
                    [switch]$Await
                )
                $script:CapturedScanTargetSyncContractParameters = [pscustomobject]@{
                    HelperName = $HelperName
                    MethodName = $MethodName
                    Description = $Description
                    MissingHelperBehavior = $MissingHelperBehavior
                    ContractScope = $ContractScope
                    MissingHelperMessage = $MissingHelperMessage
                }
                return [pscustomobject]@{ ok = $true; fatalCount = 0; warningCount = 0 }
            }

            Assert-ScanTargetSyncDomOperationContract `
                -Operation ValidateDevicePageContract `
                -TimeoutSeconds 30 | Out-Null

            Should -Invoke -CommandName Assert-FoundationDomHelperContract -Times 1 -Exactly
            $script:CapturedScanTargetSyncContractParameters.HelperName | Should -Be '__ScanTargetSyncDomHelper'
            $script:CapturedScanTargetSyncContractParameters.MethodName | Should -Be 'validateDevicePageContract'
            $script:CapturedScanTargetSyncContractParameters.Description | Should -Be 'デバイス一覧画面契約'
            $script:CapturedScanTargetSyncContractParameters.MissingHelperBehavior | Should -Be 'ReturnContractFailure'
            $script:CapturedScanTargetSyncContractParameters.ContractScope | Should -Be 'scanTargetSyncDevicePage'
            $script:CapturedScanTargetSyncContractParameters.MissingHelperMessage | Should -Be 'ScanTargetSync DOM helper is not registered'
        }
    }
}
