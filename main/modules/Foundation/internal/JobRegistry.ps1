$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

function Get-FoundationDefaultJobRegistryPath {
    param([Parameter(Mandatory)][string]$RootPath)

    return (Join-Path -Path (Join-Path -Path $RootPath -ChildPath 'config') -ChildPath 'foundation.jobs.psd1')
}

function Import-FoundationJobRegistry {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$RootPath,
        [switch]$ValidateAllFiles
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "ジョブ定義ファイルが見つかりません: $Path"
    }

    $registry = Import-PowerShellDataFile -LiteralPath $Path
    Assert-FoundationJobRegistry -Registry $registry
    $registry = Resolve-FoundationJobRegistryPaths -Registry $registry -RootPath $RootPath

    if ($ValidateAllFiles) {
        Assert-FoundationJobDefinitionFiles -Registry $registry
    }

    return $registry
}

function Assert-FoundationJobRegistry {
    param([Parameter(Mandatory)][hashtable]$Registry)

    if (-not $Registry.ContainsKey('Jobs')) {
        throw 'ジョブ定義ファイルに必須キーがありません: Jobs'
    }

    if (-not ($Registry.Jobs -is [hashtable])) {
        throw 'ジョブ定義ファイルの Jobs は hashtable で指定してください。'
    }

    if (@($Registry.Jobs.Keys).Count -eq 0) {
        throw 'ジョブ定義ファイルの Jobs が空です。'
    }

    foreach ($jobName in @($Registry.Jobs.Keys)) {
        Assert-FoundationJobDefinition -JobName ([string]$jobName) -Definition $Registry.Jobs[$jobName]
    }
}

function Assert-FoundationJobDefinitionStringValue {
    param(
        [Parameter(Mandatory)][string]$JobName,
        [Parameter(Mandatory)][hashtable]$Definition,
        [Parameter(Mandatory)][string]$Key
    )

    if (-not $Definition.ContainsKey($Key)) {
        throw "ジョブ定義に必須キーがありません: Jobs.$JobName.$Key"
    }

    if ([string]::IsNullOrWhiteSpace([string]$Definition[$Key])) {
        throw "ジョブ定義の値が空です: Jobs.$JobName.$Key"
    }
}


function Test-FoundationJobDefinitionUsesDom {
    param(
        [Parameter(Mandatory)][hashtable]$Definition,
        [Parameter(Mandatory)][string]$JobName
    )

    if (-not $Definition.ContainsKey('UsesDom')) {
        return $true
    }

    if (-not ($Definition['UsesDom'] -is [bool])) {
        throw "ジョブ定義の UsesDom は boolean で指定してください: Jobs.$JobName.UsesDom"
    }

    return [bool]$Definition['UsesDom']
}

function Assert-FoundationJobDefinitionDomFeaturePathContract {
    param(
        [Parameter(Mandatory)][string]$JobName,
        [Parameter(Mandatory)][hashtable]$Definition
    )

    $usesDom = Test-FoundationJobDefinitionUsesDom -Definition $Definition -JobName $JobName
    $hasSinglePath = $Definition.ContainsKey('DomFeaturePath')
    $hasPathList = $Definition.ContainsKey('DomFeaturePaths')

    if (-not $usesDom) {
        if ($hasSinglePath -or $hasPathList) {
            throw "DOMを使用しないジョブに DOM feature path は指定できません: Jobs.$JobName"
        }
        return
    }

    if ($hasSinglePath -and $hasPathList) {
        throw "ジョブ定義の DomFeaturePath と DomFeaturePaths は同時に指定できません: Jobs.$JobName"
    }

    if (-not $hasSinglePath -and -not $hasPathList) {
        throw "ジョブ定義に DOM feature path がありません: Jobs.$JobName.DomFeaturePath または Jobs.$JobName.DomFeaturePaths"
    }

    if ($hasSinglePath) {
        if ([string]::IsNullOrWhiteSpace([string]$Definition['DomFeaturePath'])) {
            throw "ジョブ定義の値が空です: Jobs.$JobName.DomFeaturePath"
        }
        return
    }

    $value = $Definition['DomFeaturePaths']
    if ($null -eq $value) {
        throw "ジョブ定義の値が空です: Jobs.$JobName.DomFeaturePaths"
    }

    if ($value -is [string]) {
        throw "ジョブ定義の DomFeaturePaths は文字列配列で指定してください: Jobs.$JobName.DomFeaturePaths"
    }

    if (-not ($value -is [System.Array])) {
        throw "ジョブ定義の DomFeaturePaths は文字列配列で指定してください: Jobs.$JobName.DomFeaturePaths"
    }

    $paths = @($value)
    if ($paths.Count -eq 0) {
        throw "ジョブ定義の DomFeaturePaths が空です: Jobs.$JobName.DomFeaturePaths"
    }

    foreach ($path in $paths) {
        if ([string]::IsNullOrWhiteSpace([string]$path)) {
            throw "ジョブ定義の DomFeaturePaths に空の値があります: Jobs.$JobName.DomFeaturePaths"
        }
    }
}

function Assert-FoundationJobDefinition {
    param(
        [Parameter(Mandatory)][string]$JobName,
        [Parameter(Mandatory)]$Definition
    )

    if ([string]::IsNullOrWhiteSpace($JobName)) {
        throw 'ジョブ定義名が空です。'
    }

    if (-not ($Definition -is [hashtable])) {
        throw "ジョブ定義は hashtable で指定してください: Jobs.$JobName"
    }

    foreach ($key in @('ModulePath','CommandName')) {
        Assert-FoundationJobDefinitionStringValue -JobName $JobName -Definition $Definition -Key $key
    }

    Assert-FoundationJobDefinitionDomFeaturePathContract -JobName $JobName -Definition $Definition

    if ([string]$Definition['CommandName'] -notmatch '^[A-Za-z][A-Za-z0-9_-]*$') {
        throw "ジョブ定義の CommandName が PowerShell コマンド名として不正です: Jobs.$JobName.CommandName"
    }
}

