$ErrorActionPreference = "Stop"

Describe 'AI-maintainable architecture guard' {
    BeforeAll {
        function Resolve-ArchitectureRepositoryRoot {
            $candidatePaths = @(
                (Join-Path $PSScriptRoot '..'),
                (Get-Location).Path
            )

            foreach ($candidatePath in $candidatePaths) {
                try {
                    $resolved = Resolve-Path -LiteralPath $candidatePath -ErrorAction Stop
                    if (Test-Path -LiteralPath (Join-Path $resolved.Path 'modules')) {
                        return $resolved.Path
                    }
                }
                catch {
                    # continue probing likely roots
                }
            }

            throw 'Repository root could not be resolved from test context.'
        }

        function Join-ArchitecturePath {
            param(
                [Parameter(Mandatory)][string]$RootPath,
                [Parameter(Mandatory)][string]$RelativePath
            )

            return (Join-Path $RootPath $RelativePath)
        }

        function Get-ArchitectureRelativePath {
            param(
                [Parameter(Mandatory)][string]$RootPath,
                [Parameter(Mandatory)][string]$FullPath
            )

            $root = (Resolve-Path -LiteralPath $RootPath).Path.TrimEnd([char[]]@('\', '/'))
            $path = (Resolve-Path -LiteralPath $FullPath).Path

            if ($path.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $path.Substring($root.Length).TrimStart([char[]]@('\', '/'))
            }

            return $path
        }

        function Get-ArchitectureFiles {
            param(
                [Parameter(Mandatory)][string]$RootPath,
                [Parameter(Mandatory)][string[]]$RelativePaths,
                [string[]]$Include = @('*.ps1', '*.psm1', '*.psd1')
            )

            $files = New-Object System.Collections.Generic.List[object]

            foreach ($relativePath in $RelativePaths) {
                $path = Join-ArchitecturePath -RootPath $RootPath -RelativePath $relativePath
                if (-not (Test-Path -LiteralPath $path)) {
                    continue
                }

                $item = Get-Item -LiteralPath $path
                if ($item.PSIsContainer) {
                    foreach ($pattern in $Include) {
                        $found = @(Get-ChildItem -LiteralPath $item.FullName -Recurse -File -Filter $pattern)
                        foreach ($file in $found) {
                            [void]$files.Add($file)
                        }
                    }
                }
                else {
                    [void]$files.Add($item)
                }
            }

            return @($files | Sort-Object -Property FullName -Unique)
        }

        function Find-ArchitecturePatternViolations {
            param(
                [Parameter(Mandatory)][string]$RootPath,
                [Parameter(Mandatory)][object[]]$Files,
                [Parameter(Mandatory)][object[]]$Patterns,
                [scriptblock]$IsAllowed = { param($RelativePath, $PatternName, $Line) return $false }
            )

            $violations = New-Object System.Collections.Generic.List[string]

            foreach ($file in $Files) {
                $relativePath = Get-ArchitectureRelativePath -RootPath $RootPath -FullPath $file.FullName
                $lines = @(Get-Content -LiteralPath $file.FullName)

                for ($i = 0; $i -lt $lines.Count; $i++) {
                    $line = [string]$lines[$i]

                    foreach ($pattern in $Patterns) {
                        if ($line -match $pattern.Regex) {
                            $allowed = & $IsAllowed $relativePath $pattern.Name $line
                            if (-not $allowed) {
                                [void]$violations.Add(('{0}:{1}: {2}: {3}' -f $relativePath, ($i + 1), $pattern.Name, $line.Trim()))
                            }
                        }
                    }
                }
            }

            return @($violations)
        }

        function Assert-NoArchitectureViolations {
            param(
                [Parameter(Mandatory)][string]$Message,
                [AllowNull()][AllowEmptyCollection()][string[]]$Violations = @()
            )

            $safeViolations = @()
            if ($null -ne $Violations) {
                $safeViolations = @($Violations)
            }

            if ($safeViolations.Count -gt 0) {
                throw ($Message + "`n" + ($safeViolations -join "`n"))
            }
        }

        function New-ArchitecturePattern {
            param(
                [Parameter(Mandatory)][string]$Name,
                [Parameter(Mandatory)][string]$Regex
            )

            return [pscustomobject]@{
                Name = $Name
                Regex = $Regex
            }
        }

        $script:ArchitectureRepositoryRoot = Resolve-ArchitectureRepositoryRoot
        $script:ConcreteBrowserAndCdpPatterns = @(
            (New-ArchitecturePattern -Name 'HTTP client' -Regex '(?<![A-Za-z0-9_])Invoke-WebRequest(?![A-Za-z0-9_])'),
            (New-ArchitecturePattern -Name 'ClientWebSocket' -Regex 'ClientWebSocket|System\.Net\.WebSockets'),
            (New-ArchitecturePattern -Name 'raw CDP command helper' -Regex '(?<![A-Za-z0-9_])(Send-CDPCommand|Receive-CDPMessage|Invoke-CDPJS|Wait-CDPJS|Open-CDPConnection|Close-CDPConnection|Set-CDPDownloadDirectory)(?![A-Za-z0-9_])')
        )
        $script:ConcreteIoPatterns = @(
            (New-ArchitecturePattern -Name 'direct file or console primitive' -Regex '(?<![A-Za-z0-9_])(Import-Csv|Export-Csv|Add-Content|Set-Content|Out-File|Get-ChildItem|Remove-Item|New-Item|Move-Item|Copy-Item|Write-Host|Write-Warning)(?![A-Za-z0-9_])'),
            (New-ArchitecturePattern -Name 'direct time or sleep primitive' -Regex '(?<![A-Za-z0-9_])(Get-Date|Start-Sleep)(?![A-Za-z0-9_])')
        )
        $script:DomHelperPatterns = @(
            (New-ArchitecturePattern -Name 'raw Foundation DOM helper' -Regex '(?<![A-Za-z0-9_])(Invoke-FoundationDomHelperMethod|Wait-FoundationDomHelperMethod|Wait-FoundationDomHelperMethodResult|Assert-FoundationDomHelperContract)(?![A-Za-z0-9_])')
        )
    }

    Context 'architecture documentation contract' {
        It 'documents the AI-maintainable SRP and DIP boundary policy' {
            $architecturePath = Join-ArchitecturePath -RootPath $script:ArchitectureRepositoryRoot -RelativePath 'ARCHITECTURE.md'
            Test-Path -LiteralPath $architecturePath | Should -Be $true

            $text = Get-Content -LiteralPath $architecturePath -Raw
            $text | Should -Match 'AI'
            $text | Should -Match '保守'
            $text | Should -Match 'SRP'
            $text | Should -Match 'DIP'
            $text | Should -Match 'Policy'
            $text | Should -Match 'Orchestration'
            $text | Should -Match 'Adapter'
            $text | Should -Match 'Concrete driver'
        }

        It 'keeps repository formatting policy explicit for PowerShell 5.1 maintenance' {
            $editorConfigPath = Join-ArchitecturePath -RootPath $script:ArchitectureRepositoryRoot -RelativePath '.editorconfig'
            Test-Path -LiteralPath $editorConfigPath | Should -Be $true

            $text = Get-Content -LiteralPath $editorConfigPath -Raw
            $text | Should -Match 'charset\s*=\s*utf-8-bom'
            $text | Should -Match 'end_of_line\s*=\s*lf'
            $text | Should -Match 'indent_size\s*=\s*4'
        }

    }

    Context 'DIP boundary guards' {
        It 'keeps feature workflow files free from concrete browser, CDP, filesystem, console, time, and sleep primitives' {
            $workflowFiles = Get-ArchitectureFiles `
                -RootPath $script:ArchitectureRepositoryRoot `
                -RelativePaths @(
                    'modules/InstalledAppExport/internal/Workflow.ps1',
                    'modules/InstalledAppExport/internal/Runner.ps1',
                    'modules/DeviceListExport/internal/Workflow.ps1',
                    'modules/DeviceListExport/internal/Runner.ps1',
                    'modules/ScanTargetSync/internal/Runner.ps1',
                    'modules/ScanTargetSync/internal/Workflow.ps1',
                    'modules/ScanTargetSync/internal/Workflow.Display.ps1',
                    'modules/ScanTargetSync/internal/Workflow.State.ps1',
                    'modules/ScanTargetSync/internal/Workflow.Export.ps1',
                    'modules/ScanTargetSync/internal/Workflow.Fatal.ps1',
                    'modules/ScanTargetSync/internal/Workflow.CsvPlan.ps1',
                    'modules/ScanTargetSync/internal/Workflow.EndpointSync.ps1',
                    'modules/ScanTargetSync/internal/Workflow.Orchestration.ps1',
                    'modules/ScanTargetSync/internal/Workflow.Page.ps1',
                    'modules/ScanTargetSync/internal/Workflow.Result.ps1',
                    'modules/ScanTargetSync/internal/Workflow.UiScan.ps1',
                    'modules/ScanTargetSync/internal/Workflow.UiScanState.ps1'
                )

            $patterns = @($script:ConcreteBrowserAndCdpPatterns + $script:ConcreteIoPatterns)
            $violations = Find-ArchitecturePatternViolations `
                -RootPath $script:ArchitectureRepositoryRoot `
                -Files $workflowFiles `
                -Patterns $patterns

            Assert-NoArchitectureViolations `
                -Message 'Workflow files must stay orchestration-only and use dependency ports instead of concrete infrastructure.' `
                -Violations $violations
        }

        It 'keeps feature modules from depending on concrete Chrome/CDP transport primitives' {
            $featureFiles = Get-ArchitectureFiles `
                -RootPath $script:ArchitectureRepositoryRoot `
                -RelativePaths @(
                    'modules/InstalledAppExport',
                    'modules/ScanTargetSync',
                    'modules/DeviceListExport'
                )

            $violations = Find-ArchitecturePatternViolations `
                -RootPath $script:ArchitectureRepositoryRoot `
                -Files $featureFiles `
                -Patterns $script:ConcreteBrowserAndCdpPatterns

            Assert-NoArchitectureViolations `
                -Message 'Feature modules must depend on Foundation services and DOM ports, not concrete Chrome/CDP transport.' `
                -Violations $violations
        }

        It 'keeps raw Foundation DOM helper calls inside feature DOM operation adapters' {
            $featureFiles = Get-ArchitectureFiles `
                -RootPath $script:ArchitectureRepositoryRoot `
                -RelativePaths @(
                    'modules/InstalledAppExport',
                    'modules/ScanTargetSync',
                    'modules/DeviceListExport'
                )

            $violations = Find-ArchitecturePatternViolations `
                -RootPath $script:ArchitectureRepositoryRoot `
                -Files $featureFiles `
                -Patterns $script:DomHelperPatterns `
                -IsAllowed {
                    param($RelativePath, $PatternName, $Line)
                    return ($RelativePath -like '*\DomOperations.ps1' -or $RelativePath -like '*/DomOperations.ps1')
                }

            Assert-NoArchitectureViolations `
                -Message 'Feature code should call DOM ports; raw Foundation DOM helper calls belong in DomOperations.ps1 only.' `
                -Violations $violations
        }

        It 'keeps InstalledAppExport RowAction behind DomAdapter business-named operations' {
            $rowActionFiles = Get-ArchitectureFiles `
                -RootPath $script:ArchitectureRepositoryRoot `
                -RelativePaths @('modules/InstalledAppExport/internal/RowAction.ps1')

            $installedAppExportDomOperationPatterns = @(
                (New-ArchitecturePattern -Name 'direct InstalledAppExport DOM operation wrapper' -Regex '(?<![A-Za-z0-9_])(Invoke-InstalledAppExportDomOperation|Wait-InstalledAppExportDomOperation|Wait-InstalledAppExportDomOperationResult|Assert-InstalledAppExportDomOperationContract)(?![A-Za-z0-9_])')
            )

            $violations = Find-ArchitecturePatternViolations `
                -RootPath $script:ArchitectureRepositoryRoot `
                -Files $rowActionFiles `
                -Patterns $installedAppExportDomOperationPatterns

            Assert-NoArchitectureViolations `
                -Message 'InstalledAppExport RowAction should use DomAdapter business-named operations instead of calling DomOperations wrappers directly.' `
                -Violations $violations
        }

        It 'keeps concrete Chrome transport primitives isolated to Foundation internals' {
            $moduleFiles = Get-ArchitectureFiles `
                -RootPath $script:ArchitectureRepositoryRoot `
                -RelativePaths @('modules')

            $transportPatterns = @(
                (New-ArchitecturePattern -Name 'HTTP client' -Regex '(?<![A-Za-z0-9_])Invoke-WebRequest(?![A-Za-z0-9_])'),
                (New-ArchitecturePattern -Name 'ClientWebSocket' -Regex 'ClientWebSocket|System\.Net\.WebSockets')
            )

            $violations = Find-ArchitecturePatternViolations `
                -RootPath $script:ArchitectureRepositoryRoot `
                -Files $moduleFiles `
                -Patterns $transportPatterns `
                -IsAllowed {
                    param($RelativePath, $PatternName, $Line)
                    return ($RelativePath -like 'modules\Foundation\internal\*' -or $RelativePath -like 'modules/Foundation/internal/*')
                }

            Assert-NoArchitectureViolations `
                -Message 'Concrete Chrome transport primitives must remain inside modules/Foundation/internal.' `
                -Violations $violations
        }
    }

    Context 'SRP policy guards' {
        It 'keeps ScanTargetSync policy files free from browser, CDP, DOM helper, direct I/O, and direct time dependencies' {
            $policyFiles = Get-ArchitectureFiles `
                -RootPath $script:ArchitectureRepositoryRoot `
                -RelativePaths @(
                    'modules/ScanTargetSync/internal/CsvInput.ps1',
                    'modules/ScanTargetSync/internal/Rules.ps1',
                    'modules/ScanTargetSync/internal/Reconciliation.ps1'
                )

            $patterns = @($script:ConcreteBrowserAndCdpPatterns + $script:DomHelperPatterns + $script:ConcreteIoPatterns)
            $violations = Find-ArchitecturePatternViolations `
                -RootPath $script:ArchitectureRepositoryRoot `
                -Files $policyFiles `
                -Patterns $patterns

            Assert-NoArchitectureViolations `
                -Message 'ScanTargetSync policy files must remain browser/CDP/DOM/I/O/time-independent.' `
                -Violations $violations
        }
    }

    Context 'DOM helper missing behavior policy guards' {
        It 'documents the agreed PowerShell 5.1 SRP/DIP non-application boundaries' {
            $architecturePath = Join-ArchitecturePath -RootPath $script:ArchitectureRepositoryRoot -RelativePath 'ARCHITECTURE.md'
            $text = Get-Content -LiteralPath $architecturePath -Raw

            $text | Should -Match 'interface-first'
            $text | Should -Match 'IoC container'
            $text | Should -Match 'service locator'
            $text | Should -Match 'RowAction'
            $text | Should -Match 'MissingHelperBehavior'
            $text | Should -Match 'ReturnContractFailure'
            $text | Should -Match 'MissingValue = @\(\)'
        }
        It 'does not allow ScanTargetSync row scanning to hide missing helpers as an empty array' {
            $domOperationsPath = Join-ArchitecturePath -RootPath $script:ArchitectureRepositoryRoot -RelativePath 'modules/ScanTargetSync/internal/DomOperations.ps1'
            $text = Get-Content -LiteralPath $domOperationsPath -Raw

            $text | Should -Not -Match 'FindDeviceRowsInfo\s*=\s*@\{[^\}]*MissingValue\s*=\s*@\('
        }

        It 'keeps DeviceListExport Await ownership in operation metadata instead of adapter call sites' {
            $domAdapterPath = Join-ArchitecturePath -RootPath $script:ArchitectureRepositoryRoot -RelativePath 'modules/DeviceListExport/internal/DomAdapter.ps1'
            $text = Get-Content -LiteralPath $domAdapterPath -Raw

            $text | Should -Not -Match 'Operation\s+ClickTaskButton\s+-Await'
            $text | Should -Not -Match 'Operation\s+ClickExportMenuItem\s+-Await'
        }

        It 'keeps same-page DeviceListExport and ScanTargetSync identity contracts aligned' {
            $deviceListExportContractPath = Join-ArchitecturePath -RootPath $script:ArchitectureRepositoryRoot -RelativePath 'dom/features/device-list-export/contract.js'
            $selectContractPath = Join-ArchitecturePath -RootPath $script:ArchitectureRepositoryRoot -RelativePath 'dom/features/scan-target-sync/contract.js'
            $deviceListExportText = Get-Content -LiteralPath $deviceListExportContractPath -Raw
            $selectText = Get-Content -LiteralPath $selectContractPath -Raw

            $deviceListExportText | Should -Match 'detectDeviceListExportPageIdentity[\s\S]*requireDeviceDefault:\s*true'
            $selectText | Should -Match 'buildDevicePageIdentityChecks'
            $selectText | Should -Match 'detectDevicePageIdentity[\s\S]*buildDevicePageIdentityChecks\(''identity''\)'
            $selectText | Should -Match 'validateDevicePageContract[\s\S]*buildDevicePageIdentityChecks\(''page''\)'
            $selectText | Should -Match '\$\{scopeName\}\.viewport\.unique'
            $selectText | Should -Match '\$\{scopeName\}\.product\.identity'
            $selectText | Should -Match '\$\{scopeName\}\.sensor\.text'
            $selectText | Should -Match '\$\{scopeName\}\.deviceDefault\.text'
            $selectText | Should -Match '\$\{scopeName\}\.navigation\.sensor\.unique'
        }
    }

}
