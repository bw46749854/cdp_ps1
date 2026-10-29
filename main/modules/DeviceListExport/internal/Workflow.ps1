$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

function Invoke-DeviceListExportWorkflowStep {
    param(
        [Parameter(Mandatory)]$Logger,
        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory)][scriptblock]$Action
    )

    $writeInfo = Get-DeviceListExportCallbackScriptBlock -Callbacks $Logger -Name 'WriteInfo'
    & $writeInfo $Message
    return & $Action
}

function Invoke-DeviceListExportWorkflow {
    param(
        [Parameter(Mandatory)]$Context,
        [AllowNull()]$Dependencies = $null
    )

    $settings = $Context.JobSettings
    $resolvedDependencies = Resolve-DeviceListExportWorkflowDependencies -Context $Context -Dependencies $Dependencies

    $dom = $resolvedDependencies.Dom
    $download = $resolvedDependencies.Download
    $timing = $resolvedDependencies.Timing
    $logger = $resolvedDependencies.Logger

    $register = Get-DeviceListExportCallbackScriptBlock -Callbacks $dom -Name 'Register'
    $assertInitialContract = Get-DeviceListExportCallbackScriptBlock -Callbacks $dom -Name 'AssertInitialContract'
    $assertExportPageContract = Get-DeviceListExportCallbackScriptBlock -Callbacks $dom -Name 'AssertExportPageContract'
    $clickTaskButton = Get-DeviceListExportCallbackScriptBlock -Callbacks $dom -Name 'ClickTaskButton'
    $waitTaskMenuReady = Get-DeviceListExportCallbackScriptBlock -Callbacks $dom -Name 'WaitTaskMenuReady'
    $clickExportMenuItem = Get-DeviceListExportCallbackScriptBlock -Callbacks $dom -Name 'ClickExportMenuItem'
    $assertPostcondition = Get-DeviceListExportCallbackScriptBlock -Callbacks $dom -Name 'AssertPostcondition'

    $waitDownloadedCsv = Get-DeviceListExportCallbackScriptBlock -Callbacks $download -Name 'WaitDownloadedCsv'
    $renameDownloadedCsv = Get-DeviceListExportCallbackScriptBlock -Callbacks $download -Name 'RenameDownloadedCsv'
    $timestampText = Get-DeviceListExportCallbackScriptBlock -Callbacks $timing -Name 'TimestampText'

    Invoke-DeviceListExportWorkflowStep -Logger $logger -Message 'DOM bundleを登録します。' -Action { & $register } | Out-Null
    Invoke-DeviceListExportWorkflowStep -Logger $logger -Message '初期DOM契約を検証します。' -Action { & $assertInitialContract } | Out-Null
    Invoke-DeviceListExportWorkflowStep -Logger $logger -Message 'エクスポート対象画面DOM契約を検証します。' -Action { & $assertExportPageContract } | Out-Null
    Invoke-DeviceListExportWorkflowStep -Logger $logger -Message '操作ボタンをクリックします。' -Action { & $clickTaskButton } | Out-Null
    Invoke-DeviceListExportWorkflowStep -Logger $logger -Message '操作メニュー表示を待機します。' -Action { & $waitTaskMenuReady ([int]$settings.TaskMenuTimeoutSeconds) } | Out-Null
    $postClick = Invoke-DeviceListExportWorkflowStep -Logger $logger -Message '操作メニュー内の「CSV出力」をクリックします。' -Action { & $clickExportMenuItem }
    Invoke-DeviceListExportWorkflowStep -Logger $logger -Message 'エクスポートクリック後DOM契約を検証します。' -Action { & $assertPostcondition } | Out-Null

    $downloadedCsv = Invoke-DeviceListExportWorkflowStep -Logger $logger -Message 'CSVダウンロード完了を待機します。' -Action {
        & $waitDownloadedCsv `
            ([string]$settings.TempDirectory) `
            ([string]$settings.DownloadedCsvFileNamePattern) `
            ([int]$settings.DownloadTimeoutSeconds) `
            ([int]$settings.DownloadStableSeconds)
    }

    $renamedCsv = Invoke-DeviceListExportWorkflowStep -Logger $logger -Message 'ダウンロードCSVを既定ルールでリネームします。' -Action {
        & $renameDownloadedCsv `
            $downloadedCsv `
            ([string]$settings.DownloadDirectory) `
            ([string]$settings.OutputFileNameTemplate) `
            (& $timestampText)
    }

    return New-DeviceListExportResult `
        -DownloadedCsvPath $downloadedCsv.FullName `
        -ExportedCsvPath $renamedCsv.FullName `
        -DomResult $postClick
}
