# modules/DeviceListExport/internal/Workflow.ps1

## 1. このファイルを一言でいうと

DeviceListExportの業務手順を順番に並べるファイルである。

このファイルは、DOM操作やファイル操作の具体的実装を直接持たない。
代わりに、`Dependencies.ps1` から受け取った scriptblock を順番に実行する。

## このファイルを変更する典型ケース

- 処理順序、分岐、リトライ、失敗時の継続方針が変わった場合
- Policy判定結果と依存portのつなぎ方が変わった場合
- Workflowが集約する結果や後続処理への渡し方が変わった場合


## 2. このファイルが担当する範囲

```text
- DOM bundleを登録する順番を決める
- 画面契約を確認する順番を決める
- 操作ボタン、操作メニュー、エクスポートクリックの順番を決める
- CSVダウンロード待ちとリネームの順番を決める
- 最終結果オブジェクトを組み立てる
- 各ステップのログメッセージを出す
```

## 3. このファイルが担当しない範囲

```text
- JavaScript helper名を決める
- CSS selectorを探す
- CSV候補ファイルを検索する
- ファイルサイズ安定判定をする
- ログファイルへの実際の書き込み処理を実装する
```

これらは、他ファイルやFoundationの責務である。

## 4. 関数呼び出しツリー

```text
Invoke-DeviceListExportWorkflow
  ├─ Resolve-DeviceListExportWorkflowDependencies
  ├─ Get-DeviceListExportCallbackScriptBlock x 複数
  ├─ Invoke-DeviceListExportWorkflowStep "DOM bundleを登録します。"
  │   └─ Dom.Register
  ├─ Invoke-DeviceListExportWorkflowStep "初期DOM契約を検証します。"
  │   └─ Dom.AssertInitialContract
  ├─ Invoke-DeviceListExportWorkflowStep "エクスポート対象画面DOM契約を検証します。"
  │   └─ Dom.AssertExportPageContract
  ├─ Invoke-DeviceListExportWorkflowStep "操作ボタンをクリックします。"
  │   └─ Dom.ClickTaskButton
  ├─ Invoke-DeviceListExportWorkflowStep "操作メニュー表示を待機します。"
  │   └─ Dom.WaitTaskMenuReady
  ├─ Invoke-DeviceListExportWorkflowStep "操作メニュー内のエクスポートをクリックします。"
  │   └─ Dom.ClickExportMenuItem
  ├─ Invoke-DeviceListExportWorkflowStep "エクスポートクリック後DOM契約を検証します。"
  │   └─ Dom.AssertPostcondition
  ├─ Invoke-DeviceListExportWorkflowStep "CSVダウンロード完了を待機します。"
  │   └─ Download.WaitDownloadedCsv
  ├─ Invoke-DeviceListExportWorkflowStep "ダウンロードCSVを既定ルールでリネームします。"
  │   └─ Download.RenameDownloadedCsv
  └─ New-DeviceListExportResult
```

## 5. 実行ステップの意味

| 順序 | ステップ | 理由 |
|---:|---|---|
| 1 | DOM bundle登録 | ブラウザ上に `window.__DeviceListExportDomHelper` を用意する |
| 2 | 初期DOM契約確認 | helper登録と基本画面状態を検証する |
| 3 | エクスポート対象画面契約確認 | 操作ボタンや対象画面の前提を検証する |
| 4 | 操作ボタンクリック | エクスポート項目を含むメニューを開く |
| 5 | 操作メニュー待ち | メニュー表示前にクリックしないようにする |
| 6 | エクスポートクリック | CSV出力を開始する |
| 7 | クリック後契約確認 | クリック操作がDOM上で成立したか確認する |
| 8 | CSVダウンロード待ち | ブラウザのファイル出力完了を待つ |
| 9 | CSVリネーム | 最終保存名へ変換する |
| 10 | 結果作成 | 呼び出し元へ成果物パスを返す |

## 6. 関数ごとの説明

### Invoke-DeviceListExportWorkflowStep

1つのステップを「ログ出力」と「実処理」に分けて実行する小さな補助関数である。

処理は次の通り。

```text
1. LoggerからWriteInfo scriptblockを取得する
2. Messageをログ出力する
3. Action scriptblockを実行する
4. Actionの戻り値を返す
```

この関数により、Workflowの本体では各ステップが同じ形で読める。

```text
ログを出す → 処理する
ログを出す → 処理する
ログを出す → 処理する
```

