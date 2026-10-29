param(
    [int]$Port = 8080
)

$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

# ============================================================
# Mock server
#   site\ 配下の静的ファイルを http://localhost:<Port>/ で配信する。
#   自動化ジョブの動作確認用。外部ネットワークには公開しない。
# ============================================================

$SiteRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'site')).Path.TrimEnd('\')

$ContentTypes = @{
    '.html' = 'text/html; charset=utf-8'
    '.js'   = 'text/javascript; charset=utf-8'
    '.css'  = 'text/css; charset=utf-8'
    '.svg'  = 'image/svg+xml'
    '.json' = 'application/json; charset=utf-8'
    '.ico'  = 'image/x-icon'
}

function Resolve-MockRequestPath {
    param(
        [Parameter(Mandatory)][string]$UrlPath
    )

    $relative = [Uri]::UnescapeDataString($UrlPath).TrimStart('/') -replace '/', '\'
    $fullPath = [IO.Path]::GetFullPath((Join-Path $SiteRoot $relative))

    # site\ の外を指すパスは配信しない。
    if ($fullPath -ne $SiteRoot -and -not $fullPath.StartsWith($SiteRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        return [pscustomobject]@{ Kind = 'NotFound'; Path = $null }
    }

    if (Test-Path -LiteralPath $fullPath -PathType Container) {
        # 相対パスの css/js を正しく解決させるため、ディレクトリは末尾スラッシュ付きURLに揃える。
        if (-not $UrlPath.EndsWith('/')) {
            return [pscustomobject]@{ Kind = 'Redirect'; Path = $UrlPath + '/' }
        }

        $fullPath = Join-Path $fullPath 'index.html'
    }

    if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
        return [pscustomobject]@{ Kind = 'File'; Path = $fullPath }
    }

    return [pscustomobject]@{ Kind = 'NotFound'; Path = $null }
}

function Send-MockResponse {
    param(
        [Parameter(Mandatory)]$Context
    )

    $request = $Context.Request
    $response = $Context.Response
    $response.Headers['Cache-Control'] = 'no-store'

    try {
        $resolved = Resolve-MockRequestPath -UrlPath $request.Url.AbsolutePath

        switch ($resolved.Kind) {
            'Redirect' {
                $response.StatusCode = 301
                $response.RedirectLocation = $resolved.Path
            }
            'File' {
                $extension = [IO.Path]::GetExtension($resolved.Path).ToLowerInvariant()
                $contentType = $ContentTypes[$extension]
                if (-not $contentType) { $contentType = 'application/octet-stream' }

                $bytes = [IO.File]::ReadAllBytes($resolved.Path)
                $response.StatusCode = 200
                $response.ContentType = $contentType
                $response.ContentLength64 = $bytes.Length
                $response.OutputStream.Write($bytes, 0, $bytes.Length)
            }
            default {
                $bytes = [Text.Encoding]::UTF8.GetBytes('404 Not Found')
                $response.StatusCode = 404
                $response.ContentType = 'text/plain; charset=utf-8'
                $response.ContentLength64 = $bytes.Length
                $response.OutputStream.Write($bytes, 0, $bytes.Length)
            }
        }
    }
    catch {
        $response.StatusCode = 500
        Write-Warning "応答の生成に失敗しました: $($_.Exception.Message)"
    }
    finally {
        Write-Host ("{0} {1} {2}" -f $response.StatusCode, $request.HttpMethod, $request.Url.AbsolutePath)
        $response.Close()
    }
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")

try {
    $listener.Start()
}
catch {
    throw "ポート $Port で待ち受けできません。別のプロセスが使用していないか確認してください。詳細: $($_.Exception.Message)"
}

Write-Host "Mock server: http://localhost:$Port/"
Write-Host "  ExampleSecurity : http://localhost:$Port/example-security/"
Write-Host "  ExampleAsset    : http://localhost:$Port/example-asset/"
Write-Host "停止するには Ctrl+C を押してください。"

try {
    while ($listener.IsListening) {
        # GetContext() で待つと Ctrl+C が効かないため、短い間隔で待機を区切る。
        $pending = $listener.GetContextAsync()
        while (-not $pending.AsyncWaitHandle.WaitOne(500)) { }
        Send-MockResponse -Context $pending.GetAwaiter().GetResult()
    }
}
finally {
    $listener.Stop()
    $listener.Close()
}
