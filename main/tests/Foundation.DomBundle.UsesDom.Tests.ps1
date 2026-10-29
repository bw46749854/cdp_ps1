$ErrorActionPreference = "Stop"
$modulePath = Join-Path $PSScriptRoot '..\modules\Foundation\Foundation.psm1'
Import-Module -Name $modulePath -Force

InModuleScope Foundation {
    Describe 'Foundation DOM bundle UsesDom contract' {
        It 'does not create a DOM bundle for file-only jobs' {
            $root = Join-Path $TestDrive 'root'
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            $definition = @{
                ModulePath = 'modules\LastMonthInstallExtract\LastMonthInstallExtract.psm1'
                CommandName = 'Invoke-LastMonthInstallExtractJob'
                UsesDom = $false
            }

            { Get-DomBundleDefinition -RootPath $root -JobName 'LastMonthInstallExtract' -JobDefinition $definition } | Should -Throw
        }

        It 'rejects Register-FoundationDomBundle for a file-only context' {
            $context = [pscustomobject]@{
                RootPath = $TestDrive
                JobName = 'LastMonthInstallExtract'
                JobDefinition = @{
                    ModulePath = 'modules\LastMonthInstallExtract\LastMonthInstallExtract.psm1'
                    CommandName = 'Invoke-LastMonthInstallExtractJob'
                    UsesDom = $false
                }
            }

            { Register-FoundationDomBundle -Context $context } | Should -Throw
        }
    }
}
