$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

function Resolve-FoundationRoot {
    param([string]$RootPath = "")
    if (-not [string]::IsNullOrWhiteSpace($RootPath)) {
        return (Resolve-Path -LiteralPath $RootPath).Path
    }
    return (Get-Location).Path
}

function Initialize-FoundationRuntime {
    param(
        [Parameter(Mandatory)][string]$RootPath,
        [Parameter(Mandatory)][string]$ConfigPath,
        [Parameter(Mandatory)][string]$JobName,
        [string]$JobRegistryPath = ""
    )

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        throw "設定ファイルが見つかりません: $ConfigPath"
    }
    $resolvedConfigPath = (Resolve-Path -LiteralPath $ConfigPath).Path
    $config = Import-FoundationConfig -Path $resolvedConfigPath -RootPath $RootPath

    if ([string]::IsNullOrWhiteSpace($JobRegistryPath)) {
        $JobRegistryPath = Get-FoundationDefaultJobRegistryPath -RootPath $RootPath
    }
    if (-not (Test-Path -LiteralPath $JobRegistryPath)) {
        throw "ジョブ定義ファイルが見つかりません: $JobRegistryPath"
    }
    $resolvedJobRegistryPath = (Resolve-Path -LiteralPath $JobRegistryPath).Path

    $jobRegistry = Import-FoundationJobRegistry -Path $resolvedJobRegistryPath -RootPath $RootPath
    $jobDefinition = Get-FoundationJobDefinition -Registry $jobRegistry -JobName $JobName
    Assert-FoundationJobDefinitionFiles -JobName $JobName -Definition $jobDefinition

    return New-FoundationRunContext `
        -RootPath $RootPath `
        -Config $config `
        -JobName $JobName `
        -JobDefinition $jobDefinition `
        -ConfigPath $resolvedConfigPath `
        -JobRegistryPath $resolvedJobRegistryPath
}

function Import-FoundationJobModule {
    param(
        [Parameter(Mandatory)][AllowNull()][object]$JobDefinition,
        [Parameter(Mandatory)][string]$JobName
    )

    $modulePath = Get-FoundationJobDefinitionValue `
        -Definition $JobDefinition `
        -Key 'ModulePath' `
        -JobName $JobName

    if (-not (Test-Path -LiteralPath $modulePath)) {
        throw "ジョブモジュールが見つかりません: Jobs.$JobName.ModulePath = $modulePath"
    }

    Import-Module -Name $modulePath -Force -DisableNameChecking
}

function Get-FoundationJobCommand {
    param(
        [Parameter(Mandatory)][AllowNull()][object]$JobDefinition,
        [Parameter(Mandatory)][string]$JobName
    )

    $commandName = Get-FoundationJobDefinitionValue `
        -Definition $JobDefinition `
        -Key 'CommandName' `
        -JobName $JobName

    $command = Microsoft.PowerShell.Core\Get-Command -Name $commandName -CommandType Function -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        throw "ジョブ定義の CommandName が見つかりません: Jobs.$JobName.CommandName = $commandName"
    }

    return $command
}

function Invoke-FoundationEntrypoint {
    param(
        [Parameter(Mandatory)][string]$RootPath,
        [Parameter(Mandatory)][string]$ConfigPath,
        [Parameter(Mandatory)][string]$JobName,
        [string]$JobRegistryPath = "",
        [AllowNull()][hashtable]$JobSettingsOverrides = $null
    )

    $resolvedRoot = Resolve-FoundationRoot -RootPath $RootPath
    $context = $null
    try {
        $context = Initialize-FoundationRuntime `
            -RootPath $resolvedRoot `
            -ConfigPath $ConfigPath `
            -JobName $JobName `
            -JobRegistryPath $JobRegistryPath

        if ($JobSettingsOverrides) {
            foreach ($key in @($JobSettingsOverrides.Keys)) {
                $context.JobSettings[$key] = $JobSettingsOverrides[$key]
            }
        }

        Import-FoundationJobModule -JobDefinition $context.JobDefinition -JobName $JobName
        $command = Get-FoundationJobCommand `
            -JobDefinition $context.JobDefinition `
            -JobName $JobName

        Write-FoundationSection -Logger $context.Logger -Title "$JobName 開始"
        $jobResult = & $command -Context $context
        Write-FoundationSection -Logger $context.Logger -Title "$JobName 正常終了"
        return $jobResult
    }
    catch {
        $message = $_.Exception.Message
        if ($context -and $context.Logger) {
            try { Write-FoundationLog -Logger $context.Logger -Level Error -Message $message } catch { Microsoft.PowerShell.Utility\Write-Host $message }
        }
        else {
            Microsoft.PowerShell.Utility\Write-Host $message
        }
        throw
    }
    finally {
        if ($context) { Close-FoundationRunContext -Context $context }
    }
}
