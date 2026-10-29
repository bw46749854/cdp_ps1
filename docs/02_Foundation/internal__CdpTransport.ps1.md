# modules/Foundation/internal/CdpTransport.ps1

## 1. このファイルを一言でいうと

CDP通信で使う外部依存を、差し替え可能な `Runtime` オブジェクトとしてまとめるファイルである。

ここでいう外部依存とは、次のようなものを指す。

```text
- WebSocket の作成、接続、送信、受信、クローズ
- HTTP GET
- コンソール出力
- 現在時刻の取得
- Sleep
```

これらは本番実行では .NET や PowerShell の実機能を使う。
テストでは偽物の scriptblock に差し替える。

## このファイルを変更する典型ケース

- CDP接続、command送受信、target探索、timeout方針が変わった場合
- Foundation公開サービスと低レベルCDP実装の境界が変わった場合
- CDPエラーや切断時の診断情報が変わった場合


## 2. このファイルが担当する範囲

```text
- CDP Runtime の生成
- Runtime が満たすべき契約チェック
- Transport / HttpClient / Console / Timing の既定実装作成
- scriptblock Port の取り出し
- Session や明示Runtimeから使用Runtimeを解決する
```

## 3. このファイルが担当しない範囲

```text
- どのCDP methodを送るか
- JavaScript式をどう組み立てるか
- どのタブを対象にするか
- DOM helperをどう呼ぶか
- Feature moduleの業務判断
```

それらは `CdpCommand.ps1`、`CdpBrowser.ps1`、`DomHelper.ps1`、各Feature module側の責務である。

## 4. Runtime の構造

`New-CDPRuntime` は次の形の `[pscustomobject]` を返す。

```text
CDPRuntime
  Transport
    NewWebSocket
    NewCancellationTokenSource
    Connect
    SendText
    ReceiveText
    Close
    Abort
    Dispose
  HttpClient
    GetContent
  Console
    WriteLine
    WriteWarning
  Timing
    Now
    SleepMilliseconds
```

すべての末端プロパティは `scriptblock` である。
そのため、呼び出し時は `& $callback ...` の形で実行する。

## 5. 処理の流れ

```text
New-CDPRuntime
  ├─ Transport未指定なら New-CDPWebSocketTransport
  ├─ HttpClient未指定なら New-CDPHttpClientPort
  ├─ Console未指定なら New-CDPConsolePort
  ├─ Timing未指定なら New-CDPTimingPort
  ├─ Runtimeオブジェクトを作る
  ├─ Assert-CDPRuntimeContract
  └─ Runtimeを返す
```

`Resolve-CDPRuntime` は、明示的に渡された Runtime、Session に入っている Runtime、新規作成 Runtime の順で解決する。

```text
Resolve-CDPRuntime
  ├─ -Runtime がある → それを使う
  ├─ Session.Runtime がある → それを使う
  └─ どちらもない → New-CDPRuntime
```

## 6. 関数ごとの説明

### Get-CDPCallbackScriptBlock

指定したオブジェクトから scriptblock プロパティを取り出す。

入力:

```text
Owner     : Runtime.Transport などの親オブジェクト
Name      : 取り出したいプロパティ名
OwnerName : エラー表示用の名前
```

出力:

```text
scriptblock
```

失敗条件:

```text
- Owner が null
- Owner.Name が scriptblock ではない
```

この関数が重要なのは、Runtime契約違反を早い段階で検出するためである。
`SendText` が存在しない、または文字列になっているような状態で通信処理に進むと、失敗箇所が分かりにくくなる。

### New-CDPWebSocketTransport

本番用の WebSocket Transport を作る。

主な scriptblock:

