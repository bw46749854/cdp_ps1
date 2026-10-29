$ErrorActionPreference = "Stop"

Describe 'LastMonthInstallExtract dependencies' {
    BeforeAll {
        $repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
        . (Join-Path $PSScriptRoot 'TestSupport.ps1')
        Import-Module -Name (Join-Path $repositoryRoot 'modules\LastMonthInstallExtract\LastMonthInstallExtract.psm1') -Force

        function New-TestLastMonthInstallExtractWorkflowDependencies {
            return [pscustomobject]@{
                Input = [pscustomobject]@{
                    GetTargetCsvFiles = { param([string]$TargetDirectory, [string]$OutputCsvFileName, [string]$FailureCsvFileName) @() }
                    ReadAllBytes = { param([string]$Path) [byte[]]@() }
                }
                Logger = [pscustomobject]@{
                    WriteInfo = { param([string]$Message) }
                    WriteWarning = { param([string]$Message) }
                }
                Timing = [pscustomobject]@{
                    TimestampText = { '2026-06-16 12:00:00' }
                }
            }
        }

        function New-TestLastMonthInstallExtractJobDependencies {
            $dependencies = New-TestLastMonthInstallExtractWorkflowDependencies
            $dependencies | Add-Member -MemberType NoteProperty -Name Output -Value ([pscustomobject]@{
                InitializeOutputDirectory = { param([string]$Directory) $Directory }
                ExportInstallationCsv = { param([object[]]$Rows, [string]$Path) $null }
                ExportFailureCsv = { param([object[]]$FailureRows, [string]$Path) $null }
            })
            $dependencies.Logger | Add-Member -MemberType NoteProperty -Name WriteSection -Value { param([string]$Title) }
            $dependencies.Timing | Add-Member -MemberType NoteProperty -Name Now -Value { [datetime]'2026-06-16' }
            return $dependencies
        }
    }

    It 'rejects missing required workflow callbacks' {
        $dependencies = [pscustomobject]@{
            Input = [pscustomobject]@{ GetTargetCsvFiles = { @() } }
            Logger = [pscustomobject]@{ WriteInfo = { param([string]$Message) } }
            Timing = [pscustomobject]@{}
        }

        InModuleScope LastMonthInstallExtract -Parameters @{ Dependencies = $dependencies } {
            { Assert-LastMonthInstallExtractInstallationWorkflowDependencies -Dependencies $Dependencies } |
                Should -Throw "*ReadAllBytes*"
        }
    }

    It 'allows workflow dependencies without Output, Now, or WriteSection ports' {
        $dependencies = New-TestLastMonthInstallExtractWorkflowDependencies
        $context = [pscustomobject]@{}

        $resolved = InModuleScope LastMonthInstallExtract -Parameters @{ Context = $context; Dependencies = $dependencies } {
            Resolve-LastMonthInstallExtractInstallationWorkflowDependencies -Context $Context -Dependencies $Dependencies
        }

        [object]::ReferenceEquals($resolved.Input, $dependencies.Input) | Should -BeTrue
        [object]::ReferenceEquals($resolved.Logger, $dependencies.Logger) | Should -BeTrue
        [object]::ReferenceEquals($resolved.Timing, $dependencies.Timing) | Should -BeTrue
        $resolved.PSObject.Properties['Output'] | Should -Be $null
    }

    It 'rejects job dependencies when Output, Now, or WriteSection ports are missing' {
        $dependencies = New-TestLastMonthInstallExtractWorkflowDependencies

        InModuleScope LastMonthInstallExtract -Parameters @{ Dependencies = $dependencies } {
            { Assert-LastMonthInstallExtractJobDependencies -Dependencies $Dependencies } |
                Should -Throw "*InitializeOutputDirectory*"
        }
    }

    It 'keeps injected job dependencies as the resolved dependencies' {
        $dependencies = New-TestLastMonthInstallExtractJobDependencies
        $context = [pscustomobject]@{}

        $resolved = InModuleScope LastMonthInstallExtract -Parameters @{ Context = $context; Dependencies = $dependencies } {
            Resolve-LastMonthInstallExtractJobDependencies -Context $Context -Dependencies $Dependencies
        }

        [object]::ReferenceEquals($resolved.Input, $dependencies.Input) | Should -BeTrue
        [object]::ReferenceEquals($resolved.Output, $dependencies.Output) | Should -BeTrue
        [object]::ReferenceEquals($resolved.Logger, $dependencies.Logger) | Should -BeTrue
        [object]::ReferenceEquals($resolved.Timing, $dependencies.Timing) | Should -BeTrue
    }

    It 'resolves logger, filesystem output, and timing ports from Context.Services for jobs' {
        $context = New-TestFoundationContext -JobSettings @{}

        $resolved = InModuleScope LastMonthInstallExtract -Parameters @{ Context = $context } {
            Resolve-LastMonthInstallExtractJobDependencies -Context $Context
        }

        [object]::ReferenceEquals($resolved.Logger, $context.Services.Logger) | Should -BeTrue
        [object]::ReferenceEquals($resolved.Timing, $context.Services.Timing) | Should -BeTrue
        $resolved.Output.InitializeOutputDirectory | Should -BeOfType ([scriptblock])
        $resolved.Output.ExportInstallationCsv | Should -BeOfType ([scriptblock])
        $resolved.Output.ExportFailureCsv | Should -BeOfType ([scriptblock])
    }
}
