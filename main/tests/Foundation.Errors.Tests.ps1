$ErrorActionPreference = "Stop"
$repositoryRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Import-Module -Name (Join-Path $repositoryRoot 'modules\Foundation\Foundation.psm1') -Force

InModuleScope Foundation {
    Describe 'Foundation fatal error classification' {
        It 'treats DOM helper registration failures as fatal errors' {
            Test-FoundationFatalError -Message 'ScanTargetSync DOM helper is not registered' | Should -BeTrue
            Test-FoundationFatalError -Message 'DOM helper is not registered: __ScanTargetSyncDomHelper' | Should -BeTrue
            Test-FoundationFatalError -Message 'DOM helper method is not registered: __ScanTargetSyncDomHelper.syncEndpointCheckbox' | Should -BeTrue
            Test-FoundationFatalError -Message 'helper_not_registered' | Should -BeTrue
        }

        It 'does not classify empty messages as fatal' {
            Test-FoundationFatalError -Message '' | Should -BeFalse
            Test-FoundationFatalError -Message $null | Should -BeFalse
        }
    }
}
