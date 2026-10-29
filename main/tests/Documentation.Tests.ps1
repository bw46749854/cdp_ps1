$ErrorActionPreference = 'Stop'

Describe 'Documentation quality gate' {
    BeforeAll {
        $script:ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
        $script:MainRoot = Join-Path $script:ProjectRoot 'main'
        $script:DocsRoot = Join-Path $script:ProjectRoot 'docs'

        function Read-ProjectText {
            param([Parameter(Mandatory)][string]$LiteralPath)
            return [System.IO.File]::ReadAllText($LiteralPath, [System.Text.Encoding]::UTF8)
        }

        function Join-DocPath {
            param([Parameter(Mandatory)][string[]]$Parts)
            $path = $script:DocsRoot
            foreach ($part in $Parts) {
                $path = Join-Path $path $part
            }
            return $path
        }

        function Get-ExpectedDocPathForSource {
            param([Parameter(Mandatory)][System.IO.FileInfo]$SourceFile)

            $relative = $SourceFile.FullName.Substring($script:ProjectRoot.Path.Length + 1).Replace('\\', '/')
            $name = $SourceFile.Name

            if ($relative -eq 'main/run_job.ps1') {
                return Join-DocPath @('01_起動設定', 'run_job.ps1.md')
            }

            if ($relative -like 'main/config/*.psd1') {
                return Join-DocPath @('01_起動設定', ('config__' + $name + '.md'))
            }

            if ($relative -like 'main/dom/features/*/*.js') {
                $parts = $relative -split '/'
                $feature = $parts[3]
                return Join-DocPath @('08_DOM_JavaScript', $feature, ($name + '.md'))
            }

            if ($relative -like 'main/modules/CompositeJobs/*.psm1') {
                return Join-DocPath @('07_CompositeJobs', 'CompositeJobs.psm1.md')
            }

            if ($relative -like 'main/modules/*/*') {
                $parts = $relative -split '/'
                $module = $parts[2]
                $docFolderByModule = @{
                    Foundation     = '02_Foundation'
                    DeviceListExport    = '03_DeviceListExport'
                    InstalledAppExport       = '04_InstalledAppExport'
                    ScanTargetSync = '05_ScanTargetSync'
                    LastMonthInstallExtract       = '06_LastMonthInstallExtract'
                    CompositeJobs  = '07_CompositeJobs'
                }

                if (-not $docFolderByModule.ContainsKey($module)) {
                    return $null
                }

                $folder = $docFolderByModule[$module]
                if ($name -eq ($module + '.psm1')) {
                    return Join-DocPath @($folder, ($module + '.psm1.md'))
                }

                return Join-DocPath @($folder, ('internal__' + $name + '.md'))
            }

            return $null
        }

        function Get-ProductionSourceFilesForDocs {
            $files = @()
            $files += Get-ChildItem -Path (Join-Path $script:MainRoot 'run_job.ps1') -File
            $files += Get-ChildItem -Path (Join-Path $script:MainRoot 'config') -Filter '*.psd1' -File
            $files += Get-ChildItem -Path (Join-Path $script:MainRoot 'modules') -Recurse -File -Include '*.ps1','*.psm1' | Where-Object { $_.FullName -notmatch '\\vendor\\' }
            $files += Get-ChildItem -Path (Join-Path $script:MainRoot 'dom\features') -Recurse -File -Filter '*.js'
            return @($files | Sort-Object FullName)
        }
    }

    It 'has a corresponding documentation file for every production source file' {
        $missing = @()
        foreach ($sourceFile in Get-ProductionSourceFilesForDocs) {
            $docPath = Get-ExpectedDocPathForSource -SourceFile $sourceFile
            if (-not $docPath) { continue }
            if (-not (Test-Path -LiteralPath $docPath)) {
                $relative = $sourceFile.FullName.Substring($script:ProjectRoot.Path.Length + 1)
                $missing += "$relative -> $docPath"
            }
        }

        $missing | Should -Be @()
    }

    It 'does not keep legacy missing ResultBuilder file references in living docs' {
        $matches = @()
        foreach ($docFile in Get-ChildItem -Path $script:DocsRoot -Recurse -File -Filter '*.md') {
            $docText = Read-ProjectText -LiteralPath $docFile.FullName
            if ($docText -match 'ResultBuilder\.ps1') {
                $matches += $docFile.FullName
            }
        }

        $matches | Should -BeNullOrEmpty
    }

    It 'keeps ARCHITECTURE.md maintenance guide path pointed at the real file' {
        $architectureText = Read-ProjectText -LiteralPath (Join-Path $script:MainRoot 'ARCHITECTURE.md')
        $architectureText | Should -Match 'docs/00_最初に読む/00_MAINTENANCE_GUIDE\.md'
        $architectureText | Should -Not -Match 'docs/MAINTENANCE_GUIDE\.md'
    }

    It 'keeps ScanTargetSync DOM operation documentation aligned with operation registry names' {
        $sourcePath = Join-Path $script:MainRoot 'modules\ScanTargetSync\internal\DomOperations.ps1'
        $docPath = Join-DocPath @('05_ScanTargetSync', 'internal__DomOperations.ps1.md')
        $sourceText = Read-ProjectText -LiteralPath $sourcePath
        $docText = Read-ProjectText -LiteralPath $docPath

        $operationMatches = [regex]::Matches($sourceText, '^\s*([A-Za-z0-9]+)\s*=\s*@\{', [System.Text.RegularExpressions.RegexOptions]::Multiline)
        foreach ($match in $operationMatches) {
            $operationName = $match.Groups[1].Value
            $docText | Should -Match ([regex]::Escape($operationName))
        }
    }

    It 'keeps the documented test file list aligned with existing test files' {
        $docPath = Join-DocPath @('09_テスト仕様', '06_テストファイル一覧.md')
        $docText = Read-ProjectText -LiteralPath $docPath
        $testFiles = @()
        $testFiles += Get-ChildItem -Path (Join-Path $script:MainRoot 'tests') -File -Filter '*.Tests.ps1'
        $testFiles += Get-ChildItem -Path (Join-Path $script:MainRoot 'tests\js') -File -Filter '*.test.js'

        $missing = @()
        foreach ($testFile in $testFiles) {
            if ($docText -notmatch [regex]::Escape($testFile.Name)) {
                $missing += $testFile.Name
            }
        }

        $missing | Should -Be @()
    }

    It 'does not point readers to missing docs from living docs' {
        $docFiles = Get-ChildItem -Path $script:DocsRoot -Recurse -File -Filter '*.md'
        $missing = @()

        foreach ($docFile in $docFiles) {
            $docText = Read-ProjectText -LiteralPath $docFile.FullName
            $matches = [regex]::Matches($docText, '`(docs/[^`]+\.md|main/[^`]+\.(ps1|psm1|psd1|js|md))`')

            foreach ($match in $matches) {
                $referencedPath = $match.Groups[1].Value

                if ($referencedPath -match '[<>\*\?\[]') {
                    continue
                }

                $relativePath = $referencedPath -replace '/', [System.IO.Path]::DirectorySeparatorChar
                $targetPath = Join-Path $script:ProjectRoot.Path $relativePath

                if (-not (Test-Path -LiteralPath $targetPath)) {
                    $sourceRelative = $docFile.FullName.Substring($script:ProjectRoot.Path.Length + 1)
                    $missing += "$sourceRelative -> $referencedPath"
                }
            }
        }

        $missing | Should -Be @()
    }

    It 'keeps SOLID guide from becoming a second architecture source of truth' {
        $solidDocPath = Join-DocPath @('10_SOLID原則', '抽象の価値判断.md')
        $solidDocText = Read-ProjectText -LiteralPath $solidDocPath

        $solidDocText | Should -Match 'main/ARCHITECTURE\.md'
        $solidDocText | Should -Match '正本'
        $solidDocText | Should -Not -Match '###\s+SRP-MUST-0[1-9]'
        $solidDocText | Should -Not -Match '###\s+DIP-MUST-0[1-9]'
        $solidDocText | Should -Not -Match '###\s+DIP-EXCEPTION-0[1-9]'
    }


    It 'keeps root batch JobName values aligned with documented batch entrypoints' {
        $docPath = Join-DocPath @('01_起動設定', 'bat起動入口とJobName.md')
        $docText = Read-ProjectText -LiteralPath $docPath
        $jobRegistry = Import-PowerShellDataFile -LiteralPath (Join-Path $script:MainRoot 'config\foundation.jobs.psd1')
        $batchFiles = Get-ChildItem -Path $script:ProjectRoot.Path -File -Filter '*.bat'
        $missing = @()

        foreach ($batchFile in $batchFiles) {
            $batchText = Read-ProjectText -LiteralPath $batchFile.FullName
            $match = [regex]::Match($batchText, '-JobName\s+["'']?([A-Za-z0-9_]+)["'']?')
            if (-not $match.Success) {
                $missing += "$($batchFile.Name) -> JobName not found"
                continue
            }

            $jobName = $match.Groups[1].Value
            if (-not $jobRegistry.Jobs.ContainsKey($jobName)) {
                $missing += "$($batchFile.Name) -> $jobName is not registered in foundation.jobs.psd1"
            }

            if ($docText -notmatch [regex]::Escape($batchFile.Name)) {
                $missing += "$($batchFile.Name) is missing from bat起動入口とJobName.md"
            }

            if ($docText -notmatch [regex]::Escape($jobName)) {
                $missing += "$($batchFile.Name) -> $jobName is missing from bat起動入口とJobName.md"
            }
        }

        @($batchFiles).Count | Should -Not -Be 0
        $missing | Should -Be @()
    }

    It 'does not document weekly batch as direct ScanTargetSync execution' {
        $docPaths = @(
            (Join-DocPath @('00_最初に読む', '03_JobNameとContextの関係.md')),
            (Join-DocPath @('01_起動設定', 'bat起動入口とJobName.md'))
        )
        $badMatches = @()

        foreach ($docPath in $docPaths) {
            $docText = Read-ProjectText -LiteralPath $docPath
            $badPatterns = @(
                'powershell(\.exe)?\s+[^\r\n]*-File\s+main\\run_job\.ps1\s+-JobName\s+["'']?ScanTargetSync["'']?',
                '週次作業_スキャン対象整合\.bat[\s\S]{0,120}-JobName\s+["'']?ScanTargetSync["'']?'
            )

            foreach ($pattern in $badPatterns) {
                if ($docText -match $pattern) {
                    $badMatches += "$docPath -> $pattern"
                }
            }
        }

        $badMatches | Should -Be @()
    }

    It 'keeps foundation.jobs.psd1 job definitions aligned with startup documentation' {
        $jobRegistry = Import-PowerShellDataFile -LiteralPath (Join-Path $script:MainRoot 'config\foundation.jobs.psd1')
        $docPath = Join-DocPath @('01_起動設定', 'config__foundation.jobs.psd1.md')
        $docText = Read-ProjectText -LiteralPath $docPath
        $missing = @()

        foreach ($jobName in $jobRegistry.Jobs.Keys) {
            $definition = $jobRegistry.Jobs[$jobName]
            foreach ($expected in @($jobName, $definition.ModulePath, $definition.CommandName)) {
                if ($docText -notmatch [regex]::Escape([string]$expected)) {
                    $missing += "$jobName -> missing $expected from config__foundation.jobs.psd1.md"
                }
            }

            if ($definition.ContainsKey('UsesDom') -and $definition.UsesDom -eq $false) {
                $rowPattern = '\|\s*`' + [regex]::Escape($jobName) + '`\s*\|[^\r\n]*`UsesDom = \$false`'
                if ($docText -notmatch $rowPattern) {
                    $missing += "$jobName -> UsesDom = `$false is not documented in job table"
                }
            }

            if ($definition.ContainsKey('DomFeaturePaths')) {
                $rowPattern = '\|\s*`' + [regex]::Escape($jobName) + '`\s*\|[^\r\n]*`DomFeaturePaths`'
                if ($docText -notmatch $rowPattern) {
                    $missing += "$jobName -> DomFeaturePaths is not documented in job table"
                }
            }
        }

        $missing | Should -Be @()
    }

    It 'keeps all DOM operation registries aligned with PowerShell DOM mapping documentation' {
        $mappingDocPath = Join-DocPath @('08_DOM_JavaScript', 'PowerShell_DOM対応表.md')
        $mappingDocText = Read-ProjectText -LiteralPath $mappingDocPath
        $operationFiles = @(
            (Join-Path $script:MainRoot 'modules\DeviceListExport\internal\DomOperations.ps1'),
            (Join-Path $script:MainRoot 'modules\InstalledAppExport\internal\DomOperations.ps1'),
            (Join-Path $script:MainRoot 'modules\ScanTargetSync\internal\DomOperations.ps1')
        )
        $missing = @()

        foreach ($operationFile in $operationFiles) {
            $sourceText = Read-ProjectText -LiteralPath $operationFile
            $helperPattern = "`$script:[A-Za-z0-9]+DomHelperName\s*=\s*'([^']+)'"
            $helperMatch = [regex]::Match($sourceText, $helperPattern)
            $helperName = $helperMatch.Groups[1].Value
            if ($mappingDocText -notmatch [regex]::Escape($helperName)) {
                $missing += "$operationFile -> helper $helperName is missing from PowerShell_DOM対応表.md"
            }

            $operationMatches = [regex]::Matches($sourceText, '^\s*([A-Za-z0-9]+)\s*=\s*@\{([^\r\n]+)\}', [System.Text.RegularExpressions.RegexOptions]::Multiline)
            foreach ($match in $operationMatches) {
                $operationName = $match.Groups[1].Value
                $body = $match.Groups[2].Value
                $methodMatch = [regex]::Match($body, "MethodName\s*=\s*'([^']+)'")
                $missingBehaviorMatch = [regex]::Match($body, "MissingHelperBehavior\s*=\s*'([^']+)'")
                $contractScopeMatch = [regex]::Match($body, "ContractScope\s*=\s*'([^']+)'")
                $hasAwait = $body -match 'Await\s*=\s*\$true'

                foreach ($expected in @($operationName, $methodMatch.Groups[1].Value, $missingBehaviorMatch.Groups[1].Value)) {
                    if ($mappingDocText -notmatch [regex]::Escape($expected)) {
                        $missing += "$operationFile -> $operationName -> missing $expected from PowerShell_DOM対応表.md"
                    }
                }

                if ($contractScopeMatch.Success -and $mappingDocText -notmatch [regex]::Escape($contractScopeMatch.Groups[1].Value)) {
                    $missing += "$operationFile -> $operationName -> missing ContractScope $($contractScopeMatch.Groups[1].Value) from PowerShell_DOM対応表.md"
                }

                if ($hasAwait) {
                    $rowPattern = '\|\s*`' + [regex]::Escape($operationName) + '`\s*\|[^\r\n]*`Await = \$true`'
                    if ($mappingDocText -notmatch $rowPattern) {
                        $missing += "$operationFile -> $operationName -> Await = `$true is not documented in PowerShell_DOM対応表.md"
                    }
                }
            }
        }

        $missing | Should -Be @()
    }

    It 'keeps DOM contract reading guide linked from entrypoint docs' {
        $guidePath = Join-DocPath @('08_DOM_JavaScript', 'DOM契約とselector診断の読み方.md')
        Test-Path -LiteralPath $guidePath | Should -Be $true

        $startHereText = Read-ProjectText -LiteralPath (Join-DocPath @('00_最初に読む', 'START_HERE.md'))
        $domGuideText = Read-ProjectText -LiteralPath (Join-DocPath @('00_最初に読む', '12_DOM_JavaScriptの読み方.md'))
        $mappingDocText = Read-ProjectText -LiteralPath (Join-DocPath @('08_DOM_JavaScript', 'PowerShell_DOM対応表.md'))

        $expectedPath = 'docs/08_DOM_JavaScript/DOM契約とselector診断の読み方.md'
        $startHereText | Should -Match ([regex]::Escape($expectedPath))
        $domGuideText | Should -Match ([regex]::Escape($expectedPath))
        $mappingDocText | Should -Match ([regex]::Escape($expectedPath))
    }

}
