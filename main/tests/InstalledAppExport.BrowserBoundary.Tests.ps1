$ErrorActionPreference = "Stop"
Describe 'InstalledAppExport Browser service boundary' {
    BeforeAll {
        $repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
        . (Join-Path $PSScriptRoot 'TestSupport.ps1')
        Import-Module -Name (Join-Path $repositoryRoot 'modules\InstalledAppExport\InstalledAppExport.psm1') -Force
    }

    BeforeEach {
        $script:InstalledAppExportBrowser = New-TestBrowserService
        $script:InstalledAppExportFileSystem = New-TestFileSystemService
        $script:InstalledAppExportTiming = New-TestTimingService
        $script:InstalledAppExportContext = [pscustomobject]@{
            Logger = $null
            CommonSettings = [pscustomobject]@{
                DebuggerUrl = 'http://localhost:9222'
                Cdp = [pscustomobject]@{
                    ConnectTimeoutSeconds = 11
                    CommandTimeoutSeconds = 22
                }
            }
            JobSettings = [pscustomobject]@{
                TempDirectory = 'C:\foundation\temp'
                DownloadDirectory = 'C:\foundation\download'
            }
            Services = [pscustomobject]@{
                Browser = $script:InstalledAppExportBrowser
                FileSystem = $script:InstalledAppExportFileSystem
                Timing = $script:InstalledAppExportTiming
            }
        }
    }

    It 'opens the browser by DOM contract and configures downloads through the injected Browser service port' {
        $totalCount = InModuleScope InstalledAppExport -Parameters @{ Context = $script:InstalledAppExportContext } {
            Mock Register-InstalledAppExportDomAdapter { }
            Mock Assert-InstalledAppExportPage { [pscustomobject]@{ ok = $true } }
            Mock Assert-InstalledAppExportList { [pscustomobject]@{ ok = $true } }
            Mock Get-InstalledAppExportListTotalCount { 3 }
            Mock Close-InstalledAppExportDetailPanelSafely { }
            Mock Scroll-InstalledAppExportListToTop { }

            Initialize-InstalledAppExportJob -Context $Context
        }

        $totalCount | Should -Be 3
        Get-TestCallCount -Calls $script:InstalledAppExportBrowser.Calls -Name 'OpenPageMatchingIdentity' | Should -Be 1
        Get-TestCallCount -Calls $script:InstalledAppExportBrowser.Calls -Name 'SetDownloadDirectory' | Should -Be 1

        $openPageCall = @($script:InstalledAppExportBrowser.Calls | Where-Object { $_.Name -eq 'OpenPageMatchingIdentity' })[0]
        $openPageCall.Arguments.DebuggerUrl | Should -Be 'http://localhost:9222'
        $openPageCall.Arguments.ConnectTimeoutSeconds | Should -Be 11
        $openPageCall.Arguments.CommandTimeoutSeconds | Should -Be 22

        $downloadCall = @($script:InstalledAppExportBrowser.Calls | Where-Object { $_.Name -eq 'SetDownloadDirectory' })[0]
        $downloadCall.Arguments.Directory | Should -Be 'C:\foundation\temp'
    }

    It 'creates a module-bound page identity matcher that can be invoked from outside the InstalledAppExport module scope' {
        $probe = InModuleScope InstalledAppExport -Parameters @{ Context = $script:InstalledAppExportContext } {
            Mock Test-InstalledAppExportPageIdentity {
                param($Context)
                return [pscustomobject]@{ Matched = $true; Reason = 'InstalledAppExport module-bound probe'; Result = $Context }
            }

            New-InstalledAppExportPageIdentityMatcher -Context $Context
        }

        $result = & $probe ([pscustomobject]@{ title = 'ignored' }) ([pscustomobject]@{})

        $result.Matched | Should -BeTrue
        $result.Reason | Should -Be 'InstalledAppExport module-bound probe'
    }

    It 'matches page identity through a lightweight DOM operation without readiness assertions' {
        $result = InModuleScope InstalledAppExport -Parameters @{ Context = $script:InstalledAppExportContext } {
            Mock Register-InstalledAppExportDomAdapter { }
            Mock Invoke-InstalledAppExportDomOperation {
                param([string]$Operation, [int]$TimeoutSeconds)
                $Operation | Should -Be 'DetectPageIdentity'
                $TimeoutSeconds | Should -Be 2
                return [pscustomobject]@{ ok = $true; fatalCount = 0 }
            }
            Mock Assert-InstalledAppExportPage { throw 'readiness assertion must not run during identity matching' }
            Mock Assert-InstalledAppExportList { throw 'list assertion must not run during identity matching' }

            Test-InstalledAppExportPageIdentity -Context $Context
        }

        $result.Matched | Should -BeTrue
    }

    It 'initializes output directories through the injected FileSystem service before opening the page' {
        InModuleScope InstalledAppExport -Parameters @{ Context = $script:InstalledAppExportContext } {
            Mock Register-InstalledAppExportDomAdapter { }
            Mock Assert-InstalledAppExportPage { [pscustomobject]@{ ok = $true } }
            Mock Assert-InstalledAppExportList { [pscustomobject]@{ ok = $true } }
            Mock Get-InstalledAppExportListTotalCount { 3 }
            Mock Close-InstalledAppExportDetailPanelSafely { }
            Mock Scroll-InstalledAppExportListToTop { }

            Initialize-InstalledAppExportJob -Context $Context | Out-Null
        }

        Get-TestCallCount -Calls $script:InstalledAppExportFileSystem.Calls -Name 'InitializeOutputDirectory' | Should -Be 2
        Get-TestCallCount -Calls $script:InstalledAppExportFileSystem.Calls -Name 'ClearDirectory' | Should -Be 1
        Get-TestCallCount -Calls $script:InstalledAppExportBrowser.Calls -Name 'OpenPageMatchingIdentity' | Should -Be 1

        $firstDirectoryCall = @($script:InstalledAppExportFileSystem.Calls | Where-Object { $_.Name -eq 'InitializeOutputDirectory' })[0]
        $firstDirectoryCall.Arguments.Directory | Should -Be 'C:\foundation\temp'
        $firstDirectoryCall.Arguments.Purpose | Should -Be '一時ダウンロード'
    }

    It 'stops with a DOM contract error when the initial total count is unavailable' {
        InModuleScope InstalledAppExport -Parameters @{ Context = $script:InstalledAppExportContext } {
            Mock Register-InstalledAppExportDomAdapter { }
            Mock Assert-InstalledAppExportPage { [pscustomobject]@{ ok = $true } }
            Mock Assert-InstalledAppExportList { [pscustomobject]@{ ok = $true } }
            Mock Get-InstalledAppExportListTotalCount { $null }
            Mock Close-InstalledAppExportDetailPanelSafely { }
            Mock Scroll-InstalledAppExportListToTop { }

            { Initialize-InstalledAppExportJob -Context $Context } | Should -Throw '*一覧件数*'
            Should -Invoke -CommandName Register-InstalledAppExportDomAdapter -Times 1 -Exactly
            Should -Invoke -CommandName Assert-InstalledAppExportPage -Times 1 -Exactly
            Should -Invoke -CommandName Assert-InstalledAppExportList -Times 1 -Exactly
        }

        Get-TestCallCount -Calls $script:InstalledAppExportBrowser.Calls -Name 'OpenPageMatchingIdentity' | Should -Be 1
    }
}
