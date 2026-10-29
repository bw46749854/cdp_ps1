$ErrorActionPreference = "Stop"
$modulePath = Join-Path $PSScriptRoot '..\modules\Foundation\Foundation.psm1'
Import-Module -Name $modulePath -Force

InModuleScope Foundation {
    Describe 'Foundation job registry' {
        BeforeAll {
            function New-TestFoundationJobRegistryRoot {
                $root = Join-Path $TestDrive 'root'
                $configDirectory = Join-Path $root 'config'
                $moduleDirectory = Join-Path $root 'modules\Example'
                $domDirectory = Join-Path $root 'dom\features'

                New-Item -ItemType Directory -Path $configDirectory -Force | Out-Null
                New-Item -ItemType Directory -Path $moduleDirectory -Force | Out-Null
                New-Item -ItemType Directory -Path $domDirectory -Force | Out-Null

                New-Item -ItemType File -Path (Join-Path $moduleDirectory 'Example.psm1') -Force | Out-Null
                New-Item -ItemType File -Path (Join-Path $domDirectory 'example.dom.js') -Force | Out-Null
                New-Item -ItemType File -Path (Join-Path $domDirectory 'example.contract.js') -Force | Out-Null
                New-Item -ItemType File -Path (Join-Path $domDirectory 'example.actions.js') -Force | Out-Null

                return $root
            }

            function Write-TestFoundationJobRegistryFile {
                param(
                    [Parameter(Mandatory)][string]$Path,
                    [Parameter(Mandatory)][string]$Content
                )

                Set-Content -LiteralPath $Path -Value $Content -Encoding UTF8
            }
        }

        It 'imports registry and resolves relative module and DOM paths' {
            $root = New-TestFoundationJobRegistryRoot
            $registryPath = Join-Path (Join-Path $root 'config') 'foundation.jobs.psd1'
            Write-TestFoundationJobRegistryFile -Path $registryPath -Content @'
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

            $registry = Import-FoundationJobRegistry -Path $registryPath -RootPath $root
            $definition = Get-FoundationJobDefinition -Registry $registry -JobName 'Example'

            $definition.CommandName | Should -Be 'Invoke-ExampleJob'
            $definition.ModulePath | Should -Be (Join-Path $root 'modules\Example\Example.psm1')
            $definition.DomFeaturePath | Should -Be (Join-Path $root 'dom\features\example.dom.js')
        }

        It 'imports registry and resolves ordered DomFeaturePaths' {
            $root = New-TestFoundationJobRegistryRoot
            $registryPath = Join-Path (Join-Path $root 'config') 'foundation.jobs.psd1'
            Write-TestFoundationJobRegistryFile -Path $registryPath -Content @'
@{
    Jobs = @{
        Example = @{
            ModulePath = 'modules\Example\Example.psm1'
            CommandName = 'Invoke-ExampleJob'
            DomFeaturePaths = @(
                'dom\features\example.contract.js'
                'dom\features\example.actions.js'
            )
        }
    }
}
'@

            $registry = Import-FoundationJobRegistry -Path $registryPath -RootPath $root
            $definition = Get-FoundationJobDefinition -Registry $registry -JobName 'Example'

            @($definition.DomFeaturePaths).Count | Should -Be 2
            $definition.DomFeaturePaths[0] | Should -Be (Join-Path $root 'dom\features\example.contract.js')
            $definition.DomFeaturePaths[1] | Should -Be (Join-Path $root 'dom\features\example.actions.js')
        }

        It 'imports a multi-job registry as one canonical hashtable output' {
            $root = New-TestFoundationJobRegistryRoot
            $registryPath = Join-Path (Join-Path $root 'config') 'foundation.jobs.psd1'
            Write-TestFoundationJobRegistryFile -Path $registryPath -Content @'
@{
    Jobs = @{
        InstalledAppExport = @{
            ModulePath = 'modules\InstalledAppExport\InstalledAppExport.psm1'
            CommandName = 'Invoke-InstalledAppExportJob'
            DomFeaturePaths = @(
                'dom\features\installed-app-export\contract.js'
                'dom\features\installed-app-export\list.js'
                'dom\features\installed-app-export\detail.js'
                'dom\features\installed-app-export\apps.js'
                'dom\features\installed-app-export\actions.js'
                'dom\features\installed-app-export\index.js'
            )
        }
        ScanTargetSync = @{
            ModulePath = 'modules\ScanTargetSync\ScanTargetSync.psm1'
            CommandName = 'Invoke-ScanTargetSyncJob'
            DomFeaturePaths = @(
                'dom\features\scan-target-sync\contract.js'
                'dom\features\scan-target-sync\list.js'
                'dom\features\scan-target-sync\actions.js'
                'dom\features\scan-target-sync\index.js'
            )
        }
    }
}
'@

            $output = @(Import-FoundationJobRegistry -Path $registryPath -RootPath $root)

            $output.Count | Should -Be 1
            ($output[0] -is [hashtable]) | Should -Be $true
            $output[0].Jobs.ContainsKey('InstalledAppExport') | Should -Be $true
            $output[0].Jobs.ContainsKey('ScanTargetSync') | Should -Be $true
            $output[0].Jobs.InstalledAppExport.DomFeaturePaths[0] | Should -Be (Join-Path $root 'dom\features\installed-app-export\contract.js')
            $output[0].Jobs.ScanTargetSync.DomFeaturePaths[3] | Should -Be (Join-Path $root 'dom\features\scan-target-sync\index.js')
        }

        It 'normalizes one job definition without emitting pipeline output' {
            $root = New-TestFoundationJobRegistryRoot
            $definition = @{
                ModulePath = 'modules\Example\Example.psm1'
                CommandName = 'Invoke-ExampleJob'
                DomFeaturePath = 'dom\features\example.dom.js'
            }

            $output = @(Resolve-FoundationJobDefinitionPaths -Definition $definition -RootPath $root)

            $output.Count | Should -Be 0
            $definition.ModulePath | Should -Be (Join-Path $root 'modules\Example\Example.psm1')
            $definition.DomFeaturePath | Should -Be (Join-Path $root 'dom\features\example.dom.js')
        }

        It 'normalizes one job definition with DomFeaturePaths without emitting pipeline output' {
            $root = New-TestFoundationJobRegistryRoot
            $definition = @{
                ModulePath = 'modules\Example\Example.psm1'
                CommandName = 'Invoke-ExampleJob'
                DomFeaturePaths = @(
                    'dom\features\example.contract.js'
                    'dom\features\example.actions.js'
                )
            }

            $output = @(Resolve-FoundationJobDefinitionPaths -Definition $definition -RootPath $root)

            $output.Count | Should -Be 0
            $definition.DomFeaturePaths[0] | Should -Be (Join-Path $root 'dom\features\example.contract.js')
            $definition.DomFeaturePaths[1] | Should -Be (Join-Path $root 'dom\features\example.actions.js')
        }

        It 'normalizes a registry as one registry output without leaking job definitions' {
            $root = New-TestFoundationJobRegistryRoot
            $registry = @{
                Jobs = @{
                    ExampleA = @{
                        ModulePath = 'modules\Example\Example.psm1'
                        CommandName = 'Invoke-ExampleJobA'
                        DomFeaturePath = 'dom\features\example.dom.js'
                    }
                    ExampleB = @{
                        ModulePath = 'modules\Example\Example.psm1'
                        CommandName = 'Invoke-ExampleJobB'
                        DomFeaturePaths = @(
                            'dom\features\example.contract.js'
                            'dom\features\example.actions.js'
                        )
                    }
                }
            }

            $output = @(Resolve-FoundationJobRegistryPaths -Registry $registry -RootPath $root)

            $output.Count | Should -Be 1
            ($output[0] -is [hashtable]) | Should -Be $true
            $output[0].Jobs.ExampleA.ModulePath | Should -Be (Join-Path $root 'modules\Example\Example.psm1')
            $output[0].Jobs.ExampleB.DomFeaturePaths[1] | Should -Be (Join-Path $root 'dom\features\example.actions.js')
        }

        It 'returns the default registry path under config directory' {
            $path = Get-FoundationDefaultJobRegistryPath -RootPath 'C:\foundation-root'
            $path | Should -Be (Join-Path (Join-Path 'C:\foundation-root' 'config') 'foundation.jobs.psd1')
        }

        It 'throws when registry Jobs key is missing' {
            { Assert-FoundationJobRegistry -Registry @{} } | Should -Throw
        }

        It 'throws when a job definition is missing a required key' {
            $registry = @{
                Jobs = @{
                    Example = @{
                        ModulePath = 'modules\Example\Example.psm1'
                        CommandName = 'Invoke-ExampleJob'
                    }
                }
            }

            { Assert-FoundationJobRegistry -Registry $registry } | Should -Throw
        }

        It 'throws when DomFeaturePath and DomFeaturePaths are both specified' {
            $registry = @{
                Jobs = @{
                    Example = @{
                        ModulePath = 'modules\Example\Example.psm1'
                        CommandName = 'Invoke-ExampleJob'
                        DomFeaturePath = 'dom\features\example.dom.js'
                        DomFeaturePaths = @('dom\features\example.contract.js')
                    }
                }
            }

            { Assert-FoundationJobRegistry -Registry $registry } | Should -Throw
        }

        It 'throws when DomFeaturePaths is not an array' {
            $registry = @{
                Jobs = @{
                    Example = @{
                        ModulePath = 'modules\Example\Example.psm1'
                        CommandName = 'Invoke-ExampleJob'
                        DomFeaturePaths = 'dom\features\example.dom.js'
                    }
                }
            }

            { Assert-FoundationJobRegistry -Registry $registry } | Should -Throw
        }

        It 'throws when CommandName is invalid' {
            $registry = @{
                Jobs = @{
                    Example = @{
                        ModulePath = 'modules\Example\Example.psm1'
                        CommandName = 'Invoke Example Job'
                        DomFeaturePath = 'dom\features\example.dom.js'
                    }
                }
            }

            { Assert-FoundationJobRegistry -Registry $registry } | Should -Throw
        }

        It 'throws when requested job definition is missing' {
            $registry = @{
                Jobs = @{
                    Example = @{
                        ModulePath = 'modules\Example\Example.psm1'
                        CommandName = 'Invoke-ExampleJob'
                        DomFeaturePath = 'dom\features\example.dom.js'
                    }
                }
            }

            { Get-FoundationJobDefinition -Registry $registry -JobName 'Missing' } | Should -Throw
        }

        It 'does not require files for unused jobs during normal registry import' {
            $root = New-TestFoundationJobRegistryRoot
            $registryPath = Join-Path (Join-Path $root 'config') 'foundation.jobs.psd1'
            Write-TestFoundationJobRegistryFile -Path $registryPath -Content @'
@{
    Jobs = @{
        Example = @{
            ModulePath = 'modules\Example\Example.psm1'
            CommandName = 'Invoke-ExampleJob'
            DomFeaturePath = 'dom\features\example.dom.js'
        }
        Missing = @{
            ModulePath = 'modules\Missing\Missing.psm1'
            CommandName = 'Invoke-MissingJob'
            DomFeaturePath = 'dom\features\missing.dom.js'
        }
    }
}
'@

            $registry = Import-FoundationJobRegistry -Path $registryPath -RootPath $root
            $definition = Get-FoundationJobDefinition -Registry $registry -JobName 'Example'

            { Assert-FoundationJobDefinitionFiles -JobName 'Example' -Definition $definition } | Should -Not -Throw
        }

        It 'throws for missing files only when requested job files are validated' {
            $root = New-TestFoundationJobRegistryRoot
            $registryPath = Join-Path (Join-Path $root 'config') 'foundation.jobs.psd1'
            Write-TestFoundationJobRegistryFile -Path $registryPath -Content @'
@{
    Jobs = @{
        Missing = @{
            ModulePath = 'modules\Missing\Missing.psm1'
            CommandName = 'Invoke-MissingJob'
            DomFeaturePath = 'dom\features\missing.dom.js'
        }
    }
}
'@

            $registry = Import-FoundationJobRegistry -Path $registryPath -RootPath $root
            $definition = Get-FoundationJobDefinition -Registry $registry -JobName 'Missing'

            { Assert-FoundationJobDefinitionFiles -JobName 'Missing' -Definition $definition } | Should -Throw
        }

        It 'throws for missing DomFeaturePaths files when requested job files are validated' {
            $root = New-TestFoundationJobRegistryRoot
            $registryPath = Join-Path (Join-Path $root 'config') 'foundation.jobs.psd1'
            Write-TestFoundationJobRegistryFile -Path $registryPath -Content @'
@{
    Jobs = @{
        Missing = @{
            ModulePath = 'modules\Example\Example.psm1'
            CommandName = 'Invoke-MissingJob'
            DomFeaturePaths = @(
                'dom\features\example.contract.js'
                'dom\features\missing.actions.js'
            )
        }
    }
}
'@

            $registry = Import-FoundationJobRegistry -Path $registryPath -RootPath $root
            $definition = Get-FoundationJobDefinition -Registry $registry -JobName 'Missing'

            { Assert-FoundationJobDefinitionFiles -JobName 'Missing' -Definition $definition } | Should -Throw
        }

        It 'throws for missing files when ValidateAllFiles is requested' {
            $root = Join-Path $TestDrive 'missing-file-root'
            $configDirectory = Join-Path $root 'config'
            New-Item -ItemType Directory -Path $configDirectory -Force | Out-Null
            $registryPath = Join-Path $configDirectory 'foundation.jobs.psd1'
            Write-TestFoundationJobRegistryFile -Path $registryPath -Content @'
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

            { Import-FoundationJobRegistry -Path $registryPath -RootPath $root -ValidateAllFiles } | Should -Throw
        }
    }
}
