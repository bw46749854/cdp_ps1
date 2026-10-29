$ErrorActionPreference = "Stop"
$modulePath = Join-Path $PSScriptRoot '..\modules\Foundation\Foundation.psm1'
Import-Module -Name $modulePath -Force

InModuleScope Foundation {
    Describe 'Foundation logging' {
        It 'creates a console-suppressed logger from configuration' {
            $logger = New-FoundationLogger -Config @{ Console = $false; File = $false; Level = 'Debug' } -RunId 'unit'
            $logger.Console | Should -BeFalse
            $logger.File | Should -BeFalse
            $logger.Level | Should -Be 'Debug'
            $logger.RunId | Should -Be 'unit'
        }
    }
}
