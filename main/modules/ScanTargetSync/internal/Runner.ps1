$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。


function Initialize-ScanTargetSyncJob {
    param(
        [Parameter(Mandatory)]$Context,
        [AllowNull()]$Dependencies = $null
    )

    $resolvedDependencies = Resolve-ScanTargetSyncWorkflowDependencies -Context $Context -Dependencies $Dependencies
    Assert-ScanTargetSyncWorkflowInitializationDependencies -Dependencies $resolvedDependencies

    $initializeOutputDirectory = Get-ScanTargetSyncCallbackScriptBlock -Callbacks $resolvedDependencies.FileSystem -Name 'InitializeOutputDirectory'
    & $initializeOutputDirectory $Context.JobSettings.OutputDirectory "出力" | Out-Null
}

function Invoke-ScanTargetSyncJob {
    param([Parameter(Mandatory)]$Context)

    Initialize-ScanTargetSyncJob -Context $Context
    Invoke-ScanTargetSyncSyncWorkflow -Context $Context
}
