# modules/Foundation/internal/CdpRuntime.ps1

## 1. このファイルを一言でいうと

CDP低レベル機能を、Feature module から使いやすい Foundation 公開APIに包むファイルである。

`CdpTransport.ps1`、`CdpConnection.ps1`、`CdpCommand.ps1`、`CdpBrowser.ps1` は低レベル寄りである。
Feature module は通常、それらを直接呼ばず、このファイルの関数を使う。

## このファイルを変更する典型ケース

- CDP接続、command送受信、target探索、timeout方針が変わった場合
- Foundation公開サービスと低レベルCDP実装の境界が変わった場合
- CDPエラーや切断時の診断情報が変わった場合


## 2. このファイルが担当する範囲

```text
- DebuggerUrl から操作対象ページを開く
- PageIdentityMatcher付きで対象ページを開く
- JavaScript評価を上位APIとして提供する
- JavaScript条件待機を上位APIとして提供する
- ダウンロード先設定を上位APIとして提供する
```

## 3. このファイルが担当しない範囲

```text
- WebSocketの具象操作
- CDP command JSON の詳細
- DOM helperメソッド名の管理
- Feature固有の業務処理
```

## 4. 外部公開される関数

`Foundation.psm1` では、このファイルの次の関数が export されている。

```text
Open-FoundationPage
Open-FoundationPageMatchingIdentity
Invoke-FoundationJavaScript
Wait-FoundationJavaScript
Set-FoundationDownloadDirectory
```

これらは、Foundationの外から呼べるAPIである。

## 5. 関数呼び出しツリー

```text
Open-FoundationPage
  ├─ Get-TargetPageWebSocketUrl
  ├─ Open-CDPConnection
  └─ Page object を返す

Open-FoundationPageMatchingIdentity
  ├─ Get-TargetPageWebSocketUrlMatchingIdentity
  ├─ Open-CDPConnection
  └─ Page object を返す

Invoke-FoundationJavaScript
  └─ Invoke-CDPJS

Wait-FoundationJavaScript
  └─ Wait-CDPJS

Set-FoundationDownloadDirectory
  └─ Set-CDPDownloadDirectory
```

## 6. 関数ごとの説明

### Open-FoundationPage

DebuggerUrl から操作対象ページに接続する。

入力:

```text
DebuggerUrl            : ブラウザのCDP target一覧URL
ConnectTimeoutSeconds : WebSocket接続タイムアウト
CommandTimeoutSeconds : CDP命令タイムアウト
Runtime                : テスト差し替え用Runtime
```

処理:

```text
1. Get-TargetPageWebSocketUrl で page の WebSocket URL を取得する
2. Open-CDPConnection で WebSocket接続する
3. DebuggerUrl / WebSocketUrl / CdpSession を持つオブジェクトを返す
```

戻り値:

```text
FoundationPage
  DebuggerUrl
  WebSocketUrl
  CdpSession
```

この関数は、操作可能なpageターゲットが1つだけである前提の経路である。
複数タブがありうる場合は `Open-FoundationPageMatchingIdentity` を使う。

### Open-FoundationPageMatchingIdentity

PageIdentityMatcherで対象タブを識別してから接続する。

入力:

```text
DebuggerUrl
PageIdentityMatcher
ConnectTimeoutSeconds
CommandTimeoutSeconds
Runtime
```

処理:

```text
1. Get-TargetPageWebSocketUrlMatchingIdentity で対象タブのWebSocket URLを取得する
2. Open-CDPConnection で本接続を開く
3. FoundationPage を返す
```

この関数は、複数タブが開いている状況でも、Feature側のページ識別ロジックに一致するタブだけを選ぶ。

### Invoke-FoundationJavaScript

ブラウザ上でJavaScript式を実行する。

入力:

```text
Expression     : JavaScript式
TimeoutSeconds : 実行タイムアウト
```

戻り値:

```text
JavaScriptの評価結果
```

内部では `Invoke-CDPJS` を呼ぶだけである。
この薄いラッパーがある理由は、Feature module が `CDP` という低レベル語彙ではなく、`FoundationJavaScript` という上位語彙で呼べるようにするためである。

### Wait-FoundationJavaScript

JavaScript式が true になるまで待つ。

入力:

```text
Expression     : trueになるまで評価するJavaScript式
TimeoutSeconds : 待機上限
Description    : エラー時の説明
```

出力:

```text
成功時は戻り値なし
失敗時は timeout 例外
```

内部では `Wait-CDPJS` を呼ぶ。

### Set-FoundationDownloadDirectory

ブラウザのダウンロード先を設定する。

入力:

```text
Directory : ダウンロード先ディレクトリ
Runtime   : テスト差し替え用Runtime
```

内部では `Set-CDPDownloadDirectory` を呼ぶ。
`Set-CDPDownloadDirectory` 側でディレクトリ作成とCDP method fallbackを行う。

## 7. `$PSBoundParameters.ContainsKey('Runtime')` の意味

このファイルでは、Runtimeが明示指定された場合だけ下位関数へ渡す処理がある。

```text
if ($PSBoundParameters.ContainsKey('Runtime')) {
    $args.Runtime = $Runtime
}
```

これは、「引数が省略された」のか「明示的にnullが渡された」のかを区別するためである。

この区別があると、テストでRuntimeを注入したい場合だけ下位層へ確実に渡せる。

## 8. このファイルが薄い理由

このファイルの関数は、処理量だけ見ると薄い。
しかし役割はある。

```text
Feature module が呼ぶ上位API名を提供する
CDP低レベル関数への直接依存を隠す
戻り値の FoundationPage 形を固定する
Runtime注入の入口を統一する
```

ここを消して Feature module から `Open-CDPConnection` や `Invoke-CDPJS` を直接呼ばせると、Feature module がCDP詳細に依存する。
その結果、CDP層の変更がFeature module全体へ漏れやすくなる。

## 9. 変更時の判断基準

```text
- Feature moduleにCDP語彙を漏らさない
- FoundationPage の DebuggerUrl / WebSocketUrl / CdpSession 形を不用意に変えない
- Open-FoundationPageMatchingIdentity を削ると、複数タブ誤操作防止が弱くなる
- Runtime注入を削ると、CDP接続系テストが実ブラウザ依存に近づく
```

## 10. 関連テスト

```text
tests/Foundation.CdpRuntime.Tests.ps1
```

JavaScript評価の委譲、JavaScript待機の委譲、FoundationPage戻り値、PageIdentityMatcher経路、RunContext close時のCdpSession closeが検証されている。
