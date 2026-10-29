$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

# DOM feature helper 呼び出し用 facade。
# Feature module は後続改修でこの層だけに依存させ、raw JavaScript / DOM contract 内部関数への直接依存を減らす。

function Test-FoundationDomHelperIdentifier {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$ParameterName
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw "$ParameterName が空です。"
    }

    if ($Name -notmatch '^[A-Za-z_$][A-Za-z0-9_$]*$') {
        throw "$ParameterName は JavaScript identifier 形式で指定してください: $Name"
    }
}

function ConvertTo-FoundationJavaScriptLiteral {
    param(
        [AllowNull()][object]$Value,
        [int]$Depth = 30
    )

    if ($null -eq $Value) {
        return 'null'
    }

    return (ConvertTo-Json -InputObject $Value -Compress -Depth $Depth)
}

function ConvertTo-FoundationJavaScriptArgumentArrayLiteral {
    param(
        [AllowNull()][object[]]$Arguments,
        [int]$Depth = 30
    )

    $literals = New-Object System.Collections.Generic.List[string]
    foreach ($argument in @($Arguments)) {
        [void]$literals.Add((ConvertTo-FoundationJavaScriptLiteral -Value $argument -Depth $Depth))
    }

    return ('[' + ($literals -join ',') + ']')
}

function New-FoundationDomHelperMissingContractResult {
    param(
        [Parameter(Mandatory)][string]$HelperName,
        [Parameter(Mandatory)][string]$MethodName,
        [Parameter(Mandatory)][string]$Scope,
        [Parameter(Mandatory)][string]$Message
    )

    return [pscustomobject]@{
        scope = $Scope
        ok = $false
        fatalCount = 1
        warningCount = 0
        checks = @(
            [pscustomobject]@{
                name = 'helper.registered'
                ok = $false
                severity = 'fatal'
                message = $Message
                details = [pscustomobject]@{
                    helperName = $HelperName
                    methodName = $MethodName
                    reason = 'helper_not_registered'
                }
            }
        )
        details = [pscustomobject]@{
            helperName = $HelperName
            methodName = $MethodName
            reason = 'helper_not_registered'
        }
    }
}

function New-FoundationDomHelperMissingScript {
    param(
        [Parameter(Mandatory)][string]$HelperName,
        [Parameter(Mandatory)][string]$MethodName,
        [Parameter(Mandatory)][ValidateSet('Throw','ReturnNull','ReturnValue','ReturnContractFailure')][string]$MissingHelperBehavior,
        [AllowNull()][object]$MissingValue,
        [Parameter(Mandatory)][string]$ContractScope,
        [string]$MissingHelperMessage = '',
        [int]$JsonDepth = 30
    )

    $message = $MissingHelperMessage
    if ([string]::IsNullOrWhiteSpace($message)) {
        $message = "DOM helper is not registered: $HelperName"
    }

    switch ($MissingHelperBehavior) {
        'Throw' {
            $messageLiteral = ConvertTo-FoundationJavaScriptLiteral -Value $message -Depth $JsonDepth
            return "throw new Error($messageLiteral);"
        }
        'ReturnNull' {
            return 'return null;'
        }
        'ReturnValue' {
            $literal = ConvertTo-FoundationJavaScriptLiteral -Value $MissingValue -Depth $JsonDepth
            return "return $literal;"
        }
        'ReturnContractFailure' {
            $contract = New-FoundationDomHelperMissingContractResult `
                -HelperName $HelperName `
                -MethodName $MethodName `
                -Scope $ContractScope `
                -Message $message
            $literal = ConvertTo-FoundationJavaScriptLiteral -Value $contract -Depth $JsonDepth
            return "return $literal;"
        }
        default {
            throw "未対応の MissingHelperBehavior です: $MissingHelperBehavior"
        }
    }
}

