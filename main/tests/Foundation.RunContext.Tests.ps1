$ErrorActionPreference = "Stop"
$modulePath = Join-Path $PSScriptRoot '..\modules\Foundation\Foundation.psm1'
Import-Module -Name $modulePath -Force

InModuleScope Foundation {
    Describe 'Foundation run context services' {
        It 'adds technical service ports to a new run context' {
            $config = @{
                Common = @{
                    Logging = @{
                        Console = $false
                        File = $false
                    }
                }
                Jobs = @{
                    TestJob = @{
                        OutputDirectory = 'out'
                    }
                }
            }

            $context = New-FoundationRunContext -RootPath $TestDrive -Config $config -JobName 'TestJob'

            $context.Services | Should -Not -BeNullOrEmpty
            $context.Services.Logger | Should -Not -BeNullOrEmpty
            $context.Services.FileSystem | Should -Not -BeNullOrEmpty
            $context.Services.Browser | Should -Not -BeNullOrEmpty
            $context.Services.Workflow | Should -Not -BeNullOrEmpty
            $context.Services.Timing | Should -Not -BeNullOrEmpty
            ($context.Services.Logger.WriteInfo -is [scriptblock]) | Should -BeTrue
            ($context.Services.Logger.WriteWarning -is [scriptblock]) | Should -BeTrue
            ($context.Services.FileSystem.InitializeOutputDirectory -is [scriptblock]) | Should -BeTrue
            ($context.Services.FileSystem.ClearDirectory -is [scriptblock]) | Should -BeTrue
            ($context.Services.FileSystem.AssertSafeDirectory -is [scriptblock]) | Should -BeTrue
            ($context.Services.FileSystem.TestPathUnderDirectory -is [scriptblock]) | Should -BeTrue
            ($context.Services.FileSystem.RemoveFileIfExists -is [scriptblock]) | Should -BeTrue
            ($context.Services.Browser.OpenPage -is [scriptblock]) | Should -BeTrue
            ($context.Services.Browser.OpenPageMatchingIdentity -is [scriptblock]) | Should -BeTrue
            ($context.Services.Browser.SetDownloadDirectory -is [scriptblock]) | Should -BeTrue
            ($context.Services.Workflow.InvokeScrollableList -is [scriptblock]) | Should -BeTrue
            ($context.Services.Timing.Now -is [scriptblock]) | Should -BeTrue
            ($context.Services.Timing.TimestampText -is [scriptblock]) | Should -BeTrue
            ($context.Services.Timing.SleepMilliseconds -is [scriptblock]) | Should -BeTrue
        }

        It 'adds Browser service ports without invoking CDP' {
            $config = @{
                Common = @{
                    Logging = @{
                        Console = $false
                        File = $false
                    }
                }
                Jobs = @{
                    TestJob = @{
                        OutputDirectory = 'out'
                    }
                }
            }

            $context = New-FoundationRunContext -RootPath $TestDrive -Config $config -JobName 'TestJob'

            $context.Services.Browser | Should -Not -BeNullOrEmpty
            ($context.Services.Browser.OpenPage -is [scriptblock]) | Should -BeTrue
            ($context.Services.Browser.OpenPageMatchingIdentity -is [scriptblock]) | Should -BeTrue
            ($context.Services.Browser.SetDownloadDirectory -is [scriptblock]) | Should -BeTrue
        }

        It 'invokes FileSystem service ports against a safe test directory' {
            $config = @{
                Common = @{
                    Logging = @{
                        Console = $false
                        File = $false
                    }
                }
                Jobs = @{
                    TestJob = @{
                        OutputDirectory = 'out'
                    }
                }
            }

            $context = New-FoundationRunContext -RootPath $TestDrive -Config $config -JobName 'TestJob'
            $directory = Join-Path $TestDrive 'filesystem-service-output'
            $file = Join-Path $directory 'temporary.txt'

            $resolvedDirectory = @($context.Services.FileSystem.InitializeOutputDirectory.Invoke($directory, 'テスト出力'))[0]
            Set-Content -LiteralPath $file -Value 'temporary' -Encoding UTF8

            $context.Services.FileSystem.TestPathUnderDirectory.Invoke($file, $directory) | Should -BeTrue
            $context.Services.FileSystem.RemoveFileIfExists.Invoke($file, $directory) | Should -BeTrue
            Test-Path -LiteralPath $file | Should -BeFalse

            Set-Content -LiteralPath $file -Value 'temporary' -Encoding UTF8
            { $context.Services.FileSystem.ClearDirectory.Invoke($directory, 'テスト作業') } | Should -Not -Throw
            Test-Path -LiteralPath $resolvedDirectory | Should -BeTrue
            Test-Path -LiteralPath $file | Should -BeFalse
        }


        It 'stores ConfigPath and JobRegistryPath in a new run context' {
            $config = @{
                Common = @{
                    Logging = @{
                        Console = $false
                        File = $false
                    }
                }
                Jobs = @{
                    TestJob = @{
                        OutputDirectory = 'out'
                    }
                }
            }

            $context = New-FoundationRunContext `
                -RootPath $TestDrive `
                -Config $config `
                -JobName 'TestJob' `
                -ConfigPath 'C:\custom\foundation.config.psd1' `
                -JobRegistryPath 'C:\custom\foundation.jobs.psd1'

            $context.ConfigPath | Should -Be 'C:\custom\foundation.config.psd1'
            $context.JobRegistryPath | Should -Be 'C:\custom\foundation.jobs.psd1'
        }

        It 'invokes service ports without relying on script-scope logger defaults' {
            $config = @{
                Common = @{
                    Logging = @{
                        Console = $false
                        File = $false
                    }
                }
                Jobs = @{
                    TestJob = @{
                        OutputDirectory = 'out'
                    }
                }
            }

            $context = New-FoundationRunContext -RootPath $TestDrive -Config $config -JobName 'TestJob'

            { $context.Services.Logger.WriteInfo.Invoke('info message') } | Should -Not -Throw
            { $context.Services.Logger.WriteWarning.Invoke('warning message') } | Should -Not -Throw
        }
    }
}
