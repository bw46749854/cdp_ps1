# modules/Foundation/internal/CdpCommand.ps1

## 1. このファイルを一言でいうと

CDP命令の JSON を作り、WebSocketへ送信し、対応する応答を受け取り、JavaScript実行や待機を提供するファイルである。

通信の接続・切断そのものは `CdpConnection.ps1` が担当する。
このファイルは「接続済みCDPセッションに対して、どんな命令を送るか」を担当する。

## このファイルを変更する典型ケース

- CDP接続、command送受信、target探索、timeout方針が変わった場合
- Foundation公開サービスと低レベルCDP実装の境界が変わった場合
- CDPエラーや切断時の診断情報が変わった場合


## 2. このファイルが担当する範囲

```text
- CDP command request JSON の作成
- CDP response JSON の解析
- command id による応答対応
- CDP error 応答の例外化
- Runtime.evaluate による JavaScript 実行
- JavaScript条件のポーリング待機
- DOM contract 結果のポーリング待機
```

## 3. このファイルが担当しない範囲

```text
- WebSocket接続を開くこと
- 対象タブの選択
- DOM helper JavaScript の中身
- Feature module の業務判断
```

## 4. CDP command の基本形

`New-CDPCommandRequest` は次の形のJSONを作る。

```text
{
  "id": 1,
  "method": "Runtime.evaluate",
  "params": {
    "expression": "..."
  }
}
```

`id` はセッションごとに増える。
`Send-CDPCommand` は、同じ `id` を持つ応答が返るまで受信を続ける。

## 5. 関数呼び出しツリー

```text
Invoke-CDPJS
  └─ Send-CDPCommand
      ├─ Assert-CDPSession
      ├─ Resolve-CDPRuntime
      ├─ New-CDPCommandRequest
      ├─ Runtime.Transport.SendText
      ├─ Receive-CDPMessage
      │    └─ Runtime.Transport.ReceiveText
      ├─ ConvertFrom-CDPMessageJson
      ├─ Test-CDPResponseMatchesCommandId
      └─ Assert-CDPCommandSucceeded

Wait-CDPJS
  ├─ Invoke-CDPJS を繰り返す
  ├─ true なら終了
  ├─ 一時的なJSエラーは保持してリトライ
  └─ 期限切れで timeout 例外

Wait-DomContractResult
  ├─ Invoke-CDPJS を繰り返す
  ├─ fatalCount = 0 なら終了
  ├─ 直近のcontract結果を保持
  └─ timeout時に Format-DomContractResult 付きで例外
```

## 6. 関数ごとの説明

### New-CDPCommandRequest

CDP命令のJSON文字列を作る。

入力:

```text
Id     : CDP命令ID
Method : CDP method名
Params : methodに渡すパラメータ
```

出力:

```text
圧縮済みJSON文字列
```

`ConvertTo-Json -Compress -Depth 30` を使う。
`-Depth 30` は、ネストしたパラメータが途中で省略されるのを防ぐためである。

### ConvertFrom-CDPMessageJson

CDP応答文字列をJSONとして解析する。

失敗時には、どの処理中のJSON解析に失敗したのかが分かるよう、`Description` を含めて例外を投げる。

### Test-CDPResponseMatchesCommandId

受信したCDPメッセージが、現在待っている命令IDに対応するか判定する。

CDPでは次のようなメッセージも流れてくる。

```text
- Runtime.consoleAPICalled のようなイベント
- 以前または別の命令への応答
```

そのため、単に「最初に受信したメッセージ」を応答として扱ってはいけない。

### Assert-CDPCommandSucceeded

CDP応答に `error` があれば例外にする。

例外メッセージには次を含める。

```text
method
id
CDP error message
```

これにより、どの命令が失敗したか追跡しやすくなる。

### Receive-CDPMessage

Transport経由でWebSocketから1メッセージを受信する。

入力:

```text
TimeoutMilliseconds
Description
Session
Runtime
```

出力:

```text
受信した文字列
または WebSocket close 時の null
```

### Send-CDPCommand

このファイルの中核関数である。

処理:

```text
1. Session が有効か確認する
2. Runtime を解決する
3. TimeoutSeconds が未指定なら Session の既定値を使う
4. Session.CommandId をインクリメントする
5. deadline を決める
6. command JSON を作る
7. 残り時間内に送信する
8. 応答を受信し続ける
9. JSONに変換する
10. id が一致しないメッセージは無視する
11. id が一致したら error を確認して返す
```

失敗条件:

```text
- 送信前に期限切れ
- 送信Task timeout
- 受信Task timeout
- WebSocketが閉じられた
- 応答JSONが壊れている
- CDP error 応答が返った
```

### Invoke-CDPJS

`Runtime.evaluate` を使ってブラウザ上でJavaScript式を実行する。

送る主なパラメータ:

```text
expression    : 実行するJavaScript式
returnByValue : true。値として返す
awaitPromise  : true。Promiseなら解決を待つ
userGesture   : true。ユーザー操作扱いが必要な処理を通しやすくする
```

戻り値:

```text
res.result.result.value
```

JavaScript例外がある場合は `JavaScript error: ...` として例外化する。

### Wait-CDPJS

JavaScript式が `true` を返すまで待つ。

用途:

```text
- 画面が描画されるまで待つ
- ボタンが有効になるまで待つ
- 条件が成立するまでポーリングする
```

DOM構築中や画面遷移中に一時的なJavaScriptエラーが出ることがある。
この関数では待機中の一時エラーを保持し、期限までリトライする。

期限切れ時:

```text
last error がある → 待機タイムアウト: Description / last error: ...
last error がない → 待機タイムアウト: Description
```

### Wait-DomContractResult

DOM contract の結果が fatal なしになるまで待つ。

通常の真偽値待機ではなく、JavaScript側から次のような結果が返る前提である。

```text
fatalCount
warningCount
items
```

`fatalCount` が 0 になれば成功扱いにする。
期限切れ時に直近のcontract結果がある場合は、`Format-DomContractResult` で読みやすく整形して例外に含める。

## 7. PowerShell文法上のポイント

### splatting

`Invoke-CDPJS` では、hashtableに引数を詰めてから `Send-CDPCommand @commandArgs` と呼ぶ。

これは splatting である。
条件付きで `Session` や `Runtime` を追加できる。

### `while ($true)`

`Send-CDPCommand` は、目的の `id` の応答が返るまでループする。
無限ループに見えるが、実際には deadline を毎回確認しているため、期限切れで停止する。

### `catch` で一時エラーを保持する

`Wait-CDPJS` と `Wait-DomContractResult` では、待機中の例外をすぐにthrowしない。
画面遷移中の一時エラーを許容する設計である。

## 8. 変更時の判断基準

```text
- command id 照合を削らない
- CDPイベントを応答扱いしない
- JavaScript exceptionDetails の例外化を削らない
- Wait-CDPJS の一時エラー許容を削ると、画面遷移中に不安定になる
- Timeout計算を各所でばらばらにしない
- Wait-DomContractResult の整形済みエラーを削ると、画面契約違反の診断が難しくなる
```

## 9. 関連テスト

```text
tests/Foundation.CdpRuntime.Tests.ps1
tests/Foundation.CdpTransport.Errors.Tests.ps1
tests/Foundation.CdpInternals.Tests.ps1
```

特に、Runtime.evaluate のパラメータ、JavaScript例外、CDP error、壊れたJSON、id不一致応答、WebSocket close、timeoutが検証されている。