### Invoke-DeviceListExportWorkflow

DeviceListExportの本体手順である。

引数は次の2つ。

```text
Context
  通常実行時の設定・サービス・loggerを含む実行時オブジェクト。

Dependencies
  テストや特殊実行時に差し替え可能な依存オブジェクト。
  nullなら本番用依存がResolve-DeviceListExportWorkflowDependenciesで作られる。
```

この関数は、まず依存を解決する。

```text
resolvedDependencies.Dom
resolvedDependencies.Download
resolvedDependencies.Logger
resolvedDependencies.Timing
```

次に、それぞれのコールバックを取り出す。

```text
Dom.Register
Dom.AssertInitialContract
Dom.AssertExportPageContract
Dom.ClickTaskButton
Dom.WaitTaskMenuReady
Dom.ClickExportMenuItem
Dom.AssertPostcondition
Download.WaitDownloadedCsv
Download.RenameDownloadedCsv
Timing.TimestampText
```

そして、業務順序に沿って実行する。

## 7. 戻り値の形

`Invoke-DeviceListExportWorkflow` は `New-DeviceListExportResult` の戻り値を返す。

```text
Ok                : true
Feature           : DeviceListExport
DownloadedCsvPath : 一時フォルダで見つけたCSVのパス
ExportedCsvPath   : 最終保存先へ移動したCSVのパス
DomResult         : エクスポートメニュークリックの結果
```

`DownloadedCsvPath` と `ExportedCsvPath` は同じファイルを指しているとは限らない。
一時フォルダ上のパスと、最終保存先にリネーム後のパスを分けて持つ。

## 8. PowerShell文法上のポイント

### scriptblockを変数に入れて実行する

このファイルでは、次のようにscriptblockを変数に入れてから呼んでいる。

```text
$register = Get-DeviceListExportCallbackScriptBlock ...
& $register
```

`&` は呼び出し演算子である。
変数に入っているscriptblockやCommandInfoを実行するために使う。

### 引数を位置で渡している箇所

`WaitDownloadedCsv` や `RenameDownloadedCsv` は、scriptblockとして呼ぶため、位置引数で渡している。

```text
& $waitDownloadedCsv $directory $pattern $timeout $stableSeconds
```

このため、`Dependencies.ps1` 側のscriptblock定義の引数順序が重要である。
引数順序を変えると、ディレクトリ名やタイムアウト値がずれて実行される。

### `| Out-Null`

契約確認やクリックなど、戻り値を後で使わないステップでは `Out-Null` している。
PowerShellでは余計な出力が関数全体の戻り値に混ざるため、それを防ぐ目的である。

## 9. 失敗条件

このWorkflowは、原則として失敗を握りつぶさない。
どこかのstepが `throw` したら、そこでジョブ全体を止める。

代表例は次の通り。

```text
- DOM bundle登録に失敗する
- 画面契約がfatalになる
- 操作ボタンが見つからない
- 操作メニューがタイムアウトする
- CSVダウンロードがタイムアウトする
- CSV候補が複数ある
- リネーム後ファイルが0 byteになる
```

DeviceListExportは成果物CSVが1つ出るかどうかが重要である。
中途半端な状態で成功扱いにしないため、異常時は停止する。

## 10. 変更時の注意

### 契約確認を削らない

`AssertInitialContract` や `AssertExportPageContract` は、一見するとクリック前の余分な確認に見える。
しかし、画面DOMが変わった状態でクリックだけ実行すると、誤クリックや無反応を後から診断しにくくなる。
契約確認は「画面変更を早めに検出するための診断境界」である。

### ダウンロード待ちとリネームの順序を変えない

CSVが安定してからリネームする必要がある。
安定確認前にMoveすると、ブラウザがまだ書き込んでいるファイルを動かすことになり、0 byteや壊れたCSVを保存する可能性がある。

### WorkflowにJavaScriptメソッド名を書かない

Workflowは `clickTaskButton` ではなく `ClickTaskButton` という業務名を扱う。
JavaScript helper名は `DomOperations.ps1` に閉じ込める。

## 11. 本ドキュメント内容の要点

```text
- WorkflowはDeviceListExportの業務手順を順番に実行する
- 具体的なDOM操作やファイル操作はDependencies経由で呼ぶ
- 各ステップはログを出してから実行される
- 契約確認、クリック、ダウンロード、リネームの順序には意味がある
- 失敗は握りつぶさず、ジョブ全体を止める
```
