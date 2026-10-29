# CDP低レベル通信層の読み方

## 1. この領域を一言でいうと

この領域は、PowerShell からブラウザに接続し、JavaScript を実行し、ダウンロード先を設定するための通信基盤である。

Feature module から見ると、低レベル通信層は直接触らない対象である。
InstalledAppExport や ScanTargetSync が使うのは、基本的には次のような上位関数である。

```text
Open-FoundationPage
Open-FoundationPageMatchingIdentity
Invoke-FoundationJavaScript
Wait-FoundationJavaScript
Set-FoundationDownloadDirectory
Invoke-FoundationDomHelperMethod
Wait-FoundationDomHelperMethod
```

CDP系ファイルは、これらの上位関数の裏側で使われる。

## 2. CDPとは何か

CDP は Chrome DevTools Protocol の略である。
Chrome / Edge の開発者ツールが内部的に使うプロトコルで、ブラウザ外部のプログラムから次のような操作ができる。

```text
- 開いているタブ一覧を取得する
- 特定タブに WebSocket 接続する
- タブ上で JavaScript を実行する
- JavaScript の戻り値を受け取る
- ダウンロード先を指定する
```

このプロジェクトでは Selenium のように WebDriver を使うのではなく、CDP を直接使ってブラウザを操作する。

## 3. ブラウザに接続するまでの流れ

```text
Open-FoundationPageMatchingIdentity
  ↓
Get-TargetPageWebSocketUrlMatchingIdentity
  ↓
DebuggerUrl に HTTP GET
  例: http://localhost:9222/json
  ↓
開いているタブ情報の JSON を取得
  ↓
page ターゲットだけを抽出
  ↓
Feature 側の PageIdentityMatcher で対象タブを判定
  ↓
対象タブの webSocketDebuggerUrl を取得
  ↓
Open-CDPConnection
  ↓
ClientWebSocket.ConnectAsync
  ↓
CdpSession を返す
```

`DebuggerUrl` はブラウザ全体のデバッグ用HTTPエンドポイントである。そこから取得する `webSocketDebuggerUrl` は、個別タブに対する WebSocket 接続先である。

この2つは別物である。

| 名前 | 役割 |
|---|---|
| `DebuggerUrl` | 開いているタブ一覧を取得するHTTP URL |
| `webSocketDebuggerUrl` | 個別タブへCDP命令を送るWebSocket URL |

## 4. なぜ PageIdentityMatcher が必要か

以前の単純な実装では、操作可能な page ターゲットが1つだけであることを前提にできる。
しかし実際には、ブラウザで複数タブが開いていることがある。

複数タブの中から誤ったタブを操作すると、画面クリックやCSV出力が別ページに対して実行される危険がある。
そのため、このプロジェクトでは Feature 側が「このジョブの対象画面かどうか」を判定する `PageIdentityMatcher` を渡せる。

```text
複数タブ
  ├─ ExampleAssetサイトのInstalledAppExport画面 → matched
  ├─ 関係ないタブ → not matched
  └─ DevToolsや拡張機能 → 候補から除外
```

一致するタブが0件なら停止する。
一致するタブが2件以上でも停止する。
一致するタブが1件だけのときだけ処理を続行する。

## 5. CDP命令の送信と応答の対応

CDPの命令は JSON で送る。

```text
{
  "id": 1,
  "method": "Runtime.evaluate",
  "params": {
    "expression": "1 + 1"
  }
}
```

応答にも同じ `id` が返る。

```text
{
  "id": 1,
  "result": {
    "result": {
      "value": 2
    }
  }
}
```

`CdpCommand.ps1` は、送った命令の `id` と応答の `id` が一致するまで受信を続ける。
CDPではイベント通知も同じWebSocketに流れてくるため、`id` を持たないイベントや別IDの応答は無視する。

## 6. タイムアウト時に接続をAbortする理由

CDP通信では、WebSocket受信や送信が戻ってこないことがある。
このとき単に例外を投げるだけでは、裏側の非同期処理が残る可能性がある。

このプロジェクトでは、タイムアウト時に次を実行する。

```text
CancellationTokenSource.Cancel()
WebSocket.Abort()
```

これにより、待ち続けているWebSocket処理を強制的に止める。

## 7. Runtime / Transport / Session の関係

```text
Runtime
  Transport : WebSocket作成、接続、送信、受信、Close、Abort、Dispose
  HttpClient: DebuggerUrl からタブ一覧JSONを取得
  Console   : 診断メッセージや警告の出力
  Timing    : 現在時刻取得、Sleep

Session
  WebSocket                 : 接続済みWebSocket
  CancellationTokenSource   : 接続や受信を中断するためのトークン
  Runtime                   : このSessionが使うRuntime
  CommandId                 : 次のCDP命令ID
  CommandTimeoutSeconds     : CDP命令の標準タイムアウト
  IsClosed                  : Close済みかどうか
```

Runtime は「外部環境に依存する処理を束ねたもの」である。
Session は「今つながっているCDP接続の状態」である。

## 8. scriptblock Port が使われている理由

`CdpTransport.ps1` では、WebSocket処理を直接関数呼び出しするのではなく、`[pscustomobject]` のプロパティに scriptblock を入れている。

```text
Runtime.Transport.SendText
Runtime.Transport.ReceiveText
Runtime.HttpClient.GetContent
Runtime.Timing.Now
```

これにより、テストでは本物のWebSocketを使わずに、偽物の Transport を注入できる。

この分離があるため、次のようなテストが可能になる。

```text
- malformed JSON を返す
- CDP error 応答を返す
- id が違う応答を先に返す
- ReceiveText が null を返す
- Close が失敗する
- 時刻を意図的に進めてタイムアウトさせる
```

## 9. この領域を変更するときの原則

```text
- Feature module から CdpTransport / CdpCommand を直接呼ばせない
- DOM操作名や業務判断をCDP層に入れない
- WebSocketの具象処理を CdpCommand.ps1 に混ぜない
- タイムアウト時の Abort を削らない
- Close失敗時にも Dispose する挙動を壊さない
- CDP応答の id 照合を削らない
- 複数タブを曖昧なまま選ばない
```

この領域は低レベルだが、目的は単純である。

```text
PowerShellから、正しいブラウザタブに、安全に、期限付きで、JavaScript命令を送る。
```
