# modules/Foundation/internal/CdpSession.ps1

## 1. このファイルを一言でいうと

CDP接続の状態を保持する `Session` オブジェクトと、既定セッション `$script:CdpDefaultSession` を管理するファイルである。

CDPでは、WebSocket接続を開いた後、その接続上で複数の命令を送る。
そのため、接続状態、命令ID、タイムアウト秒数を保持する場所が必要になる。

## このファイルを変更する典型ケース

- CDP接続、command送受信、target探索、timeout方針が変わった場合
- Foundation公開サービスと低レベルCDP実装の境界が変わった場合
- CDPエラーや切断時の診断情報が変わった場合


## 2. このファイルが担当する範囲

```text
- 新しいCDPセッション状態を作る
- 既定セッションを保持する script スコープ変数を定義する
- セッションからコマンドタイムアウト秒数を取得する
- WebSocket初期化済みセッションか検査する
```

## 3. このファイルが担当しない範囲

```text
- 実際にWebSocketへ接続すること
- CDP命令を送信すること
- JavaScriptを実行すること
- 対象タブを選ぶこと
```

それらは `CdpConnection.ps1`、`CdpCommand.ps1`、`CdpBrowser.ps1` が担当する。

## 4. セッションの構造

`New-CDPSessionState` は次の形の `[pscustomobject]` を返す。

```text
CDPSession
  WebSocket               : 接続済みClientWebSocket。作成直後は null
  CancellationTokenSource : WebSocket操作を中断するためのトークン。作成直後は null
  Runtime                 : このセッションが使うRuntime
  CommandId               : CDP命令ID。初期値は 0
  CommandTimeoutSeconds   : CDP命令の標準タイムアウト秒数
  IsClosed                : Close済みかどうか。初期値は false
```

`Open-CDPConnection` がこのSessionに `WebSocket` と `CancellationTokenSource` を設定する。

## 5. `$script:CdpDefaultSession` とは何か

```text
$script:CdpDefaultSession = $null
```

これは Foundation モジュールスコープの既定CDPセッションである。

多くの関数は `-Session` を省略できる。
省略された場合、この既定セッションを使う。

```text
Invoke-CDPJS -Expression '1 + 1'
```

このように呼んでも、内部では `$script:CdpDefaultSession` を使ってCDP命令を送る。

## 6. 関数ごとの説明

### New-CDPSessionState

新しいセッション状態を作る。

入力:

```text
CommandTimeoutSeconds : CDP命令の標準タイムアウト。既定値は 30
Runtime               : このセッションで使うRuntime。null可
```

出力:

```text
CDPSession オブジェクト
```

作成直後はまだWebSocketに接続していない。
つまり、この関数は「接続済みセッション」ではなく「接続状態を入れる箱」を作る。

### Get-CDPCommandTimeoutSeconds

CDP命令のタイムアウト秒数を返す。

入力:

```text
Session : 省略時は $script:CdpDefaultSession
```

戻り値:

```text
Session.CommandTimeoutSeconds があればその値
なければ 30
```

この関数により、`Invoke-CDPJS` や `Send-CDPCommand` は `-TimeoutSeconds` が省略されても、セッションの既定タイムアウトを使える。

### Assert-CDPSession

CDP命令を送れる状態か確認する。

条件:

```text
Session が存在する
かつ
Session.WebSocket が存在する
```

失敗時:

```text
CDP WebSocket が初期化されていません。
```

このチェックがないと、WebSocket未接続のまま `SendAsync` / `ReceiveAsync` に進み、より分かりにくいエラーになる。

## 7. 処理上の位置づけ

```text
Open-CDPConnection
  ├─ New-CDPSessionState
  ├─ Session.WebSocket を設定
  ├─ Session.CancellationTokenSource を設定
  ├─ $script:CdpDefaultSession に設定
  └─ Transport.Connect

Send-CDPCommand
  ├─ Assert-CDPSession
  ├─ Session.CommandId++
  └─ 送信・受信

Close-CDPConnection
  ├─ Transport.Close
  ├─ Transport.Dispose
  ├─ Session.IsClosed = true
  └─ 既定セッションなら $script:CdpDefaultSession = null
```

## 8. PowerShell文法上のポイント

### `$script:` スコープ

`$script:CdpDefaultSession` は、ファイル単体の変数ではなく、Foundation モジュールの script スコープ変数である。
同じモジュール内に dot-source された他の `.ps1` からも参照できる。

この仕組みにより、`CdpCommand.ps1` の関数も既定セッションを使える。

### 省略可能な引数と既定値

```text
[object]$Session = $script:CdpDefaultSession
```

この書き方により、呼び出し側が `-Session` を渡さない場合、既定セッションが使われる。

## 9. 変更時の判断基準

```text
- Sessionのプロパティ名を変える場合、CdpConnection / CdpCommand / CdpTransport も同時に変更する
- CommandId の初期値を 0 以外に変えると、最初のCDP命令IDが変わる
- Assert-CDPSession を弱めると、未接続状態でのエラー診断が悪くなる
- $script:CdpDefaultSession を削る場合、既存の上位APIの省略呼び出しをすべて見直す必要がある
```

## 10. 関連テスト

```text
tests/Foundation.CdpInternals.Tests.ps1
```

セッション初期値、既定タイムアウト、未初期化WebSocketの拒否が検証されている。
