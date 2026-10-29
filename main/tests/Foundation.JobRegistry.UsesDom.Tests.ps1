$ErrorActionPreference = "Stop"
$modulePath = Join-Path $PSScriptRoot '..\modules\Foundation\Foundation.psm1'
Import-Module -Name $modulePath -Force

InModuleScope Foundation {
    Describe 'Foundation job registry UsesDom contract' {
        BeforeEach {
            $script:Root = Join-Path $TestDrive 'root'
            New-Item -ItemType Directory -Path (Join-Path $script:Root 'config') -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $script:Root 'modules\LastMonthInstallExtract') -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $script:Root 'modules\LastMonthInstallExtract\LastMonthInstallExtract.psm1') -Force | Out-Null
        }

        It 'accepts a file-only job without DOM feature paths' {
            $registryPath = Join-Path $script:Root 'config\foundation.jobs.psd1'
            Set-Content -LiteralPath $registryPath -Encoding UTF8 -Value @'
@{
    Jobs = @{
        LastMonthInstallExtract = @{
            ModulePath = 'modules\LastMonthInstallExtract\LastMonthInstallExtract.psm1'
            CommandName = 'Invoke-LastMonthInstallExtractJob'
            UsesDom = $false
        }
    }
}
'@

            $registry = Import-FoundationJobRegistry -Path $registryPath -RootPath $script:Root -ValidateAllFiles
            $definition = Get-FoundationJobDefinition -Registry $registry -JobName 'LastMonthInstallExtract'

            $definition.ModulePath | Should -Be (Join-Path $script:Root 'modules\LastMonthInstallExtract\LastMonthInstallExtract.psm1')
            $definition.UsesDom | Should -Be $false
            $definition.ContainsKey('DomFeaturePath') | Should -Be $false
            $definition.ContainsKey('DomFeaturePaths') | Should -Be $false
        }

        It 'rejects DOM paths when UsesDom is false' {
            $definition = @{
                ModulePath = 'modules\LastMonthInstallExtract\LastMonthInstallExtract.psm1'
                CommandName = 'Invoke-LastMonthInstallExtractJob'
                UsesDom = $false
                DomFeaturePath = 'dom\features\last-month-install-extract\index.js'
            }

            { Assert-FoundationJobDefinition -JobName 'LastMonthInstallExtract' -Definition $definition } | Should -Throw
        }

        It 'accepts DOM jobs that omit UsesDom when DOM feature paths are defined' {
            $definition = @{
                ModulePath = 'modules\Example\Example.psm1'
                CommandName = 'Invoke-ExampleJob'
                DomFeaturePaths = @('dom\features\example\index.js')
            }

            { Assert-FoundationJobDefinition -JobName 'Example' -Definition $definition } | Should -Not -Throw
        }
    }
}