| scriptblock | 内容 |
|---|---|
| `NewWebSocket` | `System.Net.WebSockets.ClientWebSocket` を作る |
| `NewCancellationTokenSource` | `CancellationTokenSource` を作る |
| `Connect` | `ConnectAsync` でWebSocket接続する |
| `SendText` | UTF-8文字列をWebSocketへ送信する |
| `ReceiveText` | WebSocketから1メッセージ分の文字列を受信する |
| `Close` | 正常クローズを試みる |
| `Abort` | timeout時などに接続を強制中断する |
| `Dispose` | WebSocketとCancellationTokenSourceを破棄する |

副作用:

```text
- WebSocket接続を作る
- WebSocketへ送信する
- WebSocketから受信する
- セッション上の WebSocket / CancellationTokenSource を null に戻す
```

注意点:

`ReceiveText` は、1回の `ReceiveAsync` で全文が返るとは限らない。
そのため `EndOfMessage` が true になるまで `MemoryStream` に追記する。
ここを単発受信にすると、大きなCDP応答が途中で切れる可能性がある。

### New-CDPHttpClientPort

DebuggerUrl からタブ一覧JSONを取得するためのHTTP Portを作る。

本番では `Invoke-WebRequest -UseBasicParsing -TimeoutSec` を使う。

このPortがあるため、テストでは実ブラウザを起動しなくても、任意のJSON文字列を返せる。

### New-CDPConsolePort

診断出力用の Console Port を作る。

```text
WriteLine    → Write-Host
WriteWarning → Write-Warning
```

このPortを差し替えると、テストで「どんな警告が出たか」を捕捉できる。

### New-CDPTimingPort

時刻とSleepの Port を作る。

```text
Now               → Get-Date
SleepMilliseconds → Start-Sleep -Milliseconds
```

このPortを差し替えると、テストで実際に待たずにタイムアウト処理を検証できる。

### Assert-CDPRuntimeContract

Runtime が必要な scriptblock をすべて持っているか確認する。

検査対象:

```text
Transport.NewWebSocket
Transport.NewCancellationTokenSource
Transport.Connect
Transport.SendText
Transport.ReceiveText
Transport.Close
Transport.Abort
Transport.Dispose
HttpClient.GetContent
Console.WriteLine
Console.WriteWarning
Timing.Now
Timing.SleepMilliseconds
```

変更時の注意:

新しい Port を追加した場合、この契約チェックにも追加する。
追加しないと、Runtimeが不完全でも起動時に検出できない。

### Resolve-CDPRuntime

使用する Runtime を決める。

入力:

```text
Runtime : 明示指定されたRuntime
Session : 既存CDPセッション
```

戻り値:

```text
使用するCDPRuntime
```

選択順:

```text
1. 明示的な Runtime
2. Session.Runtime
3. New-CDPRuntime による既定Runtime
```

## 7. PowerShell文法上のポイント

### scriptblockプロパティ

このファイルでは、オブジェクトのプロパティに `{ ... }` を入れている。

```text
Transport.SendText = { param(...) ... }
```

これは「関数のように呼び出せる値」である。
実行するときは `&` を使う。

```text
& $sendText $Session $payload $timeout $description
```

### `[pscustomobject]@{ ... }`

PowerShellで簡易的なオブジェクトを作る構文である。
このプロジェクトでは、クラス定義の代わりに、名前付きプロパティを持つオブジェクトとして使っている。

## 8. 変更時の判断基準

```text
- Transportのscriptblock名を変更する場合、Assert-CDPRuntimeContract と全呼び出し元も同時に変更する
- ReceiveText の分割受信処理を削らない
- Timeout時の Abort を握り潰さない
- Disposeで Session.WebSocket / Session.CancellationTokenSource を null に戻す挙動を維持する
- Timing Portを直接 Get-Date / Start-Sleep 呼び出しに戻すと、タイムアウト系テストが弱くなる
```

## 9. 関連テスト

```text
tests/Foundation.CdpInternals.Tests.ps1
tests/Foundation.CdpTransport.Errors.Tests.ps1
```

特に、Runtime契約不足、Transport差し替え、タイムアウト、Close失敗時のDisposeが検証されている。
