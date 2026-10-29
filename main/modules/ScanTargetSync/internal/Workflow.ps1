$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

function Invoke-ScanTargetSyncSyncWorkflow {
    param(
        [Parameter(Mandatory)]$Context,
        [AllowNull()]$Dependencies = $null
    )

    $resolvedDependencies = Resolve-ScanTargetSyncWorkflowDependencies -Context $Context -Dependencies $Dependencies
    $state = New-ScanTargetSyncWorkflowState -Timing $resolvedDependencies.Timing

    try {
        Initialize-ScanTargetSyncWorkflow -Context $Context -Dependencies $resolvedDependencies
        $plan = New-ScanTargetSyncValidatedPlan `
            -Context $Context `
            -State $state `
            -Dependencies $resolvedDependencies

        if (Test-ScanTargetSyncNoSyncTarget -Context $Context -State $state -Plan $plan -Dependencies $resolvedDependencies) {
            return
        }

        $scanAndSyncResult = Invoke-ScanTargetSyncScanAndSync `
            -Context $Context `
            -State $state `
            -Plan $plan `
            -Dependencies $resolvedDependencies
        Complete-ScanTargetSyncWorkflow `
            -Context $Context `
            -State $state `
            -Plan $plan `
            -ScanAndSyncResult $scanAndSyncResult `
            -Dependencies $resolvedDependencies
        Assert-ScanTargetSyncWorkflowSucceeded -Context $Context -State $state
    }
    catch {
        Export-ScanTargetSyncFatalResultIfNeeded `
            -Context $Context `
            -State $state `
            -Reason $_.Exception.Message `
            -FileSystemService $resolvedDependencies.FileSystem
        throw
    }
}
