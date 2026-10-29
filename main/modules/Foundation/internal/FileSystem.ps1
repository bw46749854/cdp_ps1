$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

function Assert-FoundationSafeDirectory {
    param(
        [Parameter(Mandatory)]
        [string]$Directory,

        [string]$Purpose = "作業"
    )

    if ([string]::IsNullOrWhiteSpace($Directory)) {
        throw "$Purpose ディレクトリが空です。"
    }

    $candidateFullPath = [System.IO.Path]::GetFullPath($Directory)
    $full = $candidateFullPath.TrimEnd([char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar))

    if ([string]::IsNullOrWhiteSpace($full)) {
        throw "$Purpose ディレクトリの解決結果が空です。"
    }

    $root = [System.IO.Path]::GetPathRoot($full).TrimEnd([char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar))
    if ($full.Equals($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Purpose ディレクトリにドライブルートは指定できません: $full"
    }

    $userProfile = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
    if (-not [string]::IsNullOrWhiteSpace($userProfile)) {
        $profileFull = [System.IO.Path]::GetFullPath($userProfile).TrimEnd([char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar))
        if ($full.Equals($profileFull, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "$Purpose ディレクトリにユーザープロファイル直下は指定できません: $full"
        }

        $parent = Split-Path -Parent $full
        if (-not [string]::IsNullOrWhiteSpace($parent)) {
            $parentFull = [System.IO.Path]::GetFullPath($parent).TrimEnd([char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar))
            if ($parentFull.Equals($profileFull, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "$Purpose ディレクトリにユーザープロファイル直下の子ディレクトリは指定できません: $full"
            }
        }
    }

    if (-not (Test-Path -LiteralPath $candidateFullPath)) {
        New-Item -ItemType Directory -Path $candidateFullPath -Force | Out-Null
    }

    return (Resolve-Path -LiteralPath $candidateFullPath).Path
}

function Initialize-FoundationOutputDirectory {
    param(
        [Parameter(Mandatory)]
        [string]$Directory,

        [string]$Purpose = "出力"
    )

    $resolvedDirectory = Assert-FoundationSafeDirectory -Directory $Directory -Purpose $Purpose
    New-Item -ItemType Directory -Path $resolvedDirectory -Force | Out-Null
    return $resolvedDirectory
}

function Test-PathUnderDirectory {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Directory
    )

    $resolvedDirectory = Assert-FoundationSafeDirectory -Directory $Directory -Purpose "許可"
    $fullDirectory = [System.IO.Path]::GetFullPath($resolvedDirectory).TrimEnd([char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar))
    $fullPath = [System.IO.Path]::GetFullPath($Path)

    return $fullPath.StartsWith($fullDirectory + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)
}

function Remove-FileIfExistsSafely {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$AllowedDirectory
    )

    $resolvedAllowedDirectory = Assert-FoundationSafeDirectory -Directory $AllowedDirectory -Purpose "許可"

    if (-not (Test-PathUnderDirectory -Path $Path -Directory $resolvedAllowedDirectory)) {
        throw "削除対象ファイルが許可ディレクトリ配下ではありません。Path=$Path AllowedDirectory=$resolvedAllowedDirectory"
    }

    if (Test-Path -LiteralPath $Path) {
        $item = Get-Item -LiteralPath $Path -ErrorAction Stop

        if ($item.PSIsContainer) {
            throw "削除対象がファイルではありません: $Path"
        }

        Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
        return $true
    }

    return $false
}

function Clear-DirectoryContentsSafely {
    param(
        [Parameter(Mandatory)]
        [string]$Directory,

        [string]$Purpose = "作業"
    )

    $resolvedDirectory = Assert-FoundationSafeDirectory -Directory $Directory -Purpose $Purpose

    if (-not (Test-Path -LiteralPath $resolvedDirectory)) {
        New-Item -ItemType Directory -Path $resolvedDirectory -Force | Out-Null
        return
    }

    Get-ChildItem -LiteralPath $resolvedDirectory -Force -ErrorAction SilentlyContinue |
        ForEach-Object {
            $item = $_
            if (-not (Test-PathUnderDirectory -Path $item.FullName -Directory $resolvedDirectory)) {
                throw "$Purpose フォルダ配下ではない項目を削除しようとしました: $($item.FullName)"
            }
            Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
        }
}
