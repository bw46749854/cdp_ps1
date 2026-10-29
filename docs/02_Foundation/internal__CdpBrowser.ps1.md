# modules/Foundation/internal/CdpBrowser.ps1

## 1. このファイルを一言でいうと

ブラウザ全体から「操作対象にするpageタブ」を選び、そのタブの `webSocketDebuggerUrl` を取得するファイルである。

CDP接続を開く前には、まず「どのタブに接続するか」を決める必要がある。
このファイルはその決定を担当する。

## このファイルを変更する典型ケース

- CDP接続、command送受信、target探索、timeout方針が変わった場合
- Foundation公開サービスと低レベルCDP実装の境界が変わった場合
- CDPエラーや切断時の診断情報が変わった場合


## 2. このファイルが担当する範囲

```text
- DebuggerUrl から取得した target JSON を解析する
- 操作対象になりうる page ターゲットだけを抽出する
- タブが1つだけならそれを選ぶ
- 複数タブの中から PageIdentityMatcher で対象タブを選ぶ
- 候補や選択結果を診断出力する
- CDP経由でダウンロード先を設定する
```

## 3. このファイルが担当しない範囲

```text
- WebSocket接続の作成
- CDP command JSON の送受信
- DOM helper JavaScript の登録
- Feature固有のページ識別ロジックの中身
```

Feature固有のページ識別は、`PageIdentityMatcher` という scriptblock として外から渡される。

## 4. 対象タブ選択の流れ

### 単純選択

```text
Get-TargetPageWebSocketUrl
  ├─ Runtime.HttpClient.GetContent(DebuggerUrl)
  ├─ ConvertFrom-CDPTargetInfoJson
  ├─ Get-CDPOperablePageTargetCandidates
  ├─ 候補が複数なら Write-CDPPageTargetCandidates
  ├─ Select-FoundationPageTarget
  ├─ Write-CDPSelectedPageTarget
  └─ webSocketDebuggerUrl を返す
```

この流れでは、操作可能なpageターゲットが1つだけであることを要求する。

### PageIdentityMatcherありの選択

```text
Get-TargetPageWebSocketUrlMatchingIdentity
  ├─ Runtime.HttpClient.GetContent(DebuggerUrl)
  ├─ ConvertFrom-CDPTargetInfoJson
  ├─ Select-FoundationPageTargetMatchingIdentity
  │    ├─ page候補を抽出
  │    ├─ 各候補へ一時的に Open-CDPConnection
  │    ├─ PageIdentityMatcher を実行
  │    ├─ finally で一時接続を Close
  │    ├─ matched 0件なら停止
  │    ├─ matched 2件以上なら停止
  │    └─ matched 1件なら採用
  ├─ Write-CDPSelectedPageTarget
  └─ webSocketDebuggerUrl を返す
```

## 5. pageターゲット候補の条件

`Get-CDPOperablePageTargetCandidates` は、タブ一覧から次を満たすものだけを残す。

```text
- type が "page"
- webSocketDebuggerUrl が空ではない
- URL が chrome-extension:// ではない
- URL が devtools:// ではない
- URL が chrome:// ではない
- URL が edge:// ではない
- title が Service Worker* ではない
```

このフィルタにより、拡張機能、DevTools、ブラウザ内部ページ、Service Worker を誤操作対象から外す。

## 6. 関数ごとの説明

### ConvertFrom-CDPTargetInfoJson

DebuggerUrl から返ったタブ一覧JSONをPowerShellオブジェクトに変換する。

失敗時には、target情報のJSON解析失敗として例外を投げる。

### Get-CDPOperablePageTargetCandidates

操作対象になりうる page ターゲットだけを抽出する。

出力:

```text
page target オブジェクト配列
```

各targetは通常、次のようなプロパティを持つ。

```text
type
title
url
webSocketDebuggerUrl
```

### Select-FoundationPageTarget

候補が1件だけであることを要求して、そのtargetを返す。

失敗条件:

```text
候補0件 → 対象画面を開いてから再実行する必要がある
候補2件以上 → 誤操作防止のため停止する
webSocketDebuggerUrl空 → 接続先が取得できないため停止する
```

この関数は「曖昧なまま選ばない」ために存在する。

### Write-CDPPageTargetCandidates

複数候補があった場合に、候補の title / url を表形式で出力する。

