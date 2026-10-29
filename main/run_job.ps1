param(
    [Parameter(Mandatory)][string]$JobName,
    [string]$ConfigPath = "",
    [string]$JobRegistryPath = ""
)

$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

$ScriptDirectory = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $PSScriptRoot
}
elseif ($MyInvocation.MyCommand.Path) {
    Split-Path -Parent $MyInvocation.MyCommand.Path
}
else {
    (Get-Location).Path
}

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $ScriptDirectory "config\foundation.config.psd1"
}

$FoundationModulePath = Join-Path $ScriptDirectory "modules\Foundation\Foundation.psm1"

if (-not (Test-Path -LiteralPath $FoundationModulePath)) {
    throw "Foundationモジュールが見つかりません: $FoundationModulePath"
}

Import-Module -Name $FoundationModulePath -Force -DisableNameChecking

Invoke-FoundationEntrypoint `
    -RootPath $ScriptDirectory `
    -ConfigPath $ConfigPath `
    -JobName $JobName `
    -JobRegistryPath $JobRegistryPath
