$ErrorActionPreference = "Stop"

Describe 'DOM operation registry contract with JavaScript bundle' {
    BeforeAll {
        function Resolve-DomContractRepositoryRoot {
            $candidatePaths = @(
                (Join-Path $PSScriptRoot '..'),
                (Join-Path $PSScriptRoot '..\..'),
                (Get-Location).Path
            )

            foreach ($candidatePath in $candidatePaths) {
                try {
                    $resolved = Resolve-Path -LiteralPath $candidatePath -ErrorAction Stop
                    if (Test-Path -LiteralPath (Join-Path $resolved.Path 'dom\features')) {
                        return $resolved.Path
                    }
                }
                catch {
                    # continue probing likely roots
                }
            }

            throw 'Repository root could not be resolved from test context.'
        }

        function Resolve-DomContractPath {
            param(
                [Parameter(Mandatory)][string]$RootPath,
                [Parameter(Mandatory)][string]$Path
            )

            if ([System.IO.Path]::IsPathRooted($Path)) {
                return $Path
            }

            return (Join-Path $RootPath $Path)
        }

        function Resolve-DomContractFallbackPaths {
            param(
                [Parameter(Mandatory)][string]$RootPath,
                [Parameter(Mandatory)][string[]]$FallbackRelativePaths
            )

            $paths = New-Object System.Collections.Generic.List[string]
            foreach ($path in @($FallbackRelativePaths)) {
                [void]$paths.Add((Resolve-DomContractPath -RootPath $RootPath -Path ([string]$path)))
            }

            return $paths.ToArray()
        }

        function Get-DomContractFeaturePathsFromRegistry {
            param(
                [Parameter(Mandatory)][string]$RootPath,
                [Parameter(Mandatory)][string]$JobName,
                [Parameter(Mandatory)][string[]]$FallbackRelativePaths
            )

            $registryPath = Join-Path (Join-Path $RootPath 'config') 'foundation.jobs.psd1'
            if (-not (Test-Path -LiteralPath $registryPath)) {
                return @(Resolve-DomContractFallbackPaths -RootPath $RootPath -FallbackRelativePaths $FallbackRelativePaths)
            }

            $registry = Import-PowerShellDataFile -LiteralPath $registryPath
            if (-not $registry.ContainsKey('Jobs')) {
                return @(Resolve-DomContractFallbackPaths -RootPath $RootPath -FallbackRelativePaths $FallbackRelativePaths)
            }

            if (-not $registry.Jobs.ContainsKey($JobName)) {
                return @(Resolve-DomContractFallbackPaths -RootPath $RootPath -FallbackRelativePaths $FallbackRelativePaths)
            }

            $definition = $registry.Jobs[$JobName]
            if ($definition.ContainsKey('DomFeaturePaths')) {
                $paths = New-Object System.Collections.Generic.List[string]
                foreach ($path in @($definition.DomFeaturePaths)) {
                    [void]$paths.Add((Resolve-DomContractPath -RootPath $RootPath -Path ([string]$path)))
                }
                return $paths.ToArray()
            }

            if ($definition.ContainsKey('DomFeaturePath')) {
                return @((Resolve-DomContractPath -RootPath $RootPath -Path ([string]$definition.DomFeaturePath)))
            }

            return @(Resolve-DomContractFallbackPaths -RootPath $RootPath -FallbackRelativePaths $FallbackRelativePaths)
        }

        function Get-DomContractFeatureScriptText {
            param(
                [Parameter(Mandatory)][string]$RootPath,
                [Parameter(Mandatory)][string]$JobName,
                [Parameter(Mandatory)][string[]]$FallbackRelativePaths
            )

            $paths = @(Get-DomContractFeaturePathsFromRegistry -RootPath $RootPath -JobName $JobName -FallbackRelativePaths $FallbackRelativePaths)
            $parts = New-Object System.Collections.Generic.List[string]
            foreach ($path in $paths) {
                [void]$parts.Add((Get-Content -LiteralPath $path -Raw))
            }

            return ($parts -join "`n`n")
        }

        function Get-JavaScriptObjectMethodSetFromDomContractText {
            param([Parameter(Mandatory)][string]$Text)

            $methodRegex = [regex]'(?m)^\s{8}(?:async\s+)?([A-Za-z_$][A-Za-z0-9_$]*)\s*\([^)]*\)\s*\{'
            $methods = @{}

            foreach ($match in $methodRegex.Matches($Text)) {
                $methods[$match.Groups[1].Value] = $true
            }

            return $methods
        }

        $script:DomContractRepositoryRoot = Resolve-DomContractRepositoryRoot

        Import-Module -Name (Join-Path $script:DomContractRepositoryRoot 'modules\InstalledAppExport\InstalledAppExport.psm1') -Force
        Import-Module -Name (Join-Path $script:DomContractRepositoryRoot 'modules\ScanTargetSync\ScanTargetSync.psm1') -Force
        Import-Module -Name (Join-Path $script:DomContractRepositoryRoot 'modules\DeviceListExport\DeviceListExport.psm1') -Force

        $script:InstalledAppExportDomText = Get-DomContractFeatureScriptText -RootPath $script:DomContractRepositoryRoot -JobName 'InstalledAppExport' -FallbackRelativePaths @(
            'dom\features\installed-app-export\contract.js'
            'dom\features\installed-app-export\list.js'
            'dom\features\installed-app-export\detail.js'
            'dom\features\installed-app-export\apps.js'
            'dom\features\installed-app-export\actions.js'
            'dom\features\installed-app-export\index.js'
        )
        $script:InstalledAppExportJavaScriptMethods = Get-JavaScriptObjectMethodSetFromDomContractText -Text $script:InstalledAppExportDomText

        $script:ScanTargetSyncDomText = Get-DomContractFeatureScriptText -RootPath $script:DomContractRepositoryRoot -JobName 'ScanTargetSync' -FallbackRelativePaths @(
            'dom\features\scan-target-sync\contract.js'
            'dom\features\scan-target-sync\list.js'
            'dom\features\scan-target-sync\actions.js'
            'dom\features\scan-target-sync\index.js'
        )
        $script:ScanTargetSyncJavaScriptMethods = Get-JavaScriptObjectMethodSetFromDomContractText -Text $script:ScanTargetSyncDomText

        $script:DeviceListExportDomText = Get-DomContractFeatureScriptText -RootPath $script:DomContractRepositoryRoot -JobName 'DeviceListExport' -FallbackRelativePaths @(
            'dom\features\device-list-export\contract.js'
            'dom\features\device-list-export\navigation.js'
            'dom\features\device-list-export\export.js'
            'dom\features\device-list-export\index.js'
        )
        $script:DeviceListExportJavaScriptMethods = Get-JavaScriptObjectMethodSetFromDomContractText -Text $script:DeviceListExportDomText
    }

    Context 'InstalledAppExport DOM operation registry contract with JavaScript bundle' {
        It 'registers the expected browser helper name' {
            $script:InstalledAppExportDomText | Should -Match 'window\.__InstalledAppExportDomHelper\s*=\s*factory\(window, document\)'
            $script:InstalledAppExportDomText | Should -Match 'createInstalledAppExportDomHelper'
        }

        It 'maps every PowerShell operation MethodName to an implemented JavaScript method' {
            InModuleScope InstalledAppExport -Parameters @{ JavaScriptMethods = $script:InstalledAppExportJavaScriptMethods } {
                foreach ($operation in @($script:InstalledAppExportDomOperations.Keys | Sort-Object)) {
                    $definition = Get-InstalledAppExportDomOperationDefinition -Operation $operation
                    $JavaScriptMethods.ContainsKey($definition.MethodName) | Should -Be $true
                }
            }
        }
    }



    Context 'DeviceListExport DOM operation registry contract with JavaScript bundle' {
        It 'registers the expected browser helper name' {
            $script:DeviceListExportDomText | Should -Match 'window\.__DeviceListExportDomHelper\s*=\s*factory\(window, document\)'
            $script:DeviceListExportDomText | Should -Match 'createDeviceListExportDomHelper'
        }

        It 'maps every PowerShell operation MethodName to an implemented JavaScript method' {
            InModuleScope DeviceListExport -Parameters @{ JavaScriptMethods = $script:DeviceListExportJavaScriptMethods } {
                foreach ($operation in @($script:DeviceListExportDomOperations.Keys | Sort-Object)) {
                    $definition = Get-DeviceListExportDomOperationDefinition -Operation $operation
                    $JavaScriptMethods.ContainsKey($definition.MethodName) | Should -Be $true
                }
            }
        }
    }

    Context 'ScanTargetSync DOM operation registry contract with JavaScript bundle' {
        It 'registers the expected browser helper name' {
            $script:ScanTargetSyncDomText | Should -Match 'window\.__ScanTargetSyncDomHelper\s*=\s*factory\(window, document\)'
            $script:ScanTargetSyncDomText | Should -Match 'createScanTargetSyncDomHelper'
        }

        It 'maps every PowerShell operation MethodName to an implemented JavaScript method' {
            InModuleScope ScanTargetSync -Parameters @{ JavaScriptMethods = $script:ScanTargetSyncJavaScriptMethods } {
                foreach ($operation in @($script:ScanTargetSyncDomOperations.Keys | Sort-Object)) {
                    $definition = Get-ScanTargetSyncDomOperationDefinition -Operation $operation
                    $JavaScriptMethods.ContainsKey($definition.MethodName) | Should -Be $true
                }
            }
        }
    }
}