目的は、ユーザーがどのタブを閉じるべきか判断できるようにすることである。

### Write-CDPSelectedPageTarget

選択されたタブの title / URL / WebSocket URL を出力する。

実行ログ上で「どのタブを操作したか」を確認するための診断出力である。

### ConvertTo-CDPPageIdentityMatchOutcome

Feature側の `PageIdentityMatcher` の戻り値を、統一された形に変換する。

受け付ける戻り値:

```text
true / false
@{ Matched = true; Reason = '...' }
@{ ok = true }
その他
```

出力:

```text
MatchOutcome
  Matched : bool
  Reason  : string
  Result  : 元の戻り値
```

戻り値形式を広めに受け入れているため、Feature側のmatcher実装が過度に厳密な型に縛られない。

### Invoke-CDPPageIdentityMatcher

渡された `PageIdentityMatcher` を実行し、戻り値を `MatchOutcome` に変換する。

入力:

```text
PageIdentityMatcher
PageTarget
Session
```

Feature側のmatcherは、対象タブに一時接続した状態で実行される。

### Write-CDPPageIdentityMatcherDiagnostics

複数タブの識別結果を診断出力する。

出力内容:

```text
- Title
- URL
- Match: matched / not matched
- Reason
```

対象タブが見つからない場合や複数見つかった場合、この診断がないと原因が追いにくい。

### Select-FoundationPageTargetMatchingIdentity

複数タブの中から、`PageIdentityMatcher` に一致するタブを1つだけ選ぶ。

処理:

```text
1. page候補を抽出する
2. 各候補へ一時的にCDP接続する
3. PageIdentityMatcher を実行する
4. 結果を matchResults に記録する
5. finally で必ず一時接続を閉じる
6. matched 0件なら診断出力して停止
7. matched 複数なら診断出力して停止
8. matched 1件ならそのtargetを返す
```

重要なのは、各候補への接続が一時的であること。
最終的な本接続は `CdpRuntime.ps1` の `Open-FoundationPageMatchingIdentity` 側で改めて開かれる。

### Get-TargetPageWebSocketUrl

DebuggerUrl からタブ一覧を取得し、候補が1件だけならその WebSocket URL を返す。

接続失敗時のエラーには、ブラウザを `--remote-debugging-port=9222` 付きで起動する必要があることが含まれる。

### Get-TargetPageWebSocketUrlMatchingIdentity

DebuggerUrl からタブ一覧を取得し、PageIdentityMatcherで対象タブを選び、その WebSocket URL を返す。

複数タブ運用に対応するための主経路である。

### Set-CDPDownloadDirectory

CDP経由でブラウザのダウンロード先を設定する。

処理:

```text
1. Initialize-FoundationOutputDirectory でディレクトリを準備する
2. Browser.setDownloadBehavior を試す
3. 失敗したら警告を出す
4. Page.setDownloadBehavior を試す
5. 成功したら設定先を出力する
```

`Browser.setDownloadBehavior` と `Page.setDownloadBehavior` の両方を試す理由は、ブラウザやCDPバージョンによって使える method が異なる可能性があるためである。

## 7. PowerShell文法上のポイント

### `Where-Object`

page候補抽出では、パイプラインで受け取ったtargetを条件判定している。

```text
$TargetInfo | Where-Object { 条件 }
```

この条件が、誤操作対象を除外するフィルタである。

### `finally`

`Select-FoundationPageTargetMatchingIdentity` では、各候補タブへの一時接続後、`finally` で `Close-CDPConnection` を呼ぶ。

matcherの実行が成功しても失敗しても、一時接続を閉じるためである。

## 8. 変更時の判断基準

```text
- 複数タブを自動で先頭選択するように変更しない
- browser内部URLやdevtools URLの除外条件を安易に削らない
- matcher実行後の finally Close を削らない
- matched 0件 / 複数件を曖昧なまま続行しない
- ダウンロード先設定の fallback を削る場合、対象ブラウザ/CDPバージョンを確認する
```

## 9. 関連テスト

```text
tests/Foundation.CdpRuntime.Tests.ps1
```

page候補フィルタ、候補複数時の診断、PageIdentityMatcherによる1件選択、0件拒否、複数件拒否、matcher例外の扱い、ダウンロード先設定fallbackが検証されている。
