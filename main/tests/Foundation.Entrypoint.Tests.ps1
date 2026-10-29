$ErrorActionPreference = "Stop"
$repositoryRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$modulePath = Join-Path $repositoryRoot 'modules\Foundation\Foundation.psm1'
Import-Module -Name $modulePath -Force

InModuleScope Foundation {
    Describe 'Foundation registry-driven entrypoint' {
        BeforeAll {
            $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
            function New-TestRegistryDrivenRoot {
                param([Parameter(Mandatory)][string]$CommandName)

                $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
                $configDirectory = Join-Path $root 'config'
                $moduleDirectory = Join-Path $root 'modules\Example'
                $domDirectory = Join-Path $root 'dom\features'

                New-Item -ItemType Directory -Path $configDirectory -Force | Out-Null
                New-Item -ItemType Directory -Path $moduleDirectory -Force | Out-Null
                New-Item -ItemType Directory -Path $domDirectory -Force | Out-Null

                $configPath = Join-Path $configDirectory 'foundation.config.psd1'
                Set-Content -LiteralPath $configPath -Encoding UTF8 -Value @'
@{
    Common = @{
        Logging = @{
            Level = 'Info'
            Console = $false
            File = $false
            Directory = ''
        }
    }
    Jobs = @{
        Example = @{}
    }
}
'@

                $registryPath = Join-Path $configDirectory 'foundation.jobs.psd1'
                Set-Content -LiteralPath $registryPath -Encoding UTF8 -Value @"
@{
    Jobs = @{
        Example = @{
            ModulePath = 'modules\Example\Example.psm1'
            CommandName = '$CommandName'
            DomFeaturePath = 'dom\features\example.dom.js'
        }
    }
}
"@

                $capturePath = Join-Path $root 'context-capture.txt'
                $escapedCapturePath = $capturePath -replace "'", "''"
                $modulePath = Join-Path $moduleDirectory 'Example.psm1'
                Set-Content -LiteralPath $modulePath -Encoding UTF8 -Value @"
function $CommandName {
    param([Parameter(Mandatory)]`$Context)
    Set-Content -LiteralPath '$escapedCapturePath' -Encoding UTF8 -Value @(
        [string]`$Context.ConfigPath,
        [string]`$Context.JobRegistryPath
    )
}
Export-ModuleMember -Function $CommandName
"@

                Set-Content -LiteralPath (Join-Path $domDirectory 'example.dom.js') -Encoding UTF8 -Value '// example dom'

                return [pscustomobject]@{
                    Root = $root
                    ConfigPath = $configPath
                    RegistryPath = $registryPath
                    ModulePath = $modulePath
                    CapturePath = $capturePath
                }
            }
        }

        It 'imports job module from registry ModulePath and invokes registry CommandName' {
            $fixture = New-TestRegistryDrivenRoot -CommandName 'Invoke-ExampleJobA'

            { Invoke-FoundationEntrypoint `
                -RootPath $fixture.Root `
                -ConfigPath $fixture.ConfigPath `
                -JobName 'Example' `
                -JobRegistryPath $fixture.RegistryPath } | Should -Not -Throw
        }


        It 'passes resolved ConfigPath and JobRegistryPath into the run context' {
            $fixture = New-TestRegistryDrivenRoot -CommandName 'Invoke-ExampleContextCaptureJob'

            Invoke-FoundationEntrypoint `
                -RootPath $fixture.Root `
                -ConfigPath $fixture.ConfigPath `
                -JobName 'Example' `
                -JobRegistryPath $fixture.RegistryPath | Out-Null

            $lines = @(Get-Content -LiteralPath $fixture.CapturePath)
            $lines[0] | Should -Be (Resolve-Path -LiteralPath $fixture.ConfigPath).Path
            $lines[1] | Should -Be (Resolve-Path -LiteralPath $fixture.RegistryPath).Path
        }

        It 'throws when registry CommandName is not found after module import' {
            $fixture = New-TestRegistryDrivenRoot -CommandName 'Invoke-MissingRegistryCommand'
            Set-Content -LiteralPath $fixture.ModulePath -Encoding UTF8 -Value @'
function Invoke-DifferentRegistryCommand {
    param([Parameter(Mandatory)]$Context)
}
Export-ModuleMember -Function Invoke-DifferentRegistryCommand
'@

            { Invoke-FoundationEntrypoint `
                -RootPath $fixture.Root `
                -ConfigPath $fixture.ConfigPath `
                -JobName 'Example' `
                -JobRegistryPath $fixture.RegistryPath } | Should -Throw
        }
    }
}

Describe 'Registry-driven entry script source' {
    BeforeAll {
        $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
        $script:RunJobPath = Join-Path $script:RepositoryRoot 'run_job.ps1'
    }

    It 'provides a generic run_job.ps1 accepting JobName and JobRegistryPath' {
        $text = Get-Content -LiteralPath $script:RunJobPath -Raw
        $text | Should -Match '\[Parameter\(Mandatory\)\]\[string\]\$JobName'
        $text | Should -Match '\[string\]\$JobRegistryPath'
        $text | Should -Not -Match 'Invoke-InstalledAppExportJob|Invoke-ScanTargetSyncJob'
        $text | Should -Not -Match 'modules\\InstalledAppExport|modules\\ScanTargetSync'
    }

}
