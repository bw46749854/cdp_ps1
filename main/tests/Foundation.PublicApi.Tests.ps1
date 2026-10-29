$ErrorActionPreference = "Stop"
$modulePath = Join-Path $PSScriptRoot '..\modules\Foundation\Foundation.psm1'
Import-Module -Name $modulePath -Force

Describe 'Foundation public API surface' {
    It 'exports only the supported public functions used by entrypoints and feature modules' {
        $expected = @(
            'Invoke-FoundationEntrypoint',
            'New-FoundationRunContext',
            'Close-FoundationRunContext',
            'Open-FoundationPage',
            'Open-FoundationPageMatchingIdentity',
            'Invoke-FoundationJavaScript',
            'Wait-FoundationJavaScript',
            'Set-FoundationDownloadDirectory',
            'Register-DomBundle',
            'Register-FoundationDomBundle',
            'Invoke-FoundationDomHelperMethod',
            'Wait-FoundationDomHelperMethod',
            'Wait-FoundationDomHelperMethodResult',
            'Assert-FoundationDomHelperContract',
            'Invoke-ScrollableListWorkflow',
            'Initialize-FoundationOutputDirectory',
            'Clear-DirectoryContentsSafely',
            'Assert-FoundationSafeDirectory',
            'Test-PathUnderDirectory',
            'Remove-FileIfExistsSafely',
            'Write-FoundationLog',
            'Write-FoundationSection',
            'Write-FoundationObject',
            'Test-FoundationFatalError'
        ) | Sort-Object

        $actual = @(Get-Command -Module Foundation -CommandType Function | Select-Object -ExpandProperty Name | Sort-Object)
        @(Compare-Object -ReferenceObject $expected -DifferenceObject $actual).Count | Should -Be 0
    }

    It 'does not export internal CDP, config, CSV, job registry, and low-level DOM helpers' {
        $actual = @(Get-Command -Module Foundation -CommandType Function | Select-Object -ExpandProperty Name)
        $notPublic = @(
            'Send-CDPCommand',
            'Receive-CDPMessage',
            'Import-FoundationConfig',
            'Import-FoundationJobRegistry',
            'Get-FoundationJobDefinition',
            'Resolve-FoundationJobDefinitionPaths',
            'New-FoundationDomHelperMethodExpression',
            'ConvertTo-FoundationJavaScriptLiteral',
            'Assert-ScrollableListOperations',
            'Import-FoundationJobModule',
            'Get-FoundationJobCommand'
        )

        foreach ($functionName in $notPublic) {
            $actual | Should -Not -Contain $functionName
        }
    }
}
