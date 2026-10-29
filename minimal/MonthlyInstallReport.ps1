param(
    [int]$Port = 9222,
    [string]$Root = "$PSScriptRoot\monthly",
    [string]$Prefix = 'app_list_',
    [string]$PageTitleLike = '端末一覧*'
)

$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

# ============================================================
# 最小構成版 MonthlyInstallReport
#   main/ のモジュールを使わず、1ファイルで同じ流れを実行する。
#   1. 端末一覧の各行を開き、「インストール済みアプリ」タブからCSVを取得する
#   2. 取得したCSVから、前月に導入されたアプリを pc_installation.csv にまとめる
#   DOM契約の検証や失敗一覧CSVの出力は行わない（導入日が読めない行は件数だけ表示する）。
# ============================================================

function New-Directory([string]$Path) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
    return (Resolve-Path -LiteralPath $Path).Path
}

function Connect-Page([string]$TitleLike) {
    $targets = (Invoke-WebRequest "http://localhost:$Port/json" -UseBasicParsing).Content | ConvertFrom-Json
    $pages = @($targets | Where-Object { $_.type -eq 'page' -and $_.title -like $TitleLike })
    if ($pages.Count -ne 1) {
        throw "対象タブが1つに決まりません（タイトル '$TitleLike' に一致: $($pages.Count)件）。"
    }

    $socket = New-Object Net.WebSockets.ClientWebSocket
    $socket.ConnectAsync([Uri]$pages[0].webSocketDebuggerUrl, [Threading.CancellationToken]::None).Wait()
    return $socket
}

function Receive-Message {
    $buffer = New-Object byte[] 1048576
    $stream = New-Object IO.MemoryStream
    do {
        $segment = New-Object 'ArraySegment[byte]' -ArgumentList (, $buffer)
        $result = $script:Socket.ReceiveAsync($segment, [Threading.CancellationToken]::None).Result
        $stream.Write($buffer, 0, $result.Count)
    } while (-not $result.EndOfMessage)
    return [Text.Encoding]::UTF8.GetString($stream.ToArray())
}

function Invoke-Cdp([string]$Method, [hashtable]$Params = @{}) {
    $script:MessageId++
    $json = @{ id = $script:MessageId; method = $Method; params = $Params } | ConvertTo-Json -Depth 20 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    $segment = New-Object 'ArraySegment[byte]' -ArgumentList (, $bytes)
    $script:Socket.SendAsync($segment, 'Text', $true, [Threading.CancellationToken]::None).Wait()

    # 応答以外（イベント）は読み捨てる。
    do { $message = Receive-Message | ConvertFrom-Json } while ($message.id -ne $script:MessageId)
    if ($message.result.exceptionDetails) {
        throw "JavaScript の実行に失敗しました: $($message.result.exceptionDetails.exception.description)"
    }
    return $message
}

function Invoke-Js([string]$Expression) {
    return (Invoke-Cdp 'Runtime.evaluate' @{ expression = $Expression; returnByValue = $true; userGesture = $true }).result.result.value
}

function Wait-Until([scriptblock]$Condition, [string]$Description, [int]$TimeoutSeconds = 10) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (& $Condition) { return }
        Start-Sleep -Milliseconds 200
    }
    throw "$Description が $TimeoutSeconds 秒以内に完了しませんでした。"
}

function Wait-Download([string]$Directory, [string]$Filter, [int]$TimeoutSeconds = 60) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $file = Get-ChildItem -LiteralPath $Directory -File -Filter $Filter | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($file -and $file.Length -gt 0) {
            Start-Sleep -Milliseconds 500
            if ((Get-Item -LiteralPath $file.FullName).Length -eq $file.Length) { return $file }
        }
        Start-Sleep -Milliseconds 500
    }
    throw "ダウンロードが $TimeoutSeconds 秒以内に完了しませんでした: $Directory\$Filter"
}

function Import-DelimitedCsv([string]$Path) {
    $header = Get-Content -LiteralPath $Path -TotalCount 1 -Encoding UTF8
    $delimiter = if ($header -match "`t") { "`t" } else { ',' }
    return @(Import-Csv -LiteralPath $Path -Delimiter $delimiter -Encoding UTF8)
}

function ConvertTo-SafeFileNamePart([string]$Value) {
    $safe = $Value.Trim() -replace '\s+', '_'
    foreach ($ch in [IO.Path]::GetInvalidFileNameChars()) { $safe = $safe.Replace([string]$ch, '_') }
    return $safe
}

# DOM操作用の共通JavaScript（固定列側の端末名セル、詳細パネル）
$DomPrelude = @'
const nameCellSelector = 'td[aria-describedby="asset-grid_asset_name"]';
const fixedRows = () => Array.from(document.querySelectorAll('#asset-grid_fixed tbody tr[data-id]')).filter(r => r.querySelector(nameCellSelector));
const panel = () => document.querySelector('#detail-panel');
const detailName = () => { const p = panel(); const el = p && !p.hidden && p.querySelector('[ng-bind="detail.item.name"]'); return el ? el.textContent.trim() : ''; };
'@

