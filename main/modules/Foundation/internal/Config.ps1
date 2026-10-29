$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。


function Import-FoundationConfig {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$RootPath
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "設定ファイルが見つかりません: $Path"
    }

    $config = Import-PowerShellDataFile -LiteralPath $Path
    Assert-FoundationConfig -Config $config
    return Resolve-FoundationConfigPaths -Config $config -RootPath $RootPath
}

function Assert-FoundationConfig {
    param([Parameter(Mandatory)][hashtable]$Config)

    foreach ($key in @('Common','Jobs')) {
        if (-not $Config.ContainsKey($key)) {
            throw "設定ファイルに必須キーがありません: $key"
        }

        if (-not ($Config[$key] -is [hashtable])) {
            throw "設定ファイルの $key は hashtable で指定してください。"
        }
    }
}

function Get-FoundationJobConfig {
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [Parameter(Mandatory)][string]$JobName
    )

    if (-not $Config.ContainsKey('Jobs') -or -not ($Config.Jobs -is [hashtable])) {
        throw '設定ファイルに有効な Jobs がありません。'
    }

    if (-not $Config.Jobs.ContainsKey($JobName)) {
        throw "ジョブ設定が見つかりません: $JobName"
    }

    if (-not ($Config.Jobs[$JobName] -is [hashtable])) {
        throw "ジョブ設定は hashtable で指定してください: Jobs.$JobName"
    }

    return $Config.Jobs[$JobName]
}

function Expand-FoundationPath {
    param([AllowEmptyString()][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $Path
    }

    return [Environment]::ExpandEnvironmentVariables($Path)
}

function Resolve-FoundationConfigPaths {
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [Parameter(Mandatory)][string]$RootPath
    )

    $resolvedRootPath = (Resolve-Path -LiteralPath $RootPath).Path
    $projectRoot = Split-Path -Parent $resolvedRootPath

    foreach ($sectionName in @('Common')) {
        if ($Config.ContainsKey($sectionName)) {
            Resolve-FoundationHashtablePaths -Table $Config[$sectionName] -BaseDirectory $projectRoot
        }
    }
    if ($Config.ContainsKey('Jobs') -and ($Config.Jobs -is [hashtable])) {
        foreach ($jobName in @($Config.Jobs.Keys)) {
            if ($Config.Jobs[$jobName] -is [hashtable]) {
                Resolve-FoundationHashtablePaths -Table $Config.Jobs[$jobName] -BaseDirectory $projectRoot
            }
        }
    }

    return $Config
}

function Resolve-FoundationHashtablePaths {
    param(
        [Parameter(Mandatory)][hashtable]$Table,
        [Parameter(Mandatory)][string]$BaseDirectory
    )

    foreach ($key in @($Table.Keys)) {
        $value = $Table[$key]
        if ($value -is [hashtable]) {
            Resolve-FoundationHashtablePaths -Table $value -BaseDirectory $BaseDirectory
        }
        elseif ($key -like '*Path' -or $key -like '*Directory') {
            $expanded = Expand-FoundationPath -Path ([string]$value)
            if ([string]::IsNullOrWhiteSpace($expanded) -or [System.IO.Path]::IsPathRooted($expanded)) {
                $Table[$key] = $expanded
            }
            else {
                $Table[$key] = Join-Path -Path $BaseDirectory -ChildPath $expanded
            }
        }
    }
}
