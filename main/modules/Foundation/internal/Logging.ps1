$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。


$script:FoundationLogger = $null

function New-FoundationLogger {
    param(
        [hashtable]$Config = @{},
        [string]$RunId = ""
    )

    $level = if ($Config.ContainsKey('Level')) { [string]$Config.Level } else { 'Info' }
    $console = if ($Config.ContainsKey('Console')) { [bool]$Config.Console } else { $true }
    $file = if ($Config.ContainsKey('File')) { [bool]$Config.File } else { $false }
    $directory = if ($Config.ContainsKey('Directory')) { [string]$Config.Directory } else { '' }
    $filePath = $null

    if ($file) {
        if ([string]::IsNullOrWhiteSpace($directory)) {
            throw "ログファイル出力が有効ですが、ログディレクトリが空です。"
        }
        $directory = Expand-FoundationPath -Path $directory
        Initialize-FoundationOutputDirectory -Directory $directory -Purpose "ログ" | Out-Null
        $filePath = Join-Path $directory ("foundation_{0}.log" -f $RunId)
    }

    $logger = [pscustomobject]@{
        Level = $level
        Console = $console
        File = $file
        FilePath = $filePath
        RunId = $RunId
    }

    $script:FoundationLogger = $logger
    return $logger
}

function Write-FoundationLog {
    param(
        [object]$Logger = $script:FoundationLogger,
        [ValidateSet('Debug','Info','Warning','Error')][string]$Level = 'Info',
        [AllowEmptyString()][string]$Message = '',
        [object]$Data = $null
    )

    if (-not $Logger) {
        Microsoft.PowerShell.Utility\Write-Host $Message
        return
    }

    $prefix = "[{0}] [{1}]" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"), $Level.ToUpperInvariant()
    if (-not [string]::IsNullOrWhiteSpace($Logger.RunId)) {
        $prefix = "$prefix [$($Logger.RunId)]"
    }

    $line = if ([string]::IsNullOrWhiteSpace($Message)) { "" } else { "$prefix $Message" }

    if ($Logger.Console -eq $true) {
        if ($Level -eq 'Warning') {
            Microsoft.PowerShell.Utility\Write-Warning $Message
        }
        elseif ($Level -eq 'Error') {
            Microsoft.PowerShell.Utility\Write-Host $line
        }
        else {
            Microsoft.PowerShell.Utility\Write-Host $line
        }
    }

    if ($Logger.File -eq $true -and -not [string]::IsNullOrWhiteSpace($Logger.FilePath)) {
        Add-Content -LiteralPath $Logger.FilePath -Value $line -Encoding UTF8
        if ($Data) {
            Add-Content -LiteralPath $Logger.FilePath -Value ($Data | ConvertTo-Json -Compress -Depth 30) -Encoding UTF8
        }
    }
}

function Write-FoundationSection {
    param(
        [object]$Logger = $script:FoundationLogger,
        [Parameter(Mandatory)][string]$Title
    )
    Write-FoundationLog -Logger $Logger -Level Info -Message ""
    Write-FoundationLog -Logger $Logger -Level Info -Message "============================================================"
    Write-FoundationLog -Logger $Logger -Level Info -Message $Title
    Write-FoundationLog -Logger $Logger -Level Info -Message "============================================================"
}

function Write-FoundationObject {
    param(
        [object]$Logger = $script:FoundationLogger,
        [string]$Message = "",
        [object]$Data,
        [int]$Depth = 10
    )
    if (-not [string]::IsNullOrWhiteSpace($Message)) {
        Write-FoundationLog -Logger $Logger -Level Info -Message $Message
    }
    Write-FoundationLog -Logger $Logger -Level Info -Message ($Data | ConvertTo-Json -Depth $Depth)
}

function Close-FoundationLogger {
    # 現在の実装は都度書き込みのため明示的なclose処理は不要。
}
