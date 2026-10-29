# DeviceListExportの読み方

## 1. DeviceListExportを一言でいうと

`DeviceListExport` は、ブラウザ上の「センサー / デバイス一覧」画面からCSVを1つダウンロードし、決められた名前で保存するジョブである。

画面上で行う操作は少ない。

```text
1. 対象画面を確認する
2. 操作ボタンをクリックする
3. 操作メニューが表示されるのを待つ
4. エクスポート項目をクリックする
5. CSVがダウンロードされるのを待つ
6. CSVを最終保存先へリネームして移動する
```

処理は短いが、このプロジェクトの基本設計がほぼ全部入っている。

```text
Runner       : ジョブ開始前の準備
Workflow     : 業務手順の並び
Dependencies : Workflowから呼ぶ部品を差し替え可能にする
DomAdapter   : 業務名で画面操作を呼ぶ
DomOperations: PowerShell名とJavaScript helper名を対応させる
Download     : CSVダウンロード待ちとリネーム
Output       : 結果オブジェクトとログ出力
```

## 2. 全体の実行順序

```text
Invoke-FoundationEntrypoint
  ↓
Import-FoundationJobModule
  ↓
Import-Module modules\DeviceListExport\DeviceListExport.psm1
  ↓
Invoke-DeviceListExportJob -Context $context
  ↓
Initialize-DeviceListExportJob
  ├─ Initialize-DeviceListExportOutputDirectories
  ├─ Open-DeviceListExportBrowserSession
  └─ Set-DeviceListExportDownloadDirectory
  ↓
Invoke-DeviceListExportWorkflow
  ├─ Resolve-DeviceListExportWorkflowDependencies
  ├─ Register DOM bundle
  ├─ Assert initial DOM contract
  ├─ Assert export page DOM contract
  ├─ Click task button
  ├─ Wait task menu ready
  ├─ Click export menu item
  ├─ Assert postcondition
  ├─ Wait downloaded CSV
  ├─ Rename downloaded CSV
  └─ New-DeviceListExportResult
  ↓
Write-DeviceListExportResultSummary
```

この流れのうち、`Runner.ps1` は初期化と最終ログ、`Workflow.ps1` は画面操作からCSV保存までの業務順序を担当する。

## 3. DeviceListExportの設定値

`foundation.jobs.psd1` 側では、DeviceListExportがどのモジュール・どのコマンドで実行されるかを定義する。

```text
JobName      = DeviceListExport
ModulePath   = modules\DeviceListExport\DeviceListExport.psm1
CommandName  = Invoke-DeviceListExportJob
DomFeaturePaths
  ├─ dom\features\device-list-export\contract.js
  ├─ dom\features\device-list-export\navigation.js
  ├─ dom\features\device-list-export\export.js
  └─ dom\features\device-list-export\index.js
```

`foundation.config.psd1` 側では、DeviceListExport実行時に使う値を定義する。

```text
TempDirectory                 : ブラウザの一時ダウンロード先
DownloadDirectory             : リネーム後CSVの最終保存先
DownloadedCsvFileNamePattern  : 一時フォルダで探すCSV名の正規表現
OutputFileNameTemplate        : 最終出力ファイル名テンプレート
DownloadTimeoutSeconds        : CSVダウンロード待ちの最大秒数
DownloadStableSeconds         : ファイルサイズ安定確認の秒数
NavigationTimeoutSeconds      : 画面遷移・識別用のタイムアウト
TaskMenuTimeoutSeconds        : 操作メニュー表示待ちの最大秒数
```

`DeviceListExport` の各関数は、これらの値を直接 `Import-PowerShellDataFile` で読まない。
`Initialize-FoundationRuntime` と `New-FoundationRunContext` によって作られた `$Context.JobSettings` から参照する。

## 4. DeviceListExportで重要な分離

### RunnerとWorkflowの違い

| 領域 | 担当 |
|---|---|
| `Runner.ps1` | 実行前の環境準備、ブラウザ接続、ダウンロード先設定、Workflow呼び出し、結果サマリー |
| `Workflow.ps1` | DOM登録、画面契約確認、クリック、ダウンロード待ち、リネームという業務手順 |

Runnerは「ジョブを始められる状態にする」。
Workflowは「ジョブの本体手順を実行する」。

### DomAdapterとDomOperationsの違い

| 領域 | 担当 |
|---|---|
| `DomAdapter.ps1` | `ClickTaskButton` など、Workflowから見える業務名の関数を提供する |
| `DomOperations.ps1` | `ClickTaskButton` を JavaScript 側の `clickTaskButton` に対応させる |

Workflowに `clickTaskButton` というJavaScriptメソッド名を直接書かないことが重要である。
Workflowは「操作ボタンをクリックする」という業務操作だけを知っていればよい。

### DownloadをWorkflowに混ぜない理由

CSVダウンロードは画面操作とは別の副作用である。

```text
- 一時フォルダが存在するか確認する
- .crdownload / .tmp / .download が消えるまで待つ
- CSV候補が1つだけか確認する
- ファイルサイズが安定するか確認する
- ファイルを読み取り専有で開けるか確認する
- 最終ファイル名へリネームする
```

これをWorkflowに書くと、Workflowが「画面手順」と「ファイルシステム処理」の両方を持つ。
そのため、`Download.ps1` に隔離している。

## 5. DeviceListExportの戻り値

最終的に `Invoke-DeviceListExportJob` は次の形のオブジェクトを返す。

```text
DeviceListExportResult
  Ok                : true
  Feature           : DeviceListExport
  DownloadedCsvPath : 一時フォルダで見つかったCSVの元パス
  ExportedCsvPath   : 最終保存先に移動・リネームされたCSVのパス
  DomResult         : エクスポートクリック時のDOM操作結果
```

この戻り値は、人間向けログとは別である。
ログは `Write-DeviceListExportResultSummary` が出力する。
戻り値は、CompositeJobsやテストが処理結果を確認するために使える。

## 6. このジョブで失敗する代表例

| 失敗箇所 | 例 | 止める理由 |
|---|---|---|
| ブラウザ接続 | 対象タブが見つからない | 間違った画面を操作しないため |
| DOM bundle登録 | JSファイルが未登録 | helperメソッドを呼べないため |
| 初期契約確認 | 画面構造が想定と違う | ボタン探索やクリックが危険なため |
| 操作メニュー待ち | メニューが開かない | エクスポート項目をクリックできないため |
| CSV待ち | CSVが出ない、複数CSVがある | 誤ったCSVを保存しないため |
| リネーム | ファイル名が.csvにならない | 成果物契約に反するため |

## 7. 本ドキュメント内容の要点

```text
- DeviceListExportは「1つのCSVを画面から出す」短いDOM系ジョブである
- Runnerは準備、Workflowは業務手順である
- DependenciesはWorkflowの呼び出し先をscriptblockとして束ねる
- DomAdapterはWorkflow用の業務名を提供する
- DomOperationsはJavaScript helperとの対応表を持つ
- Downloadは一時CSVの安定確認とリネームを担当する
- Outputは結果オブジェクトとログ出力を担当する
```
