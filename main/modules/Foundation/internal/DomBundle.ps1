$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。


function Test-DomBundleJobDefinitionKey {
    param(
        [Parameter(Mandatory)][AllowNull()][object]$Definition,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$JobName
    )

    if ($null -eq $Definition) {
        throw "ジョブ定義が指定されていません: $JobName"
    }

    if ($Definition -is [hashtable]) {
        return $Definition.ContainsKey($Key)
    }

    return ($null -ne $Definition.PSObject.Properties[$Key])
}

function Get-DomBundleJobDefinitionRawValue {
    param(
        [Parameter(Mandatory)][AllowNull()][object]$Definition,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$JobName
    )

    if (-not (Test-DomBundleJobDefinitionKey -Definition $Definition -Key $Key -JobName $JobName)) {
        throw "ジョブ定義に必須キーがありません: Jobs.$JobName.$Key"
    }

    if ($Definition -is [hashtable]) {
        return $Definition[$Key]
    }

    return $Definition.PSObject.Properties[$Key].Value
}

function Get-FoundationJobDefinitionValue {
    param(
        [Parameter(Mandatory)][AllowNull()][object]$Definition,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$JobName
    )

    $value = Get-DomBundleJobDefinitionRawValue -Definition $Definition -Key $Key -JobName $JobName
    if ([string]::IsNullOrWhiteSpace([string]$value)) {
        throw "ジョブ定義の値が空です: Jobs.$JobName.$Key"
    }

    return [string]$value
}

function ConvertTo-FoundationDomFeaturePathList {
    param(
        [Parameter(Mandatory)][string]$RootPath,
        [Parameter(Mandatory)][string]$JobName,
        [Parameter(Mandatory)][AllowNull()][object]$Value
    )

    if ($null -eq $Value) {
        throw "ジョブ定義の値が空です: Jobs.$JobName.DomFeaturePaths"
    }

    if ($Value -is [string]) {
        throw "ジョブ定義の DomFeaturePaths は文字列配列で指定してください: Jobs.$JobName.DomFeaturePaths"
    }

    if (-not ($Value -is [System.Array])) {
        throw "ジョブ定義の DomFeaturePaths は文字列配列で指定してください: Jobs.$JobName.DomFeaturePaths"
    }

    $items = @($Value)
    if ($items.Count -eq 0) {
        throw "ジョブ定義の DomFeaturePaths が空です: Jobs.$JobName.DomFeaturePaths"
    }

    $paths = New-Object System.Collections.Generic.List[string]
    foreach ($item in $items) {
        if ([string]::IsNullOrWhiteSpace([string]$item)) {
            throw "ジョブ定義の DomFeaturePaths に空の値があります: Jobs.$JobName.DomFeaturePaths"
        }

        [void]$paths.Add((Resolve-FoundationJobRegistryPath -RootPath $RootPath -Path ([string]$item)))
    }

    return $paths.ToArray()
}

function Get-FoundationDomFeaturePathsFromDefinition {
    param(
        [Parameter(Mandatory)][string]$RootPath,
        [Parameter(Mandatory)][string]$JobName,
        [Parameter(Mandatory)][AllowNull()][object]$JobDefinition
    )

    if (Test-DomBundleJobDefinitionKey -Definition $JobDefinition -Key 'UsesDom' -JobName $JobName) {
        $usesDom = Get-DomBundleJobDefinitionRawValue -Definition $JobDefinition -Key 'UsesDom' -JobName $JobName
        if (-not ($usesDom -is [bool])) {
            throw "ジョブ定義の UsesDom は boolean で指定してください: Jobs.$JobName.UsesDom"
        }
        if (-not [bool]$usesDom) {
            throw "DOMを使用しないジョブでは DOM bundle を登録できません: Jobs.$JobName"
        }
    }

    $hasSinglePath = Test-DomBundleJobDefinitionKey -Definition $JobDefinition -Key 'DomFeaturePath' -JobName $JobName
    $hasPathList = Test-DomBundleJobDefinitionKey -Definition $JobDefinition -Key 'DomFeaturePaths' -JobName $JobName

    if ($hasSinglePath -and $hasPathList) {
        throw "ジョブ定義の DomFeaturePath と DomFeaturePaths は同時に指定できません: Jobs.$JobName"
    }

    if (-not $hasSinglePath -and -not $hasPathList) {
        throw "ジョブ定義に DOM feature path がありません: Jobs.$JobName.DomFeaturePath または Jobs.$JobName.DomFeaturePaths"
    }

    if ($hasSinglePath) {
        $domFeaturePath = Get-FoundationJobDefinitionValue -Definition $JobDefinition -Key 'DomFeaturePath' -JobName $JobName
        return @((Resolve-FoundationJobRegistryPath -RootPath $RootPath -Path $domFeaturePath))
    }

    $domFeaturePaths = Get-DomBundleJobDefinitionRawValue -Definition $JobDefinition -Key 'DomFeaturePaths' -JobName $JobName
    return @(ConvertTo-FoundationDomFeaturePathList -RootPath $RootPath -JobName $JobName -Value $domFeaturePaths)
}

