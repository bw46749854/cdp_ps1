$ErrorActionPreference = "Stop"

Describe 'Test support ports' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestSupport.ps1')
    }


    It 'creates an empty call list as an ArrayList object instead of null' {
        $calls = New-TestCallList

        ($null -eq $calls) | Should -BeFalse
        $calls.GetType().FullName | Should -Be 'System.Collections.ArrayList'
        $calls.Count | Should -Be 0
    }

    It 'records logger calls without writing to the real console or log file' {
        $logger = New-TestLoggerPort

        $logger.WriteInfo.Invoke('started')
        $logger.WriteWarning.Invoke('careful')

        Get-TestCallCount -Calls $logger.Calls -Name 'WriteInfo' | Should -Be 1
        Get-TestCallCount -Calls $logger.Calls -Name 'WriteWarning' | Should -Be 1
        $logger.Records[0].Message | Should -Be 'started'
        $logger.Records[1].Level | Should -Be 'Warning'
    }

    It 'records filesystem boundary calls and returns configured results' {
        $fileSystem = New-TestFileSystemService -PathUnderDirectoryResult $false -RemoveFileIfExistsResult $true

        $fileSystem.InitializeOutputDirectory.Invoke('out', '出力') | Should -Be 'out'
        $fileSystem.TestPathUnderDirectory.Invoke('out\a.csv', 'out') | Should -BeFalse
        $fileSystem.RemoveFileIfExists.Invoke('out\a.csv', 'out') | Should -BeTrue

        Get-TestCallCount -Calls $fileSystem.Calls -Name 'InitializeOutputDirectory' | Should -Be 1
        Get-TestCallCount -Calls $fileSystem.Calls -Name 'TestPathUnderDirectory' | Should -Be 1
        Get-TestCallCount -Calls $fileSystem.Calls -Name 'RemoveFileIfExists' | Should -Be 1
    }

    It 'can perform real directory initialization and file deletion when explicitly requested' {
        $fileSystem = New-TestFileSystemService -CreateDirectories $true -RemoveFiles $true
        $outputDirectory = Join-Path $TestDrive 'out'
        $stalePath = Join-Path $outputDirectory 'stale.csv'

        $fileSystem.InitializeOutputDirectory.Invoke($outputDirectory, '出力') | Should -Be $outputDirectory
        Set-Content -LiteralPath $stalePath -Value 'old' -Encoding UTF8

        $fileSystem.RemoveFileIfExists.Invoke($stalePath, $outputDirectory) | Should -BeTrue
        Test-Path -LiteralPath $stalePath | Should -BeFalse
    }

    It 'records browser calls and returns the configured page object' {
        $page = [pscustomobject]@{ CdpSession = [pscustomobject]@{ Id = 'session-1' } }
        $browser = New-TestBrowserService -Page $page

        $opened = $browser.OpenPage.Invoke('http://localhost:9222', 3, 9)
        $openedByContract = $browser.OpenPageMatchingIdentity.Invoke('http://localhost:9222', 3, 9, { $true })
        $browser.SetDownloadDirectory.Invoke('downloads')

        $opened | Should -Be $page
        $openedByContract | Should -Be $page
        Get-TestCallCount -Calls $browser.Calls -Name 'OpenPage' | Should -Be 1
        Get-TestCallCount -Calls $browser.Calls -Name 'OpenPageMatchingIdentity' | Should -Be 1
        Get-TestCallCount -Calls $browser.Calls -Name 'SetDownloadDirectory' | Should -Be 1
        $browser.Calls[0].Arguments.CommandTimeoutSeconds | Should -Be 9
        $browser.Calls[1].Arguments.PageIdentityMatcher | Should -BeOfType ([scriptblock])
    }

    It 'creates an Foundation-like context with injectable service ports' {
        $browser = New-TestBrowserService
        $context = New-TestFoundationContext -JobName 'InstalledAppExport' -BrowserService $browser

        $context.JobName | Should -Be 'InstalledAppExport'
        $context.Services.Browser | Should -Be $browser
        $context.Services.Logger.WriteInfo.Invoke('context-ready')
        Get-TestCallCount -Calls $context.Services.Logger.Calls -Name 'WriteInfo' | Should -Be 1
    }
}
