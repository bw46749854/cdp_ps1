$ErrorActionPreference = "Stop"
$modulePath = Join-Path $PSScriptRoot '..\modules\Foundation\Foundation.psm1'
Import-Module -Name $modulePath -Force

InModuleScope Foundation {
    Describe 'Foundation configuration' {
        It 'accepts config without hard-coded job set' {
            $config = @{
                Common = @{}
                Jobs = @{
                    CustomJob = @{ OutputDirectory = 'out' }
                }
            }

            { Assert-FoundationConfig -Config $config } | Should -Not -Throw
        }

        It 'throws when Common is missing' {
            $config = @{ Jobs = @{} }
            { Assert-FoundationConfig -Config $config } | Should -Throw
        }

        It 'throws when Jobs is missing' {
            $config = @{ Common = @{} }
            { Assert-FoundationConfig -Config $config } | Should -Throw
        }

        It 'throws when Common or Jobs are not hashtables' {
            { Assert-FoundationConfig -Config @{ Common = 'invalid'; Jobs = @{} } } | Should -Throw
            { Assert-FoundationConfig -Config @{ Common = @{}; Jobs = 'invalid' } } | Should -Throw
        }

        It 'returns a named job configuration' {
            $config = @{ Jobs = @{ ScanTargetSync = @{ InputCsvPath = 'input.csv' } } }
            $job = Get-FoundationJobConfig -Config $config -JobName 'ScanTargetSync'
            $job.InputCsvPath | Should -Be 'input.csv'
        }

        It 'throws when a named job configuration is missing' {
            $config = @{ Jobs = @{} }
            { Get-FoundationJobConfig -Config $config -JobName 'Missing' } | Should -Throw
        }

        It 'throws when the named job configuration is not a hashtable' {
            $config = @{ Jobs = @{ BadJob = 'invalid' } }
            { Get-FoundationJobConfig -Config $config -JobName 'BadJob' } | Should -Throw
        }
    }
}
