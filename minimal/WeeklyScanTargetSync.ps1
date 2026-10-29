param(
    [int]$Port = 9222,
    [string]$Root = "$PSScriptRoot\weekly",
    [int]$Days = 7,
    [string]$PageTitleLike = 'センサー*'
)

$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

# ============================================================
# 最小構成版 WeeklyScanTargetSync
#   main/ のモジュールを使わず、1ファイルで同じ流れを実行する。
#   1. 「操作」→「CSV出力」でデバイス一覧CSVを取得する
#   2. CSVの日付から、手動スキャン対象（ON/OFF）を判定する
#   3. 一覧を上からスクロールし、各行のチェックを判定に揃える
#   DOM契約の検証や失敗一覧CSVの出力は行わない。
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

function ConvertTo-DateOrNull([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value.Trim() -eq '-') { return $null }
    $parsed = [datetime]::MinValue
    if ([datetime]::TryParse($Value.Trim(), [ref]$parsed)) { return $parsed.Date }
    throw "日付として解釈できません: $Value"
}

# DOM操作用の共通JavaScript（一覧の行、セル、スクロール領域の取得）
$DomPrelude = @'
const rowSelector = '[class*="DataTable__row"]';
const cellsOf = row => Array.from(row.children).filter(c => /DataTable__(cell|header)/.test(String(c.className)));
const tableRoot = () => Array.from(document.querySelectorAll('[class*="DataTable__fixed-left"]')).find(x => x.querySelector(rowSelector)) || document;
const dataRows = () => Array.from(tableRoot().querySelectorAll(rowSelector)).filter(r => r.hasAttribute('data-id'));
const hostOf = row => (cellsOf(row)[1].textContent || '').trim();
const isOn = row => cellsOf(row)[0].querySelector('input[type="checkbox"]').checked || row.getAttribute('aria-selected') === 'true';
const scroller = () => Array.from(document.querySelectorAll('div, main, section'))
    .filter(e => e.querySelector(rowSelector) && e.scrollHeight > e.clientHeight + 50)
    .sort((a, b) => (b.scrollHeight - b.clientHeight) - (a.scrollHeight - a.clientHeight))[0] || document.scrollingElement;
'@

$run = New-Directory (Join-Path $Root (Get-Date -Format yyyyMMdd_HHmmss))
$tempDir = New-Directory "$run\device_list_export_tmp"
$outDir = New-Directory "$run\device_list_export_downloads"

$script:MessageId = 0
$script:Socket = Connect-Page $PageTitleLike
Invoke-Cdp 'Browser.setDownloadBehavior' @{ behavior = 'allow'; downloadPath = $tempDir } | Out-Null

# 1. デバイス一覧CSVを取得する
Invoke-Js "Array.from(document.querySelectorAll('button[aria-haspopup]')).find(b => b.textContent.trim() === '操作').click()" | Out-Null
Start-Sleep -Milliseconds 500
Invoke-Js "Array.from(document.querySelectorAll('[role=""menuitem""]')).find(x => x.textContent.trim() === 'CSV出力').click()" | Out-Null
$downloaded = Wait-Download $tempDir '*.csv'
$csvPath = Join-Path $outDir ('sensor_devices_{0}.csv' -f (Get-Date -Format MMdd))
Move-Item -LiteralPath $downloaded.FullName -Destination $csvPath -Force
Write-Host "CSVを取得しました: $csvPath"

# 2. 手動スキャン対象を判定する（完了日なし、または最終通信日時との差が $Days 日以上なら ON）
$desired = @{}
foreach ($row in Import-DelimitedCsv $csvPath) {
    $completed = ConvertTo-DateOrNull $row.'手動スキャンの完了'
    $lastSeen = ConvertTo-DateOrNull $row.'最終通信日時'
    $desired[$row.'ホスト名'.Trim()] = ($null -eq $completed) -or ($null -ne $lastSeen -and ($lastSeen - $completed).Days -ge $Days)
}
$onCount = @($desired.Values | Where-Object { $_ }).Count
Write-Host "判定: $($desired.Count)件（ON $($onCount)件 / OFF $($desired.Count - $onCount)件）"

# 3. 一覧を走査してチェックを揃える
Invoke-Js "(() => { $DomPrelude const s = scroller(); s.scrollTop = 0; s.dispatchEvent(new Event('scroll')); return true; })()" | Out-Null
Start-Sleep -Milliseconds 500
$done = @{}
$changed = 0

for ($loop = 0; $loop -lt 500 -and $done.Count -lt $desired.Count; $loop++) {
    $visible = @(Invoke-Js "(() => { $DomPrelude return dataRows().map(r => ({ host: hostOf(r), on: isOn(r) })); })()")

    foreach ($item in $visible) {
        if (-not $desired.ContainsKey($item.host) -or $done.ContainsKey($item.host)) { continue }
        $done[$item.host] = $true
        if ([bool]$item.on -eq $desired[$item.host]) { continue }

        $hostJson = $item.host | ConvertTo-Json
        Invoke-Js "(() => { $DomPrelude const row = dataRows().find(r => hostOf(r) === $hostJson); cellsOf(row)[0].querySelector('label').click(); return true; })()" | Out-Null
        $changed++
        Start-Sleep -Milliseconds 350
    }

    $moved = Invoke-Js "(() => { $DomPrelude const s = scroller(), before = s.scrollTop; s.scrollTop = before + Math.max(s.clientHeight * 0.75, 300); s.dispatchEvent(new Event('scroll')); return s.scrollTop !== before; })()"
    Start-Sleep -Milliseconds 600
    if ($moved -ne $true) { break }
}

Write-Host "チェック整合: $($done.Count)/$($desired.Count)件確認、$($changed)件を変更しました。"
if ($done.Count -lt $desired.Count) {
    Write-Warning "一覧で見つからなかった端末があります: $(@($desired.Keys | Where-Object { -not $done.ContainsKey($_) }) -join ', ')"
}
$script:Socket.Dispose()
