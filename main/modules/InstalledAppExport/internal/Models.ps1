$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

function New-InstalledAppExportProcessResult { param([string]$DataId,[string]$AssetName,[string]$CsvPath) return [pscustomobject]@{ DataId=$DataId; AssetName=$AssetName; CsvPath=$CsvPath } }
function New-InstalledAppExportFailure { param([string]$DataId,[string]$AssetName,[string]$Reason,[AllowEmptyString()][string]$Timestamp = '') return [pscustomobject]@{ DataId=$DataId; AssetName=$AssetName; Reason=$Reason; Timestamp=$Timestamp } }
function Get-InstalledAppExportRowKey { param([object]$Row) $dataId=[string]$Row.dataId; $name=[string]$Row.assetName; if([string]::IsNullOrWhiteSpace($dataId) -or [string]::IsNullOrWhiteSpace($name)){ return '' }; return "$dataId|$name" }