function New-FoundationDomHelperMethodExpression {
    param(
        [Parameter(Mandatory)][string]$HelperName,
        [Parameter(Mandatory)][string]$MethodName,
        [AllowNull()][object[]]$Arguments = @(),
        [ValidateSet('Throw','ReturnNull','ReturnValue','ReturnContractFailure')][string]$MissingHelperBehavior = 'Throw',
        [AllowNull()][object]$MissingValue = $null,
        [string]$ContractScope = 'domHelper',
        [string]$MissingHelperMessage = '',
        [int]$JsonDepth = 30,
        [switch]$Await
    )

    Test-FoundationDomHelperIdentifier -Name $HelperName -ParameterName 'HelperName'
    Test-FoundationDomHelperIdentifier -Name $MethodName -ParameterName 'MethodName'

    $helperNameLiteral = ConvertTo-FoundationJavaScriptLiteral -Value $HelperName -Depth $JsonDepth
    $methodNameLiteral = ConvertTo-FoundationJavaScriptLiteral -Value $MethodName -Depth $JsonDepth
    $argumentsLiteral = ConvertTo-FoundationJavaScriptArgumentArrayLiteral -Arguments $Arguments -Depth $JsonDepth
    $missingScript = New-FoundationDomHelperMissingScript `
        -HelperName $HelperName `
        -MethodName $MethodName `
        -MissingHelperBehavior $MissingHelperBehavior `
        -MissingValue $MissingValue `
        -ContractScope $ContractScope `
        -MissingHelperMessage $MissingHelperMessage `
        -JsonDepth $JsonDepth

    if ($Await) {
        $callStatement = 'const result = helper[methodName].apply(helper, args); return await result;'
        return @"
(async () => {
const helperName = $helperNameLiteral;
const methodName = $methodNameLiteral;
const args = $argumentsLiteral;
const helper = window[helperName];

if (!helper) {
    $missingScript
}

if (typeof helper[methodName] !== 'function') {
    throw new Error('DOM helper method is not registered: ' + helperName + '.' + methodName);
}

$callStatement
})()
"@
    }

    $callStatement = 'return helper[methodName].apply(helper, args);'
    return @"
(() => {
const helperName = $helperNameLiteral;
const methodName = $methodNameLiteral;
const args = $argumentsLiteral;
const helper = window[helperName];

if (!helper) {
    $missingScript
}

if (typeof helper[methodName] !== 'function') {
    throw new Error('DOM helper method is not registered: ' + helperName + '.' + methodName);
}

$callStatement
})()
"@
}

function New-FoundationDomHelperTimingRuntime {
    [pscustomobject]@{
        Now = { Get-Date }
        SleepMilliseconds = { param([int]$Milliseconds) Start-Sleep -Milliseconds $Milliseconds }
    }
}

function Get-FoundationDomHelperTimingScriptBlock {
    param(
        [Parameter(Mandatory)]
        [object]$Timing,

        [Parameter(Mandatory)]
        [string]$Name
    )

    $property = $Timing.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value -or -not ($property.Value -is [scriptblock])) {
        throw "DOM helper timing runtime に必要な scriptblock がありません: $Name"
    }

    return $property.Value
}

function Resolve-FoundationDomHelperTimingRuntime {
    param(
        [AllowNull()]
        [object]$Timing
    )

    if ($null -eq $Timing) {
        $Timing = New-FoundationDomHelperTimingRuntime
    }

    [void](Get-FoundationDomHelperTimingScriptBlock -Timing $Timing -Name 'Now')
    [void](Get-FoundationDomHelperTimingScriptBlock -Timing $Timing -Name 'SleepMilliseconds')

    return $Timing
}

function Get-FoundationDomHelperNow {
    param(
        [Parameter(Mandatory)]
        [object]$Timing
    )

    $nowCallback = Get-FoundationDomHelperTimingScriptBlock -Timing $Timing -Name 'Now'
    $now = & $nowCallback

    if ($null -eq $now) {
        throw 'DOM helper timing runtime の Now が null を返しました。'
    }

    return [datetime]$now
}

function Invoke-FoundationDomHelperSleepMilliseconds {
    param(
        [Parameter(Mandatory)]
        [object]$Timing,

        [int]$Milliseconds
    )

    $sleepCallback = Get-FoundationDomHelperTimingScriptBlock -Timing $Timing -Name 'SleepMilliseconds'
    & $sleepCallback $Milliseconds
}

function Get-FoundationDomHelperRemainingSeconds {
    param(
        [Parameter(Mandatory)]
        [datetime]$Deadline,

        [AllowNull()]
        [object]$Timing = $null
    )

    $Timing = Resolve-FoundationDomHelperTimingRuntime -Timing $Timing
    $remainingSeconds = [int][Math]::Ceiling(($Deadline - (Get-FoundationDomHelperNow -Timing $Timing)).TotalSeconds)
    if ($remainingSeconds -lt 1) {
        return 1
    }

    return $remainingSeconds
}

function Register-FoundationDomBundle {
    [CmdletBinding(DefaultParameterSetName='Context')]
    param(
        [Parameter(Mandatory=$true, ParameterSetName='Context')][object]$Context,
        [Parameter(Mandatory=$true, ParameterSetName='RootPath')][string]$RootPath,
        [Parameter(Mandatory=$true, ParameterSetName='RootPath')][string]$JobName,
        [Parameter(ParameterSetName='RootPath')][string]$JobRegistryPath = ""
    )

    if ($PSCmdlet.ParameterSetName -eq 'Context') {
        if ($null -eq $Context) {
            throw 'Context が空です。'
        }

        if (-not $Context.RootPath) {
            throw 'Context.RootPath が空です。'
        }

        if (-not $Context.JobName) {
            throw 'Context.JobName が空です。'
        }

        $RootPath = [string]$Context.RootPath
        $JobName = [string]$Context.JobName
        $jobDefinition = $Context.JobDefinition

        Register-DomBundle `
            -RootPath $RootPath `
            -JobName $JobName `
            -JobDefinition $jobDefinition
        return
    }

    Register-DomBundle `
        -RootPath $RootPath `
        -JobName $JobName `
        -JobRegistryPath $JobRegistryPath
}

function Invoke-FoundationDomHelperMethod {
    param(
        [Parameter(Mandatory)][string]$HelperName,
        [Parameter(Mandatory)][string]$MethodName,
        [AllowNull()][object[]]$Arguments = @(),
        [int]$TimeoutSeconds = 30,
        [ValidateSet('Throw','ReturnNull','ReturnValue','ReturnContractFailure')][string]$MissingHelperBehavior = 'Throw',
        [AllowNull()][object]$MissingValue = $null,
        [string]$ContractScope = 'domHelper',
        [string]$MissingHelperMessage = '',
        [int]$JsonDepth = 30,
        [switch]$Await
    )

    $expression = New-FoundationDomHelperMethodExpression `
        -HelperName $HelperName `
        -MethodName $MethodName `
        -Arguments $Arguments `
        -MissingHelperBehavior $MissingHelperBehavior `
        -MissingValue $MissingValue `
        -ContractScope $ContractScope `
        -MissingHelperMessage $MissingHelperMessage `
        -JsonDepth $JsonDepth `
        -Await:$Await

    return Invoke-FoundationJavaScript -Expression $expression -TimeoutSeconds $TimeoutSeconds
}