$run = New-Directory (Join-Path $Root (Get-Date -Format yyyyMMdd_HHmmss))
$tempDir = New-Directory "$run\installed_app_export_tmp"
$outDir = New-Directory "$run\installed_app_export_downloads"

$script:MessageId = 0
$script:Socket = Connect-Page $PageTitleLike
Invoke-Cdp 'Browser.setDownloadBehavior' @{ behavior = 'allow'; downloadPath = $tempDir } | Out-Null

# 1. 端末ごとにアプリ一覧CSVを取得する
Invoke-Js "document.querySelector('#asset-grid_scroll').scrollTop = 0" | Out-Null
$seen = @{}

for ($loop = 0; $loop -lt 500; $loop++) {
    $rows = @(Invoke-Js "(() => { $DomPrelude return fixedRows().map(r => ({ id: r.getAttribute('data-id'), name: r.querySelector(nameCellSelector).textContent.trim() })); })()")

    foreach ($row in $rows) {
        if ($seen.ContainsKey($row.id)) { continue }
        $seen[$row.id] = $true
        Get-ChildItem -LiteralPath $tempDir -Force | Remove-Item -Recurse -Force

        $idJson = $row.id | ConvertTo-Json
        $nameJson = $row.name | ConvertTo-Json
        Invoke-Js "(() => { $DomPrelude const cell = fixedRows().find(r => r.getAttribute('data-id') === $idJson).querySelector(nameCellSelector); cell.scrollIntoView({ block: 'center' }); cell.click(); return true; })()" | Out-Null
        Wait-Until { (Invoke-Js "(() => { $DomPrelude return detailName(); })()") -eq $row.name } "詳細パネルの表示（$($row.name)）"

        Invoke-Js "Array.from(document.querySelectorAll('#detail-panel nav button')).find(b => b.textContent.trim() === 'インストール済みアプリ').click()" | Out-Null
        Invoke-Js "(() => { $DomPrelude const p = panel(); const radio = p.querySelector('#app-list-radio'); if (!radio.checked) p.querySelector('label[for=""app-list-radio""]').click(); p.querySelector('div[data-download-url=""detail.csvUrl[\'app\']""] button').click(); return detailName() === $nameJson; })()" | Out-Null

        $file = Wait-Download $tempDir "$Prefix*.csv"
        $baseName = $file.BaseName -replace '\s\(\d+\)$', ''
        Move-Item -LiteralPath $file.FullName -Destination (Join-Path $outDir "$baseName`_$(ConvertTo-SafeFileNamePart $row.name)$($file.Extension)") -Force
        Write-Host "CSVを取得しました: $($row.name)"

        Invoke-Js "document.querySelector('#detail-panel .panel-close button.close-btn').click()" | Out-Null
        Start-Sleep -Milliseconds 300
    }

    $moved = Invoke-Js "(() => { const s = document.querySelector('#asset-grid_scroll'), before = s.scrollTop; s.scrollTop = before + Math.max(s.clientHeight * 0.75, 300); s.dispatchEvent(new Event('scroll')); return s.scrollTop !== before; })()"
    Start-Sleep -Milliseconds 500
    if ($moved -ne $true) { break }
}

# 2. 前月に導入されたアプリをまとめる
$from = (Get-Date -Day 1).Date.AddMonths(-1)
$to = $from.AddMonths(1)
$formats = [string[]]@('yyyy/MM/dd', 'yyyy/M/d', 'yyyy-MM-dd', 'yyyy-M-d', 'yyyy/MM/dd HH:mm:ss', 'yyyy-MM-dd HH:mm:ss')
$culture = [Globalization.CultureInfo]::GetCultureInfo('ja-JP')
$installations = @()
$skipped = 0

foreach ($file in Get-ChildItem -LiteralPath $outDir -Filter "$Prefix*.csv") {
    if ($file.Name -notmatch '^.+_(PCXX-\d{2}-\d{3})\.csv$') { continue }
    $assetName = $Matches[1]

    foreach ($row in Import-DelimitedCsv $file.FullName) {
        $installed = [datetime]::MinValue
        if (-not [datetime]::TryParseExact([string]$row.'導入日', $formats, $culture, 'None', [ref]$installed)) {
            $skipped++
            continue
        }
        if ($installed -ge $from -and $installed -lt $to) {
            $installations += [pscustomobject]@{
                '端末名' = $assetName
                'アプリ名' = $row.'アプリ名'
                'バージョン' = $row.'バージョン'
                '導入日' = $row.'導入日'
            }
        }
    }
}

$reportPath = Join-Path $outDir 'pc_installation.csv'
$installations | Export-Csv -LiteralPath $reportPath -NoTypeInformation -Encoding UTF8
Write-Host "前月（$($from.ToString('yyyy/MM'))）の導入: $($installations.Count)件 → $reportPath"
if ($skipped -gt 0) { Write-Warning "導入日が読めない行を $skipped 件スキップしました。" }
$script:Socket.Dispose()
