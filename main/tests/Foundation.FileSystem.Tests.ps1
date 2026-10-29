$ErrorActionPreference = "Stop"
$modulePath = Join-Path $PSScriptRoot '..\modules\Foundation\Foundation.psm1'
Import-Module -Name $modulePath -Force

InModuleScope Foundation {
    Describe 'Foundation filesystem safety' {
        It 'allows paths under the configured directory' {
            $dir = Join-Path $TestDrive 'safe'
            $path = Join-Path $dir 'child.txt'
            Test-PathUnderDirectory -Path $path -Directory $dir | Should -BeTrue
        }

        It 'rejects paths outside the configured directory' {
            $dir = Join-Path $TestDrive 'safe'
            $outside = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '.txt')
            Test-PathUnderDirectory -Path $outside -Directory $dir | Should -BeFalse
        }

        It 'removes existing files only under the allowed directory' {
            $dir = Join-Path $TestDrive 'safe'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            $path = Join-Path $dir 'old.csv'
            Set-Content -LiteralPath $path -Value 'old' -Encoding UTF8
            Remove-FileIfExistsSafely -Path $path -AllowedDirectory $dir | Should -BeTrue
            Test-Path -LiteralPath $path | Should -BeFalse
        }

        It 'does not remove files outside the allowed directory' {
            $dir = Join-Path $TestDrive 'safe'
            $outsideDir = Join-Path $TestDrive 'outside'
            New-Item -ItemType Directory -Path $outsideDir -Force | Out-Null
            $outside = Join-Path $outsideDir 'old.csv'
            Set-Content -LiteralPath $outside -Value 'old' -Encoding UTF8
            { Remove-FileIfExistsSafely -Path $outside -AllowedDirectory $dir } | Should -Throw
        }
    }
}
