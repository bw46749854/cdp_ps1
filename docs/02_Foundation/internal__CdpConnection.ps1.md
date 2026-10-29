# modules/Foundation/internal/CdpConnection.ps1

## 1. このファイルを一言でいうと

WebSocket接続の開始、待機、タイムアウト時の中断、クローズを担当するファイルである。

CDP命令の内容は扱わない。
ここでは「WebSocket接続をどう開き、どう閉じるか」に責務を限定している。

## このファイルを変更する典型ケース

- CDP接続、command送受信、target探索、timeout方針が変わった場合
- Foundation公開サービスと低レベルCDP実装の境界が変わった場合
- CDPエラーや切断時の診断情報が変わった場合


## 2. このファイルが担当する範囲

```text
- WebSocket接続を開く
- 接続処理や送受信Taskをタイムアウト付きで待つ
- 期限切れ時にTransport.Abortを呼ぶ
- WebSocketを閉じてDisposeする
- 既定セッションをクリアする
```

## 3. このファイルが担当しない範囲

```text
- CDP JSON payload を作る
- Runtime.evaluate を送る
- pageターゲットを選ぶ
- DOM helperを呼ぶ
```

## 4. 関数呼び出しツリー

```text
Open-CDPConnection
  ├─ Resolve-CDPRuntime
  ├─ Close-CDPConnection -Quiet
  ├─ New-CDPSessionState
  ├─ Runtime.Transport.NewWebSocket
  ├─ Runtime.Transport.NewCancellationTokenSource
  ├─ $script:CdpDefaultSession = $session
  └─ Runtime.Transport.Connect
       └─ Wait-CDPTask

Close-CDPConnection
  ├─ Resolve-CDPRuntime
  ├─ Runtime.Transport.Close
  │    └─ Wait-CDPTask
  ├─ Runtime.Transport.Dispose
  ├─ Session.IsClosed = true
  └─ 既定セッションなら $script:CdpDefaultSession = null
```

## 5. 関数ごとの説明

### Stop-CDPConnectionDueToTimeout

タイムアウト発生時にCDP接続を中断する。

入力:

```text
Session : 中断対象のCDPセッション
Runtime : 明示Runtime。省略可能
```

処理:

```text
Resolve-CDPRuntime
  ↓
Runtime.Transport.Abort を取得
  ↓
Abort(Session) を実行
```

この関数は、タイムアウト時の後始末を一箇所に寄せている。
Abort の中では `CancellationTokenSource.Cancel()` と `WebSocket.Abort()` が行われる。

### Wait-CDPTask

.NET の非同期 `Task` をタイムアウト付きで待つ。

入力:

```text
Task                : 待機対象の .NET Task
TimeoutMilliseconds : 待機上限ミリ秒
Description         : エラー説明用の文脈
Session             : timeout時にAbortするセッション
Runtime             : Transport解決用
```

処理:

```text
Task.Wait(TimeoutMilliseconds)
  ├─ 完了した → 正常終了
  ├─ AggregateException → inner exception を読みやすいメッセージでthrow
  ├─ その他例外 → CDP処理失敗としてthrow
  └─ 完了しない → Stop-CDPConnectionDueToTimeout → timeout例外
```

`TimeoutMilliseconds` が 0 以下なら 1 に丸める。
これは `Task.Wait(0)` のような即時失敗を避け、異常系でも少なくとも待機処理を通すためである。

### Get-RemainingMilliseconds

期限時刻までの残りミリ秒を返す。

入力:

```text
Deadline : 期限時刻
Runtime  : Now取得用Runtime
```

戻り値:

```text
1以上 : 残りミリ秒
0     : 期限切れ
```

`Timing.Now` を使うため、テストでは時刻を偽物に差し替えられる。

### Open-CDPConnection

WebSocket URL に接続し、CDP Session を返す。

入力:

```text
WebSocketUrl           : pageターゲットの webSocketDebuggerUrl
ConnectTimeoutSeconds : 接続タイムアウト
CommandTimeoutSeconds : 後続CDP命令の標準タイムアウト
Runtime                : Transport差し替え用Runtime
```

出力:

```text
CDPSession
```

重要な処理順:

```text
1. Runtimeを解決する
2. 既存の既定接続を Close-CDPConnection -Quiet で閉じる
3. 新しい Session を作る
4. WebSocket と CancellationTokenSource を作る
5. $script:CdpDefaultSession に登録する
6. Transport.Connect で接続する
7. Session を返す
```

既存接続を先に閉じる理由は、既定セッションが複数残ることを避けるためである。

### Close-CDPConnection

CDP接続を閉じ、リソースを破棄する。

入力:

```text
Session : 閉じるセッション。省略時は既定セッション
Quiet   : Close失敗時に警告を出さない
Runtime : 明示Runtime
```

処理:

```text
Session が null → 何もしない
WebSocket がある → Close を試みる → Dispose
WebSocket がなくても CancellationTokenSource がある → Dispose
Session.IsClosed = true
既定セッションなら $script:CdpDefaultSession = null
```

Closeに失敗してもDisposeは実行される。
これは、正常クローズに失敗してもリソース破棄は必要だからである。

## 6. PowerShell文法上のポイント

### `catch [System.AggregateException]`

.NET の非同期Taskは、内部例外を `AggregateException` として包むことがある。
このファイルでは `InnerException` を取り出して、原因が分かるメッセージにしている。

### `[switch]$Quiet`

`Quiet` は真偽値のスイッチ引数である。

```text
Close-CDPConnection -Quiet
```

と呼ぶと `$Quiet` が true になる。
Close失敗時に警告を出したくない場面で使う。

## 7. 失敗条件と意味

| 失敗 | 意味 |
|---|---|
| 接続Taskがtimeout | ブラウザ/CDPポート/対象タブへの接続が完了しなかった |
| 送受信Taskがtimeout | CDP処理が応答しなかった |
| Close失敗 | WebSocket正常クローズには失敗したが、Disposeは続行する |
| Sessionなし | Closeでは何もしない。Send側では `Assert-CDPSession` が落とす |

## 8. 変更時の判断基準

```text
- Timeout時の Stop-CDPConnectionDueToTimeout を削らない
- Close失敗時にも Dispose する挙動を維持する
- Open-CDPConnection で既存セッションを閉じる処理を削る場合、既定セッションの多重管理を設計し直す
- Get-RemainingMilliseconds を直接 Get-Date 依存に戻すと、時刻差し替えテストが弱くなる
```

## 9. 関連テスト

```text
tests/Foundation.CdpInternals.Tests.ps1
tests/Foundation.CdpTransport.Errors.Tests.ps1
```

接続作成、タイムアウトAbort、Close失敗時の警告とDispose、CancellationTokenSource単独Disposeが検証されている。