function Resolve-FoundationJobRegistryPaths {
    param(
        [Parameter(Mandatory)][hashtable]$Registry,
        [Parameter(Mandatory)][string]$RootPath
    )

    foreach ($jobName in @($Registry.Jobs.Keys)) {
        $definition = $Registry.Jobs[$jobName]
        $null = Resolve-FoundationJobDefinitionPaths -Definition $definition -RootPath $RootPath
    }

    return $Registry
}

function Resolve-FoundationJobDefinitionDomFeaturePaths {
    param(
        [Parameter(Mandatory)][hashtable]$Definition,
        [Parameter(Mandatory)][string]$RootPath
    )

    if ($Definition.ContainsKey('UsesDom') -and -not [bool]$Definition['UsesDom']) {
        return @()
    }

    if ($Definition.ContainsKey('DomFeaturePath')) {
        return @((Resolve-FoundationJobRegistryPath -RootPath $RootPath -Path ([string]$Definition['DomFeaturePath'])))
    }

    $resolvedPaths = New-Object System.Collections.Generic.List[string]
    foreach ($path in @($Definition['DomFeaturePaths'])) {
        [void]$resolvedPaths.Add((Resolve-FoundationJobRegistryPath -RootPath $RootPath -Path ([string]$path)))
    }

    return $resolvedPaths.ToArray()
}

function Resolve-FoundationJobDefinitionPaths {
    param(
        [Parameter(Mandatory)][hashtable]$Definition,
        [Parameter(Mandatory)][string]$RootPath
    )

    $Definition['ModulePath'] = Resolve-FoundationJobRegistryPath -RootPath $RootPath -Path ([string]$Definition['ModulePath'])

    if ($Definition.ContainsKey('UsesDom') -and -not [bool]$Definition['UsesDom']) {
        return
    }

    if ($Definition.ContainsKey('DomFeaturePath')) {
        $Definition['DomFeaturePath'] = Resolve-FoundationJobRegistryPath -RootPath $RootPath -Path ([string]$Definition['DomFeaturePath'])
        return
    }

    $Definition['DomFeaturePaths'] = @(Resolve-FoundationJobDefinitionDomFeaturePaths -Definition $Definition -RootPath $RootPath)
}

function Resolve-FoundationJobRegistryPath {
    param(
        [Parameter(Mandatory)][string]$RootPath,
        [Parameter(Mandatory)][string]$Path
    )

    $expanded = Expand-FoundationPath -Path $Path
    if ([System.IO.Path]::IsPathRooted($expanded)) {
        return $expanded
    }

    return (Join-Path -Path $RootPath -ChildPath $expanded)
}

function Get-FoundationJobDefinitionFilePaths {
    param([Parameter(Mandatory)][hashtable]$Definition)

    $paths = New-Object System.Collections.Generic.List[string]
    [void]$paths.Add([string]$Definition['ModulePath'])

    if ($Definition.ContainsKey('UsesDom') -and -not [bool]$Definition['UsesDom']) {
        return $paths.ToArray()
    }

    if ($Definition.ContainsKey('DomFeaturePath')) {
        [void]$paths.Add([string]$Definition['DomFeaturePath'])
    }
    else {
        foreach ($path in @($Definition['DomFeaturePaths'])) {
            [void]$paths.Add([string]$path)
        }
    }

    return $paths.ToArray()
}

function Assert-FoundationSingleJobDefinitionFiles {
    param(
        [Parameter(Mandatory)][string]$JobName,
        [Parameter(Mandatory)][hashtable]$Definition
    )

    foreach ($path in @(Get-FoundationJobDefinitionFilePaths -Definition $Definition)) {
        if (-not (Test-Path -LiteralPath $path)) {
            throw "ジョブ定義のファイルが見つかりません: Jobs.$JobName = $path"
        }
    }
}

function Assert-FoundationJobDefinitionFiles {
    [CmdletBinding(DefaultParameterSetName='Registry')]
    param(
        [Parameter(Mandatory=$true, ParameterSetName='Registry')][hashtable]$Registry,
        [Parameter(Mandatory=$true, ParameterSetName='Definition')][string]$JobName,
        [Parameter(Mandatory=$true, ParameterSetName='Definition')][hashtable]$Definition
    )

    if ($PSCmdlet.ParameterSetName -eq 'Definition') {
        Assert-FoundationSingleJobDefinitionFiles -JobName $JobName -Definition $Definition
        return
    }

    foreach ($registryJobName in @($Registry.Jobs.Keys)) {
        Assert-FoundationSingleJobDefinitionFiles `
            -JobName ([string]$registryJobName) `
            -Definition $Registry.Jobs[$registryJobName]
    }
}

function Get-FoundationJobDefinition {
    param(
        [Parameter(Mandatory)][hashtable]$Registry,
        [Parameter(Mandatory)][string]$JobName
    )

    if (-not $Registry.ContainsKey('Jobs')) {
        throw 'ジョブ定義ファイルに必須キーがありません: Jobs'
    }

    if (-not $Registry.Jobs.ContainsKey($JobName)) {
        throw "ジョブ定義が見つかりません: $JobName"
    }

    return $Registry.Jobs[$JobName]
}