function Wait-FoundationDomHelperMethod {
    param(
        [Parameter(Mandatory)][string]$HelperName,
        [Parameter(Mandatory)][string]$MethodName,
        [AllowNull()][object[]]$Arguments = @(),
        [int]$TimeoutSeconds = 10,
        [string]$Description = 'DOM helper condition',
        [ValidateSet('Throw','ReturnNull','ReturnValue','ReturnContractFailure')][string]$MissingHelperBehavior = 'Throw',
        [AllowNull()][object]$MissingValue = $null,
        [string]$ContractScope = 'domHelper',
        [string]$MissingHelperMessage = '',
        [int]$JsonDepth = 30,
        [switch]$Await
    )

    $expression = New-FoundationDomHelperMethodExpression `
        -HelperName $HelperName `
        -MethodName $MethodName `
        -Arguments $Arguments `
        -MissingHelperBehavior $MissingHelperBehavior `
        -MissingValue $MissingValue `
        -ContractScope $ContractScope `
        -MissingHelperMessage $MissingHelperMessage `
        -JsonDepth $JsonDepth `
        -Await:$Await

    Wait-FoundationJavaScript -Expression $expression -TimeoutSeconds $TimeoutSeconds -Description $Description
}

function Wait-FoundationDomHelperMethodResult {
    param(
        [Parameter(Mandatory)][string]$HelperName,
        [Parameter(Mandatory)][string]$MethodName,
        [AllowNull()][object[]]$Arguments = @(),
        [int]$TimeoutSeconds = 10,
        [string]$Description = 'DOM helper result condition',
        [scriptblock]$AcceptResult = { param($Result) $Result -eq $true },
        [int]$PollIntervalMilliseconds = 250,
        [ValidateSet('Throw','ReturnNull','ReturnValue','ReturnContractFailure')][string]$MissingHelperBehavior = 'Throw',
        [AllowNull()][object]$MissingValue = $null,
        [string]$ContractScope = 'domHelper',
        [string]$MissingHelperMessage = '',
        [int]$JsonDepth = 30,
        [switch]$Await,
        [AllowNull()][object]$Timing = $null
    )

    if (-not $AcceptResult) {
        throw 'AcceptResult が空です。'
    }

    if ($PollIntervalMilliseconds -lt 1) {
        $PollIntervalMilliseconds = 1
    }

    $Timing = Resolve-FoundationDomHelperTimingRuntime -Timing $Timing
    $deadline = (Get-FoundationDomHelperNow -Timing $Timing).AddSeconds($TimeoutSeconds)
    $lastResult = $null
    $hasLastResult = $false
    $lastError = $null

    while ((Get-FoundationDomHelperNow -Timing $Timing) -lt $deadline) {
        try {
            $remainingSeconds = Get-FoundationDomHelperRemainingSeconds -Deadline $deadline -Timing $Timing
            $result = Invoke-FoundationDomHelperMethod `
                -HelperName $HelperName `
                -MethodName $MethodName `
                -Arguments $Arguments `
                -TimeoutSeconds $remainingSeconds `
                -MissingHelperBehavior $MissingHelperBehavior `
                -MissingValue $MissingValue `
                -ContractScope $ContractScope `
                -MissingHelperMessage $MissingHelperMessage `
                -JsonDepth $JsonDepth `
                -Await:$Await

            $lastResult = $result
            $hasLastResult = $true
            $accepted = & $AcceptResult $result
            if ($accepted -eq $true) {
                return $result
            }
        }
        catch {
            $lastError = $_.Exception.Message
        }

        Invoke-FoundationDomHelperSleepMilliseconds -Timing $Timing -Milliseconds $PollIntervalMilliseconds
    }

    if ($hasLastResult) {
        $json = $lastResult | ConvertTo-Json -Compress -Depth $JsonDepth
        throw "待機タイムアウト: $Description / last result: $json"
    }

    if ($lastError) {
        throw "待機タイムアウト: $Description / last error: $lastError"
    }

    throw "待機タイムアウト: $Description"
}

function Assert-FoundationDomHelperContract {
    param(
        [Parameter(Mandatory)][string]$HelperName,
        [Parameter(Mandatory)][string]$MethodName,
        [AllowNull()][object[]]$Arguments = @(),
        [int]$TimeoutSeconds = 20,
        [Parameter(Mandatory)][string]$Description,
        [ValidateSet('Throw','ReturnNull','ReturnValue','ReturnContractFailure')][string]$MissingHelperBehavior = 'Throw',
        [AllowNull()][object]$MissingValue = $null,
        [string]$ContractScope = 'domHelper',
        [string]$MissingHelperMessage = '',
        [int]$JsonDepth = 30,
        [switch]$Await
    )

    $expression = New-FoundationDomHelperMethodExpression `
        -HelperName $HelperName `
        -MethodName $MethodName `
        -Arguments $Arguments `
        -MissingHelperBehavior $MissingHelperBehavior `
        -MissingValue $MissingValue `
        -ContractScope $ContractScope `
        -MissingHelperMessage $MissingHelperMessage `
        -JsonDepth $JsonDepth `
        -Await:$Await

    $result = Wait-DomContractResult -Expression $expression -TimeoutSeconds $TimeoutSeconds -Description $Description
    Assert-DomContractResult -Result $result -Description $Description
    return $result
}