function Resolve-FoundationDomBundleJobDefinition {
    param(
        [Parameter(Mandatory)][string]$RootPath,
        [Parameter(Mandatory)][string]$JobName,
        [AllowNull()][object]$JobDefinition = $null,
        [string]$JobRegistryPath = ""
    )

    if ($null -ne $JobDefinition) {
        return $JobDefinition
    }

    if ([string]::IsNullOrWhiteSpace($JobRegistryPath)) {
        $JobRegistryPath = Get-FoundationDefaultJobRegistryPath -RootPath $RootPath
    }

    $registry = Import-FoundationJobRegistry -Path $JobRegistryPath -RootPath $RootPath
    return (Get-FoundationJobDefinition -Registry $registry -JobName $JobName)
}

function Get-DomBundleDefinition {
    param(
        [Parameter(Mandatory)][string]$RootPath,
        [Parameter(Mandatory)][string]$JobName,
        [AllowNull()][object]$JobDefinition = $null,
        [string]$JobRegistryPath = ""
    )

    if ([string]::IsNullOrWhiteSpace($JobName)) {
        throw 'JobName が空です。'
    }

    $resolvedDefinition = Resolve-FoundationDomBundleJobDefinition `
        -RootPath $RootPath `
        -JobName $JobName `
        -JobDefinition $JobDefinition `
        -JobRegistryPath $JobRegistryPath

    $features = @(Get-FoundationDomFeaturePathsFromDefinition `
        -RootPath $RootPath `
        -JobName $JobName `
        -JobDefinition $resolvedDefinition)

    return @($features)
}

function Assert-DomBundleFileExists {
    param([Parameter(Mandatory)][string[]]$Paths)

    foreach ($path in $Paths) {
        if (-not (Test-Path -LiteralPath $path)) {
            throw "DOM bundleファイルが見つかりません: $path"
        }
    }
}

function Get-DomBundleScript {
    param([Parameter(Mandatory)][string[]]$Paths)

    Assert-DomBundleFileExists -Paths $Paths
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($path in $Paths) {
        $parts.Add((Get-Content -LiteralPath $path -Raw -Encoding UTF8))
    }
    return ($parts -join "`n`n")
}

function Register-DomBundle {
    param(
        [Parameter(Mandatory)][string]$RootPath,
        [Parameter(Mandatory)][string]$JobName,
        [AllowNull()][object]$JobDefinition = $null,
        [string]$JobRegistryPath = ""
    )

    $paths = @(Get-DomBundleDefinition `
        -RootPath $RootPath `
        -JobName $JobName `
        -JobDefinition $JobDefinition `
        -JobRegistryPath $JobRegistryPath)

    $script = Get-DomBundleScript -Paths $paths
    $script = $script + "`n//# sourceURL=foundation-$JobName-dom-bundle.js"
    $registered = Invoke-FoundationJavaScript -Expression $script -TimeoutSeconds 30

    if ($registered -ne $true) {
        $json = $registered | ConvertTo-Json -Compress -Depth 20
        throw "DOM bundle登録結果が true ではありません。Job=$JobName result=$json"
    }

    Write-FoundationLog -Level Info -Message "DOM bundleを登録しました: $JobName"
}
