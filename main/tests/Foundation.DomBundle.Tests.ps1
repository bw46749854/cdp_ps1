$ErrorActionPreference = "Stop"
$repositoryRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$modulePath = Join-Path $repositoryRoot 'modules\Foundation\Foundation.psm1'
Import-Module -Name $modulePath -Force

InModuleScope Foundation {
    Describe 'Foundation DOM bundle registry integration' {
        BeforeAll {
            function New-TestDomBundleRoot {
                $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
                $featureDirectory = Join-Path $root 'dom\features'
                $configDirectory = Join-Path $root 'config'

                New-Item -ItemType Directory -Path $featureDirectory -Force | Out-Null
                New-Item -ItemType Directory -Path $configDirectory -Force | Out-Null

                return $root
            }
        }

        It 'uses DomFeaturePath from the job definition instead of hard-coded job names' {
            $root = New-TestDomBundleRoot
            $definition = @{
                ModulePath = 'modules\Example\Example.psm1'
                CommandName = 'Invoke-ExampleJob'
                DomFeaturePath = 'dom\features\example.dom.js'
            }

            $paths = @(Get-DomBundleDefinition -RootPath $root -JobName 'Example' -JobDefinition $definition)

            $paths.Count | Should -Be 1
            $paths[0] | Should -Be (Join-Path $root 'dom\features\example.dom.js')
            $paths | Should -Not -Match 'dom[\\/]common'
        }

        It 'uses DomFeaturePaths from the job definition in configured order' {
            $root = New-TestDomBundleRoot
            $definition = @{
                ModulePath = 'modules\Example\Example.psm1'
                CommandName = 'Invoke-ExampleJob'
                DomFeaturePaths = @(
                    'dom\features\example.contract.js'
                    'dom\features\example.actions.js'
                )
            }

            $paths = @(Get-DomBundleDefinition -RootPath $root -JobName 'Example' -JobDefinition $definition)

            $paths.Count | Should -Be 2
            $paths[0] | Should -Be (Join-Path $root 'dom\features\example.contract.js')
            $paths[1] | Should -Be (Join-Path $root 'dom\features\example.actions.js')
            $paths | Should -Not -Match 'dom[\\/]common'
        }
        It 'throws when the job definition has no DOM feature path key' {
            $root = New-TestDomBundleRoot
            $definition = @{
                ModulePath = 'modules\Example\Example.psm1'
                CommandName = 'Invoke-ExampleJob'
            }

            { Get-DomBundleDefinition -RootPath $root -JobName 'Example' -JobDefinition $definition } | Should -Throw
        }

        It 'throws when DomFeaturePath and DomFeaturePaths are both specified' {
            $root = New-TestDomBundleRoot
            $definition = @{
                ModulePath = 'modules\Example\Example.psm1'
                CommandName = 'Invoke-ExampleJob'
                DomFeaturePath = 'dom\features\example.dom.js'
                DomFeaturePaths = @('dom\features\example.contract.js')
            }

            { Get-DomBundleDefinition -RootPath $root -JobName 'Example' -JobDefinition $definition } | Should -Throw
        }

        It 'throws when DomFeaturePaths is not an array' {
            $root = New-TestDomBundleRoot
            $definition = @{
                ModulePath = 'modules\Example\Example.psm1'
                CommandName = 'Invoke-ExampleJob'
                DomFeaturePaths = 'dom\features\example.dom.js'
            }

            { Get-DomBundleDefinition -RootPath $root -JobName 'Example' -JobDefinition $definition } | Should -Throw
        }

        It 'registers a context job definition without requiring a job-name switch' {
            $root = New-TestDomBundleRoot
            $featurePath = Join-Path $root 'dom\features\example.dom.js'
            Set-Content -LiteralPath $featurePath -Value '// feature: example' -Encoding UTF8

            $script:RegisteredDomExpression = $null
            Mock Invoke-FoundationJavaScript {
                $script:RegisteredDomExpression = $Expression
                return $true
            }
            Mock Write-FoundationLog { }

            $context = [pscustomobject]@{
                RootPath = $root
                JobName = 'Example'
                JobDefinition = @{
                    ModulePath = 'modules\Example\Example.psm1'
                    CommandName = 'Invoke-ExampleJob'
                    DomFeaturePath = $featurePath
                }
            }

            Register-FoundationDomBundle -Context $context

            $script:RegisteredDomExpression | Should -Match 'feature: example'
            $script:RegisteredDomExpression | Should -Match 'sourceURL=foundation-Example-dom-bundle.js'
            Assert-MockCalled Invoke-FoundationJavaScript -Times 1 -Exactly
        }

        It 'registers context job definitions with multiple feature DOM files in configured order' {
            $root = New-TestDomBundleRoot
            $firstFeaturePath = Join-Path $root 'dom\features\example.contract.js'
            $secondFeaturePath = Join-Path $root 'dom\features\example.actions.js'
            Set-Content -LiteralPath $firstFeaturePath -Value '// feature: contract' -Encoding UTF8
            Set-Content -LiteralPath $secondFeaturePath -Value '// feature: actions' -Encoding UTF8

            $script:RegisteredDomExpression = $null
            Mock Invoke-FoundationJavaScript {
                $script:RegisteredDomExpression = $Expression
                return $true
            }
            Mock Write-FoundationLog { }

            $context = [pscustomobject]@{
                RootPath = $root
                JobName = 'Example'
                JobDefinition = @{
                    ModulePath = 'modules\Example\Example.psm1'
                    CommandName = 'Invoke-ExampleJob'
                    DomFeaturePaths = @(
                        $firstFeaturePath
                        $secondFeaturePath
                    )
                }
            }

            Register-FoundationDomBundle -Context $context

            $contractIndex = $script:RegisteredDomExpression.IndexOf('feature: contract')
            $actionsIndex = $script:RegisteredDomExpression.IndexOf('feature: actions')
            $contractIndex | Should -BeGreaterThan -1
            $actionsIndex | Should -BeGreaterThan $contractIndex
            Assert-MockCalled Invoke-FoundationJavaScript -Times 1 -Exactly
        }

        It 'keeps RootPath and JobName compatibility by reading foundation.jobs.psd1' {
            $root = New-TestDomBundleRoot
            $moduleDirectory = Join-Path $root 'modules\Example'
            New-Item -ItemType Directory -Path $moduleDirectory -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $moduleDirectory 'Example.psm1') -Force | Out-Null

            $featurePath = Join-Path $root 'dom\features\example.dom.js'
            Set-Content -LiteralPath $featurePath -Value '// registry feature: example' -Encoding UTF8

            $registryPath = Join-Path (Join-Path $root 'config') 'foundation.jobs.psd1'
            Set-Content -LiteralPath $registryPath -Encoding UTF8 -Value @'
@{
    Jobs = @{
        Example = @{
            ModulePath = 'modules\Example\Example.psm1'
            CommandName = 'Invoke-ExampleJob'
            DomFeaturePath = 'dom\features\example.dom.js'
        }
    }
}
'@

            $script:RegisteredDomExpression = $null
            Mock Invoke-FoundationJavaScript {
                $script:RegisteredDomExpression = $Expression
                return $true
            }
            Mock Write-FoundationLog { }

            Register-FoundationDomBundle -RootPath $root -JobName 'Example'

            $script:RegisteredDomExpression | Should -Match 'registry feature: example'
            Assert-MockCalled Invoke-FoundationJavaScript -Times 1 -Exactly
        }
    }
}

Describe 'Foundation DOM bundle source' {
    BeforeAll {
        $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
        $script:DomBundlePath = Join-Path $script:RepositoryRoot 'modules\Foundation\internal\DomBundle.ps1'
        $script:DomHelperPath = Join-Path $script:RepositoryRoot 'modules\Foundation\internal\DomHelper.ps1'
    }

    It 'does not hard-code feature DOM paths or fixed job-name validation' {
        $domBundleText = Get-Content -LiteralPath $script:DomBundlePath -Raw
        $domHelperText = Get-Content -LiteralPath $script:DomHelperPath -Raw

        $fixedJobNameValidateSetPattern = '\[ValidateSet\([^\)]*\)\]\s*\[string\]\$JobName'
        $domBundleText | Should -Not -Match $fixedJobNameValidateSetPattern
        $domHelperText | Should -Not -Match $fixedJobNameValidateSetPattern
        $domBundleText | Should -Not -Match 'switch \(\$JobName\)'
        $domBundleText | Should -Not -Match 'asset\.dom\.js'
        $domBundleText | Should -Not -Match 'scan-target-sync\.dom\.js'
    }
}
