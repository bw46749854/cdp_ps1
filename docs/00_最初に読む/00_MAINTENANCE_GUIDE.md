# 理解のためのガイド：このプロジェクトの読み方

この文書は詳細編です。
最初に読む入口は `docs/00_最初に読む/START_HERE.md` です。
全体像を短く把握してから、この文書で詳細を確認してください。

このドキュメントは、このプロジェクトを保守する人が、次のことを判断できるようにするための資料です。

```text
どこから読むべきか
処理がどのファイルを通るか
どのファイルが何を担当しているか
変更するときに、どこを直すべきか
変更してはいけない境界はどこか
```

このプロジェクトでは、画面操作、CSV処理、ダウンロード処理、ジョブ連携処理を分けています。
分割されている理由は、
**変更理由が違う処理を分け、変更時の影響範囲を狭くするため**です。

以下では、実行ルートを `main/` として説明します。


## 0. ドキュメントの正本と役割

このプロジェクトのドキュメントは、すべてを同じ重みで扱わない。
保守時は、まず次の分類で読む。

| 種別 | 役割 | 正本として扱う情報 |
|---|---|---|
| `main/ARCHITECTURE.md` | 設計判断の基準 | SRP / DIP / Job境界 / Composite Job境界 / DOM helper未登録時の方針 |
| 個別ファイルドキュメント | 実装詳細の説明 | 対応する source file の責務、公開関数、入力、出力、重要な分岐 |
| 横断ガイド | 読み方案内 | 読む順番、ファイル間の関係、誤解しやすい点 |
| テスト仕様ドキュメント | テストの読み方案内 | どのテストがどの設計境界を守っているか |

横断ガイドは詳細仕様の正本ではない。
横断ガイドに、関数一覧、引数一覧、DOM operation一覧、CSV列の完全仕様、設定キー一覧を再掲しない。
それらは個別ファイルドキュメントまたは設定ファイル側を正とする。

横断ガイドを更新するのは、読み順、責務の関係、変更時の参照先、誤解しやすい点が変わった場合に限る。
細かい関数追加や引数変更だけなら、対応する個別ファイルドキュメントを更新する。

---

## 1. このプロジェクトは何をしているのか

このプロジェクトは、PowerShell からブラウザを操作し、画面上の情報取得・CSVダウンロード・チェックボックス操作を自動化するためのプロジェクトです。

主な実行単位は `Job` です。

| ジョブ名 | 種類 | 何をするか |
|---|---|---|
| `DeviceListExport` | DOM系ジョブ | 管理画面からデバイス一覧CSVをエクスポートする |
| `ScanTargetSync` | DOM系ジョブ | 入力CSVを読み、画面上のチェックボックスをON/OFFする |
| `InstalledAppExport` | DOM系ジョブ | 端末一覧を見て、各行の詳細からアプリCSVをダウンロードする |
| `LastMonthInstallExtract` | ファイル処理ジョブ | InstalledAppExportが出したCSVを読み、インストール情報CSVを作る |
| `WeeklyScanTargetSync` | Composite Job | `DeviceListExport` の結果を使って `ScanTargetSync` を続けて実行する |
| `MonthlyInstallReport` | Composite Job | `InstalledAppExport` の結果を使って `LastMonthInstallExtract` を続けて実行する |

実行例です。

```powershell
.\run_job.ps1 -JobName DeviceListExport
.\run_job.ps1 -JobName ScanTargetSync
.\run_job.ps1 -JobName InstalledAppExport
.\run_job.ps1 -JobName LastMonthInstallExtract
.\run_job.ps1 -JobName WeeklyScanTargetSync
.\run_job.ps1 -JobName MonthlyInstallReport
```

上の例は、保守時に `JobName` を直接指定する場合の例です。  
root の `.bat` は、通常作業用の入口として単体Jobではなく Composite Job を呼びます。対応関係は `docs/01_起動設定/bat起動入口とJobName.md` を参照してください。

---

## 2. 全体の流れ

DOMを使うジョブの基本形です。

```text
main/run_job.ps1
  ↓
Foundation モジュール
  ↓
config/foundation.jobs.psd1 を読む
  ↓
config/foundation.config.psd1 を読む
  ↓
対象ジョブのモジュールを読み込む
  ↓
Runner
  ↓
Workflow
  ↓
Dependencies / Port
  ↓
DomAdapter
  ↓
DomOperations
  ↓
Foundation DomHelper / CDP
  ↓
ブラウザ内 JavaScript
  ↓
画面を読む・クリックする・スクロールする
  ↓
CSV・結果・失敗情報を出す
```

`LastMonthInstallExtract` のようにDOMを使わないジョブは、ブラウザ操作部分を通りません。

```text
main/run_job.ps1
  ↓
Foundation モジュール
  ↓
LastMonthInstallExtract Runner
  ↓
LastMonthInstallExtract Workflow
  ↓
Input / Encoding / DelimitedText / Rules / Output
  ↓
CSVを読む・判定する・出力する
```

Composite Job は、既存ジョブを順番に呼ぶだけの薄い連携ジョブです。

```text
main/run_job.ps1
  ↓
Foundation モジュール
  ↓
CompositeJobs
  ↓
子Job 1
  ↓
子Job 2
```

Composite Job は、子Jobの内部処理には入りません。

---

## 3. ファイルごとの基本役割

| 種類 | 役割 | 変更するときの目安 |
|---|---|---|
| `run_job.ps1` | 最初に呼ばれる入口 | 基本的には変更しない |
| `Foundation` | 全ジョブ共通の起動、設定、CDP、DOM bundle、ログ、ファイル安全処理 | 全ジョブに影響するため慎重に変更する |
| `Runner.ps1` | そのジョブの開始、初期化、終了、結果検査 | ジョブ全体の開始・終了を変えるときに見る |
| `Workflow*.ps1` | 作業の順番、分岐、集約 | 処理順序や判定の流れを変えるときに見る |
| `Dependencies.ps1` | 本番用・テスト用の依存をまとめる | テスト差し替えや外部I/Oの窓口を変えるときに見る |
| `DomAdapter.ps1` | PowerShellから見た画面操作の業務名を定義する | Workflowから呼ぶ画面操作名を変えるときに見る |
| `DomOperations.ps1` | JavaScript helper呼び出しを定義する | JS側のoperation名・契約が変わるときに見る |
| `dom/features/**/*.js` | ブラウザ内で実際にDOMを読む・押す・スクロールする | 画面HTMLやselectorが変わったときに見る |
| `Input.ps1` / `CsvInput.ps1` | 入力ファイル・CSVを読む | 入力ファイル形式や列名を変えるときに見る |
| `Encoding.ps1` | 文字コードを扱う | CSVの文字コード処理を変えるときに見る |
| `DelimitedText.ps1` | 区切り文字つきテキストをCSVレコード化する | カンマ・タブ等の解析を変えるときに見る |
| `Rules.ps1` | 業務判定ルール | ON/OFF判定や抽出条件を変えるときに見る |
| `Reconciliation.ps1` | CSVと画面などの突き合わせ | 入力と画面の一致確認を変えるときに見る |
| `Models.ps1` | 結果・失敗行などのデータ形状 | 出力前のデータ形を変えるときに見る |
| `Output.ps1` | CSV出力・結果表示 | 出力CSVの列やファイル名を変えるときに見る |
| `Download.ps1` | ダウンロード待ち、安定確認、リネーム | ダウンロード仕様を変えるときに見る |
| `CompositeJobs.psm1` | 既存ジョブの連携 | 子Jobの順序、override、成果物確認だけを変える |

---

## 4. 最初に読む入口

最初に読むファイルはこれです。

```text
main/run_job.ps1
```

`run_job.ps1` は、実際の業務処理をほとんど持ちません。
やっていることは主に次の3つです。

```text
1. プロジェクトの場所を決める
2. Foundation モジュールを読み込む
3. Invoke-FoundationEntrypoint を呼ぶ
```

つまり、`run_job.ps1` は受付です。
受付は、自分で画面操作やCSV処理をしません。
指定された `JobName` を Foundation に渡します。

---

## 5. Foundation モジュールの役割

`Foundation` は、全ジョブで使う共通基盤です。

場所はここです。

```text
main/modules/Foundation/
```

主なファイルです。

| ファイル | 何をするか |
|---|---|
| `Foundation.psm1` | internal配下の共通ファイルを読み込む |
| `Bootstrap.ps1` | 起動処理、config読み込み、ジョブ呼び出し |
| `Config.ps1` | `foundation.config.psd1` を読む |
| `JobRegistry.ps1` | `foundation.jobs.psd1` からジョブ定義を読む |
| `RunContext.ps1` | 実行中に必要な情報を1つの箱にまとめる |
| `Logging.ps1` | ログを書く |
| `Errors.ps1` | fatal error 判定を扱う |
| `FileSystem.ps1` | ディレクトリやファイルを安全に扱う |
| `DomContract.ps1` | DOM helperの返却形を検査する |
| `DomBundle.ps1` | ブラウザにJavaScriptを読み込ませる |
| `DomHelper.ps1` | ブラウザ内のhelper関数を呼ぶ |
| `ScrollableList.ps1` | スクロールしながら一覧を処理する共通処理 |
| `Cdp*.ps1` | ブラウザと通信する低レベル処理 |

`Foundation` に feature 固有の処理は入れません。
たとえば、InstalledAppExportだけのCSV列、ScanTargetSyncだけの判定ルール、LastMonthInstallExtractだけの抽出条件は入れません。

---

## 6. 設定ファイルの見方

ジョブ定義はここにあります。

```text
main/config/foundation.jobs.psd1
```

ここには、各Jobについて次のような情報があります。

```text
JobName
  ModulePath
  CommandName
  DomFeaturePaths または UsesDom
```

例です。

```text
InstalledAppExport
  ModulePath  = modules\InstalledAppExport\InstalledAppExport.psm1
  CommandName = Invoke-InstalledAppExportJob
  DomFeaturePaths = dom\features\installed-app-export\*.js
```

`foundation.jobs.psd1` は、**ジョブ名と実装を結びつける地図**です。

一方、実行時の値はここにあります。

```text
main/config/foundation.config.psd1
```

ここには、出力フォルダ、timeout、閾値、ファイル名などがあります。

```text
Common
  Logging
  Cdp

Jobs
  DeviceListExport
  ScanTargetSync
  InstalledAppExport
  LastMonthInstallExtract
  WeeklyScanTargetSync
  MonthlyInstallReport
```

`foundation.jobs.psd1` と `foundation.config.psd1` は役割が違います。

| ファイル | 役割 |
|---|---|
| `foundation.jobs.psd1` | どのモジュールを読み、どの関数を呼ぶか |
| `foundation.config.psd1` | そのジョブをどの設定値で動かすか |

---

## 7. RunContext とは何か

Foundation は、ジョブを呼ぶ前に `Context` を作ります。

`Context` は、実行中に必要な情報をまとめた箱です。

主な中身です。

| Key | 意味 |
|---|---|
| `RootPath` | 実行ルート |
| `RunId` | 実行ごとの識別子 |
| `JobName` | 指定されたジョブ名 |
| `JobDefinition` | `foundation.jobs.psd1` から取得したジョブ定義 |
| `ConfigPath` | 実行時設定ファイルのパス |
| `JobRegistryPath` | ジョブ定義ファイルのパス |
| `Config` | 設定全体 |
| `CommonSettings` | 共通設定 |
| `JobSettings` | 対象ジョブの設定 |
| `Logger` | ログ出力用オブジェクト |
| `Services` | ファイル、ブラウザ、時刻などの共通道具 |
| `Page` | 開いているブラウザページ情報。必要になるまで `$null` のことがある |

`JobName` と `JobDefinition` は同じものではありません。

```text
JobName       = ユーザーが指定する名前
JobDefinition = その名前から引いた、ModulePath / CommandName / DomFeaturePaths などの定義
```

たとえば、`-JobName InstalledAppExport` で実行すると、`JobName` は `InstalledAppExport` です。
その後、`foundation.jobs.psd1` の `Jobs['InstalledAppExport']` から `ModulePath` と `CommandName` が取得され、それが `JobDefinition` に入ります。

---

## 8. 各ジョブの基本構造

各ジョブは、完全に同じ構造ではありません。
ただし、考え方は揃っています。

DOMを使うジョブです。

```text
main/modules/DeviceListExport/
main/modules/InstalledAppExport/
main/modules/ScanTargetSync/
```

これらには、だいたい次のようなファイルがあります。

```text
Runner.ps1
Workflow*.ps1
Dependencies.ps1
DomAdapter.ps1
DomOperations.ps1
Output.ps1
Download.ps1  ※ダウンロードがあるジョブ
Models.ps1    ※結果形状を分けるジョブ
```

DOMを使わないジョブです。

```text
main/modules/LastMonthInstallExtract/
```

こちらは、画面操作ではなくファイル処理が中心です。

```text
Runner.ps1
Workflow.ps1
Input.ps1
Encoding.ps1
DelimitedText.ps1
Rules.ps1
Models.ps1
Output.ps1
Dependencies.ps1
```

Composite Job です。

```text
main/modules/CompositeJobs/CompositeJobs.psm1
```

ここは既存ジョブの連携だけを持ちます。

---

## 9. Runner とは何か

`Runner.ps1` は、そのジョブの開始と終了を担当します。

Runner の主な仕事です。

```text
出力フォルダを準備する
ブラウザを開く、または入力フォルダを確認する
画面や設定が正しいか確認する
Workflow を呼ぶ
結果を出力する
失敗があればエラーにする
```

Runner は、仕事全体を始めて、最後に片付ける係です。
細かい1行ずつの処理順序は、RunnerではなくWorkflowに置きます。

---

## 10. Workflow とは何か

`Workflow*.ps1` は、作業の順番を書いている場所です。

例として、InstalledAppExportなら次のような順番になります。

```text
一覧を開く
  ↓
表示されている行を取る
  ↓
まだ処理していない行だけ選ぶ
  ↓
1行ずつ詳細を開く
  ↓
CSVをダウンロードする
  ↓
詳細を閉じる
  ↓
下にスクロールする
  ↓
次の行を処理する
```

Workflow は作業手順書です。
Workflow の中に、HTML selector や raw CDP 呼び出しを直接書かないようにします。

---

## 11. Dependencies とは何か

`Dependencies.ps1` は、本番用の道具とテスト用の道具を入れ替えやすくする仕組みです。

Workflow は、直接いろいろな外部処理を呼びすぎるとテストしにくくなります。
そこで、必要な道具をまとめて渡します。

例です。

```text
ログを書く道具
画面を読む道具
画面をクリックする道具
ファイルを読む道具
CSVを出す道具
時刻を取得する道具
sleepする道具
```

本番では本物の道具を渡します。
テストでは偽物の道具を渡します。

これにより、ブラウザや実ファイルを使わずにWorkflowをテストできます。

---

## 12. DomAdapter とは何か

`DomAdapter.ps1` は、PowerShell側から見た画面操作の窓口です。

例として、InstalledAppExportには次のような関数があります。

```text
Assert-InstalledAppExportPage
Get-VisibleAssetRows
Open-InstalledAppExportDetailPanel
Open-InstalledAppExportAppTab
Click-InstalledAppExportAppCsvButton
Close-InstalledAppExportDetailPanel
Scroll-InstalledAppExportListDown
```

名前を見ると、業務上やりたいことが分かるようになっています。

`DomAdapter` は、PowerShellとJavaScriptの間の通訳です。
Workflowは `DomAdapter` の名前を呼びます。
実際に画面のどこを探すかは、JavaScript側に置きます。

---

## 13. DomOperations とは何か

`DomOperations.ps1` は、JavaScript helper のどの処理を呼ぶかを決める場所です。

`DomAdapter` が「CSVボタンを押して」と言うと、`DomOperations` がブラウザ内JavaScript helperのoperation呼び出しへ変換します。

`DomOperations` はリモコンのボタン一覧です。

```text
PowerShell側
  ↓
DomAdapter
  ↓
DomOperations
  ↓
Foundation DomHelper
  ↓
window.__FeatureDomHelper の JavaScript helper
```

ここに業務判断を入れないようにします。

---

## 14. dom/features/*.js とは何か

`dom/features/` 配下には、ブラウザ内で動くJavaScriptがあります。

主な場所です。

```text
main/dom/features/device-list-export/
main/dom/features/installed-app-export/
main/dom/features/scan-target-sync/
```

PowerShellは、ブラウザ内のHTMLを直接操作しません。
JavaScriptをブラウザに読み込ませ、そのJavaScriptに画面操作をしてもらいます。

JavaScript側の責務です。

```text
DOMを探す
画面上の値を読む
ボタンをクリックする
スクロールする
チェックボックスを操作する
画面操作後の状態を確認する
```

PowerShell側の責務です。

```text
処理順序を決める
エラー時に止めるか続けるか判断する
CSVを読む・書く
ログを書く
ダウンロード完了を待つ
```

---

## 15. DeviceListExport ジョブの流れ

`DeviceListExport` は、管理画面からデバイス一覧CSVをエクスポートするジョブです。

主なファイルです。

```text
main/modules/DeviceListExport/DeviceListExport.psm1
main/modules/DeviceListExport/internal/Runner.ps1
main/modules/DeviceListExport/internal/Workflow.ps1
main/modules/DeviceListExport/internal/Dependencies.ps1
main/modules/DeviceListExport/internal/DomAdapter.ps1
main/modules/DeviceListExport/internal/DomOperations.ps1
main/modules/DeviceListExport/internal/Download.ps1
main/modules/DeviceListExport/internal/Output.ps1
main/dom/features/device-list-export/contract.js
main/dom/features/device-list-export/navigation.js
main/dom/features/device-list-export/export.js
main/dom/features/device-list-export/index.js
```

処理の流れです。

```text
Invoke-DeviceListExportJob
  ↓
Initialize-DeviceListExportJob
  ↓
出力フォルダと一時フォルダを準備する
  ↓
ブラウザ対象ページを開く
  ↓
DOM bundle を登録する
  ↓
画面契約を確認する
  ↓
操作ボタンをクリックする
  ↓
エクスポートメニューを待つ
  ↓
エクスポートをクリックする
  ↓
CSVダウンロード完了を待つ
  ↓
ファイル名を整える
  ↓
結果を返す
```

見る場所の目安です。

| やりたいこと | 見る場所 |
|---|---|
| 全体の開始・終了を見たい | `Runner.ps1` |
| 操作順序を見たい | `Workflow.ps1` |
| 画面操作名を見たい | `DomAdapter.ps1` |
| JS operationとの対応を見たい | `DomOperations.ps1` |
| ダウンロード待ちを見たい | `Download.ps1` |
| 実際のDOMの探し方を見たい | `dom/features/device-list-export/*.js` |

---

## 16. InstalledAppExport ジョブの流れ

`InstalledAppExport` は、端末一覧から各機器のアプリCSVをダウンロードするジョブです。

主なファイルです。

```text
main/modules/InstalledAppExport/InstalledAppExport.psm1
main/modules/InstalledAppExport/internal/Runner.ps1
main/modules/InstalledAppExport/internal/Workflow.ps1
main/modules/InstalledAppExport/internal/RowAction.ps1
main/modules/InstalledAppExport/internal/Dependencies.ps1
main/modules/InstalledAppExport/internal/DomAdapter.ps1
main/modules/InstalledAppExport/internal/DomOperations.ps1
main/modules/InstalledAppExport/internal/Download.ps1
main/modules/InstalledAppExport/internal/Models.ps1
main/modules/InstalledAppExport/internal/Output.ps1
main/dom/features/installed-app-export/contract.js
main/dom/features/installed-app-export/list.js
main/dom/features/installed-app-export/detail.js
main/dom/features/installed-app-export/apps.js
main/dom/features/installed-app-export/actions.js
main/dom/features/installed-app-export/index.js
```

処理の流れです。

```text
Invoke-InstalledAppExportJob
  ↓
Initialize-InstalledAppExportJob
  ↓
出力フォルダとダウンロードフォルダを準備する
  ↓
ブラウザを開く
  ↓
InstalledAppExport画面か確認する
  ↓
一覧の件数を取る
  ↓
一覧の一番上へ移動する
  ↓
Invoke-InstalledAppExportCsvWorkflow
  ↓
表示中の行を取る
  ↓
未処理行だけ処理する
  ↓
1行ずつ RowAction を実行する
  ↓
詳細パネルを開く
  ↓
アプリタブを開く
  ↓
CSVダウンロードボタンを押す
  ↓
ダウンロード完了を待つ
  ↓
ファイル名を変更する
  ↓
詳細パネルを閉じる
  ↓
下にスクロールする
  ↓
最後まで繰り返す
  ↓
失敗があれば failure CSV を出す
```

`RowAction.ps1` は、1台分のアプリCSV取得を表します。

```text
対象行を開く
詳細パネルを確認する
アプリタブを開く
CSVを出す
ダウンロードを待つ
リネームする
詳細パネルを閉じる
```

これは1つの業務トランザクションです。
見た目が大きくても、機械的に小さな関数へ分割しません。

見る場所の目安です。

| やりたいこと | 見る場所 |
|---|---|
| 全体の開始・終了を見たい | `Runner.ps1` |
| 一覧をどう回しているか見たい | `Workflow.ps1` |
| 1台分の処理を見たい | `RowAction.ps1` |
| CSVダウンロード待ちを見たい | `Download.ps1` |
| 画面操作のPowerShell側を見たい | `DomAdapter.ps1` |
| JS operationとの対応を見たい | `DomOperations.ps1` |
| 実際のHTMLの探し方を見たい | `dom/features/installed-app-export/*.js` |
| 失敗CSVを見たい | `Output.ps1`, `Models.ps1` |

---

## 17. ScanTargetSync ジョブの流れ

`ScanTargetSync` は、入力CSVを読んで、画面上のチェックボックスをON/OFFするジョブです。

主なファイルです。

```text
main/modules/ScanTargetSync/ScanTargetSync.psm1
main/modules/ScanTargetSync/internal/Runner.ps1
main/modules/ScanTargetSync/internal/Workflow.ps1
main/modules/ScanTargetSync/internal/Workflow.Orchestration.ps1
main/modules/ScanTargetSync/internal/Workflow.CsvPlan.ps1
main/modules/ScanTargetSync/internal/Workflow.Page.ps1
main/modules/ScanTargetSync/internal/Workflow.UiScan.ps1
main/modules/ScanTargetSync/internal/Workflow.UiScanState.ps1
main/modules/ScanTargetSync/internal/Workflow.EndpointSync.ps1
main/modules/ScanTargetSync/internal/Workflow.Result.ps1
main/modules/ScanTargetSync/internal/Workflow.Export.ps1
main/modules/ScanTargetSync/internal/Workflow.Fatal.ps1
main/modules/ScanTargetSync/internal/Workflow.State.ps1
main/modules/ScanTargetSync/internal/Workflow.Display.ps1
main/modules/ScanTargetSync/internal/CsvInput.ps1
main/modules/ScanTargetSync/internal/CsvInputFile.ps1
main/modules/ScanTargetSync/internal/Rules.ps1
main/modules/ScanTargetSync/internal/Reconciliation.ps1
main/modules/ScanTargetSync/internal/DomAdapter.ps1
main/modules/ScanTargetSync/internal/DomOperations.ps1
main/modules/ScanTargetSync/internal/Output.ps1
main/dom/features/scan-target-sync/contract.js
main/dom/features/scan-target-sync/list.js
main/dom/features/scan-target-sync/actions.js
main/dom/features/scan-target-sync/index.js
```

処理の流れです。

```text
Invoke-ScanTargetSyncJob
  ↓
入力CSVを読む
  ↓
CSVの列が正しいか確認する
  ↓
各行を見て、チェックON/OFFの希望を決める
  ↓
CSV内のエラーを集める
  ↓
重複endpointがないか確認する
  ↓
ブラウザを開く
  ↓
対象画面か確認する
  ↓
画面の件数とCSVの件数を比較する
  ↓
画面一覧をスキャンしてendpointを集める
  ↓
CSVのendpointと画面のendpointを突き合わせる
  ↓
問題なければ、画面上のチェックボックスをON/OFFする
  ↓
操作後の状態が希望どおりか確認する
  ↓
結果CSVとfailure CSVを出す
```

クリックする前に、先に次の確認をします。

```text
CSVは壊れていないか
endpointは空ではないか
endpointが重複していないか
画面の件数とCSVの件数は合っているか
画面に同じendpointが複数ないか
CSVにあるendpointが画面にもあるか
画面にCSV外のendpointがないか
```

どれか1つでも怪しければ、原則として操作を止めます。

見る場所の目安です。

| やりたいこと | 見る場所 |
|---|---|
| 全体の流れを見たい | `Workflow.Orchestration.ps1` |
| CSV読み込みを見たい | `CsvInput.ps1`, `CsvInputFile.ps1` |
| ON/OFF判定ルールを見たい | `Rules.ps1` |
| endpointの重複や突き合わせを見たい | `Reconciliation.ps1` |
| 画面を開いて確認する部分を見たい | `Workflow.Page.ps1` |
| 画面一覧のスキャンを見たい | `Workflow.UiScan.ps1`, `Workflow.UiScanState.ps1` |
| endpointごとの操作を見たい | `Workflow.EndpointSync.ps1` |
| 結果のまとめを見たい | `Workflow.Result.ps1` |
| 結果・失敗CSV出力を見たい | `Workflow.Export.ps1`, `Output.ps1` |
| fatal時の出力を見たい | `Workflow.Fatal.ps1` |
| 表示用文言を見たい | `Workflow.Display.ps1` |
| 実際の画面操作を見たい | `dom/features/scan-target-sync/*.js` |

---

## 18. LastMonthInstallExtract ジョブの流れ

`LastMonthInstallExtract` は、CSVファイルを読み、アプリのインストール情報を抽出するジョブです。
ブラウザは使いません。

主なファイルです。

```text
main/modules/LastMonthInstallExtract/LastMonthInstallExtract.psm1
main/modules/LastMonthInstallExtract/internal/Runner.ps1
main/modules/LastMonthInstallExtract/internal/Workflow.ps1
main/modules/LastMonthInstallExtract/internal/Input.ps1
main/modules/LastMonthInstallExtract/internal/Encoding.ps1
main/modules/LastMonthInstallExtract/internal/DelimitedText.ps1
main/modules/LastMonthInstallExtract/internal/Rules.ps1
main/modules/LastMonthInstallExtract/internal/Models.ps1
main/modules/LastMonthInstallExtract/internal/Output.ps1
main/modules/LastMonthInstallExtract/internal/Dependencies.ps1
```

処理の流れです。

```text
Invoke-LastMonthInstallExtractJob
  ↓
設定を確認する
  ↓
対象ディレクトリからCSVファイルを探す
  ↓
ファイルをバイト列として読む
  ↓
文字コードを推定する
  ↓
テキストへ変換する
  ↓
区切り文字を判定する
  ↓
CSVレコードに変換する
  ↓
ファイル名から端末名を取る
  ↓
必要ヘッダーを確認する
  ↓
導入日を日付として解釈する
  ↓
対象期間内の行を抽出する
  ↓
結果CSVと失敗CSVを出す
```

見る場所の目安です。

| やりたいこと | 見る場所 |
|---|---|
| 全体の開始・終了を見たい | `Runner.ps1` |
| ファイルごとの処理順序を見たい | `Workflow.ps1` |
| 対象CSVの探索・読み込みを見たい | `Input.ps1` |
| 文字コード判定を見たい | `Encoding.ps1` |
| 区切り文字・CSV変換を見たい | `DelimitedText.ps1` |
| ファイル名、ヘッダー、日付、対象期間の判定を見たい | `Rules.ps1` |
| 結果行・失敗行の形を見たい | `Models.ps1` |
| CSV出力を見たい | `Output.ps1` |

---

## 19. Composite Job の流れ

Composite Job は、既存ジョブを順番に呼ぶ連携ジョブです。

場所はここです。

```text
main/modules/CompositeJobs/CompositeJobs.psm1
```

現在のComposite Jobです。

| ジョブ名 | 流れ |
|---|---|
| `WeeklyScanTargetSync` | `DeviceListExport` → `ScanTargetSync` |
| `MonthlyInstallReport` | `InstalledAppExport` → `LastMonthInstallExtract` |

Composite Job に書いてよいことです。

```text
子Jobを順番に実行する
子Jobの結果を検証する
次のJobに必要なパスをoverrideで渡す
今回実行専用のtimestampディレクトリを作る
連携全体の結果を返す
```

Composite Job に書いてはいけないことです。

```text
DOM操作
CDP操作
CSV列解析
InstalledAppExport内部処理
LastMonthInstallExtract内部処理
ScanTargetSync内部処理
DeviceListExport内部処理
汎用workflow engine
共通化目的だけの別共通module
```

`MonthlyInstallReport` は、毎回 `yyyyMMdd_HHmmss` の専用ディレクトリを作ります。
その配下に `installed_app_export_tmp` と `installed_app_export_downloads` を作り、InstalledAppExportにはこの2つを渡します。
LastMonthInstallExtractには同じ `installed_app_export_downloads` を `TargetDirectory` として渡します。

Composite Job は、InstalledAppExport終了後に成果物CSVが存在することだけを確認します。
CSVの中身、列、行数、PC番号の意味はここでは見ません。
成果物がなければ安全に停止し、次のJobは実行しません。

---

## 20. 画面一覧をスクロールしながら処理する仕組み

一覧画面は、全件が一度に表示されないことがあります。
そのため、見えている行を処理し、下にスクロールし、また見えている行を処理します。

InstalledAppExportは共通基盤のこれを使います。

```text
main/modules/Foundation/internal/ScrollableList.ps1
```

処理の考え方です。

```text
今見えている行を取る
  ↓
まだ処理していない行だけ処理する
  ↓
下にスクロールする
  ↓
また見えている行を取る
  ↓
最後まで繰り返す
```

ScanTargetSyncは、専用のUIスキャン処理を持っています。

```text
main/modules/ScanTargetSync/internal/Workflow.UiScan.ps1
main/modules/ScanTargetSync/internal/Workflow.UiScanState.ps1
main/modules/ScanTargetSync/internal/Workflow.EndpointSync.ps1
```

理由は、ScanTargetSyncでは「画面に存在するendpointの完全性確認」と「チェックボックス操作」が重要だからです。
単に見えている行を処理するだけではなく、CSVと画面の一致確認を行います。

---

## 21. Contract とは何か

このプロジェクトでは `Contract` という言葉が出てきます。

意味は、**関数の返り値の形についての約束**です。

たとえば、画面から行を取る処理では、次のような情報が必要です。

```text
成功したか
行の一覧
失敗理由
件数
```

JavaScript側の返り値が毎回バラバラだと、PowerShell側は安全に処理できません。
そのため、JavaScript側とPowerShell側で返す形を約束します。

Contractは、PowerShellとJavaScriptの間の約束です。

---

## 22. DOM helper が無い時の考え方

次のような helper が無い状態は、通常のDOM揺れではありません。

```text
window.__DeviceListExportDomHelper
window.__InstalledAppExportDomHelper
window.__ScanTargetSyncDomHelper
```

これは、DOM bundleが注入されていない、対象ページが違う、または自動化基盤が壊れている状態として扱います。

そのため、一覧取得で空配列を返してごまかしたり、チェック操作で `ok=false` として処理を続けたりしません。
契約確認では診断しやすい契約失敗として返し、業務操作では安全に停止します。

---

## 23. 失敗時の考え方

このプロジェクトでは、失敗したときに理由を残します。

代表的な失敗です。

```text
対象ページが見つからない
DOM helperが読み込まれていない
対象の行が見つからない
詳細パネルが開けない
CSVボタンが押せない
ダウンロードが終わらない
画面の件数とCSVの件数が合わない
チェックボックス操作後の状態が合わない
CSVのヘッダーが期待と違う
日付が解釈できない
```

失敗は大きく2種類あります。

| 種類 | 意味 |
|---|---|
| 行単位の失敗 | その行だけ失敗として記録し、次に進める可能性がある |
| 全体を止める失敗 | 続けると危険なので処理を止める |

特に `ScanTargetSync` は、怪しいときに操作を止める方針です。
画面のチェック状態を誤って変更する方が危険だからです。

---

## 24. テストの読み方

テストはここにあります。

```text
main/tests/
main/tests/js/
```

PowerShellのテストはPesterです。
JavaScriptのテストはNode.jsで実行します。

主なテスト名です。

| テスト名 | 何を見ているか |
|---|---|
| `Foundation.*.Tests.ps1` | 共通基盤のテスト |
| `DeviceListExport.*.Tests.ps1` | DeviceListExportのテスト |
| `InstalledAppExport.*.Tests.ps1` | InstalledAppExportのテスト |
| `ScanTargetSync.*.Tests.ps1` | ScanTargetSyncのテスト |
| `LastMonthInstallExtract.*.Tests.ps1` | LastMonthInstallExtractのテスト |
| `CompositeJobs.Tests.ps1` | Composite Jobのテスト |
| `Architecture.Tests.ps1` | 設計ルールを守っているか |
| `Dom.OperationRegistryContract.Tests.ps1` | DOM操作名とJS側の契約がズレていないか |
| `tests/js/*.test.js` | JavaScript側のテスト |

テストは、単なる動作確認ではありません。
設計境界を守るための仕様でもあります。

例です。

```text
ScanTargetSyncの判定ルールを直す
  → ScanTargetSync.Rules.Tests.ps1 を見る

InstalledAppExportのダウンロード待ちを直す
  → InstalledAppExport.Download.Tests.ps1 を見る

LastMonthInstallExtractの文字コード判定を直す
  → LastMonthInstallExtract.Encoding.Tests.ps1 を見る

Composite Jobの連携順序を直す
  → CompositeJobs.Tests.ps1 を見る
```

---

## 25. 修正したいときの探し方

### 画面のボタンやHTMLが変わったとき

見る場所です。

```text
main/dom/features/**/*.js
main/modules/*/internal/DomAdapter.ps1
main/modules/*/internal/DomOperations.ps1
```

実際にHTMLを探しているのはJavaScript側です。
ただし、PowerShell側の関数名から辿る方が安全です。

### CSVの列名や出力形式を変えたいとき

見る場所です。

```text
CsvInput.ps1
Input.ps1
Rules.ps1
Models.ps1
Output.ps1
Workflow.Result.ps1
Workflow.Export.ps1
```

CSVの読み込み、判定、結果の形、出力はPowerShell側です。
JavaScript側には置きません。

### 作業の順番を変えたいとき

見る場所です。

```text
Workflow*.ps1
Runner.ps1
```

処理順序はWorkflowにあります。
開始・終了・最終検査はRunnerにあります。

### ジョブの追加や読み込み先を変えたいとき

見る場所です。

```text
main/config/foundation.jobs.psd1
main/config/foundation.config.psd1
main/modules/Foundation/internal/JobRegistry.ps1
```

ジョブ名、モジュール、呼び出し関数、DOM bundleの対応は `foundation.jobs.psd1` が持ちます。
実行時設定は `foundation.config.psd1` が持ちます。

### ブラウザ通信まわりを直したいとき

見る場所です。

```text
main/modules/Foundation/internal/Cdp*.ps1
main/modules/Foundation/internal/DomHelper.ps1
main/modules/Foundation/internal/DomBundle.ps1
```

ここは全DOM系ジョブに影響します。
局所的な画面変更なら、まず `dom/features/**/*.js` を疑います。

---

## 26. 修正前に考えること

修正前に、次の質問をします。

```text
これはどのJobの話か
これは作業順番の問題か
これは画面の探し方の問題か
これはCSV入力の問題か
これはCSV出力の問題か
これは設定の問題か
これは全ジョブ共通の問題か
これはComposite Jobの連携の問題か
```

答えによって見る場所が変わります。

| 問題 | 見る場所 |
|---|---|
| 作業順番 | `Workflow*.ps1` |
| 画面の探し方 | `dom/features/**/*.js` |
| PowerShellから画面操作を呼ぶ部分 | `DomAdapter.ps1`, `DomOperations.ps1` |
| CSV入力 | `CsvInput.ps1`, `Input.ps1` |
| CSV出力 | `Output.ps1`, `Workflow.Export.ps1` |
| 結果の形 | `Models.ps1`, `Workflow.Result.ps1` |
| 判定ルール | `Rules.ps1` |
| CSVと画面の突き合わせ | `Reconciliation.ps1` |
| 設定 | `config/*.psd1` |
| 全体共通 | `modules/Foundation/` |
| ジョブ連携 | `modules/CompositeJobs/CompositeJobs.psm1` |

---

## 27. やってはいけない直し方

### 1. WorkflowにHTMLの探し方を書かない

悪い例です。

```text
Workflow.ps1 の中に CSS selector や DOM の細かい条件を書く
```

画面の細かい探し方はJavaScript側に置きます。

### 2. JavaScriptにCSV出力処理を書かない

CSV出力はPowerShell側の仕事です。
JavaScriptは画面を読む・押す・スクロールするだけにします。

### 3. Foundationに機能固有の処理を書かない

`Foundation` は共通基盤です。
特定Jobだけのルールを入れると、後から混乱します。

### 4. Composite Jobに子Jobの内部処理を書かない

Composite Jobは連携だけを持ちます。
子JobのDOM操作、CSV解析、業務判定は持ちません。

### 5. テストだけを直して本体を直さない

テストが落ちたときは、まず本体のバグを疑います。
期待値だけ変えるのは危険です。

### 6. 失敗理由を消さない

失敗理由は、運用時の調査に必要です。
エラー処理を直すときは、CSVやログに理由が残るか確認します。

---

## 28. 変更するときの安全な手順

基本手順です。

```text
1. どのJobの話か決める
2. どの種類の問題か決める
3. 対応するファイルを1〜2個だけ読む
4. 対応するテストを読む
5. 小さく直す
6. その機能のテストを動かす
7. 必要なら全体テストを動かす
```

最初から全ファイルを読まないようにします。
読む範囲を絞ることが、保守時の事故防止になります。

---

## 29. 具体例：ScanTargetSyncの判定ルールを変える場合

たとえば、最終通信日から何日経ったらチェックをONにするかを変える場合です。

見る順番です。

```text
1. main/modules/ScanTargetSync/internal/Rules.ps1
2. main/tests/ScanTargetSync.Rules.Tests.ps1
3. main/modules/ScanTargetSync/internal/Workflow.CsvPlan.ps1
4. main/tests/ScanTargetSync.Workflow.Tests.ps1
```

最初に `Rules.ps1` を見ます。
ここにON/OFFの判定があります。

次に `ScanTargetSync.Rules.Tests.ps1` を見ます。
ここに「こういう入力ならON」「こういう入力ならOFF」というテストがあります。

この変更では、画面操作のJavaScriptを最初に見る必要はありません。
判定ルールの変更だからです。

---

## 30. 具体例：InstalledAppExportのCSVボタンが押せなくなった場合

見る順番です。

```text
1. main/modules/InstalledAppExport/internal/DomAdapter.ps1
2. main/modules/InstalledAppExport/internal/DomOperations.ps1
3. main/dom/features/installed-app-export/*.js
4. main/tests/InstalledAppExport.DomOperations.Tests.ps1
5. main/tests/js/installed-app-export.dom.behavior.test.js
```

原因は画面HTMLの変更かもしれません。
ただし、いきなりJavaScript全体を読むのではなく、PowerShell側の関数名から辿ります。

手がかりです。

```text
Click-InstalledAppExportAppCsvButton
```

この名前を起点に、DomAdapter、DomOperations、JavaScript helperへ辿ります。

---

## 31. 具体例：出力CSVの列を変える場合

対象Jobによって見る場所が違います。

### InstalledAppExportのfailure CSVを変える場合

```text
1. main/modules/InstalledAppExport/internal/Models.ps1
2. main/modules/InstalledAppExport/internal/Output.ps1
3. main/tests/InstalledAppExport.Output.Tests.ps1
```

### ScanTargetSyncの結果・失敗CSVを変える場合

```text
1. main/modules/ScanTargetSync/internal/Output.ps1
2. main/modules/ScanTargetSync/internal/Workflow.Result.ps1
3. main/modules/ScanTargetSync/internal/Workflow.Export.ps1
4. main/tests/ScanTargetSync.Output.Tests.ps1
5. main/tests/ScanTargetSync.Workflow.Tests.ps1
```

### LastMonthInstallExtractの結果・失敗CSVを変える場合

```text
1. main/modules/LastMonthInstallExtract/internal/Models.ps1
2. main/modules/LastMonthInstallExtract/internal/Output.ps1
3. main/modules/LastMonthInstallExtract/internal/Workflow.ps1
4. main/tests/LastMonthInstallExtract.Output.Tests.ps1
5. main/tests/LastMonthInstallExtract.Workflow.Tests.ps1
```

出力CSVの変更では、画面操作のJavaScriptを触らないことが多いです。

---

## 32. このプロジェクトでよく出る言葉

| 言葉 | 意味 |
|---|---|
| Job | 実行する仕事。DeviceListExport / InstalledAppExport / ScanTargetSync / LastMonthInstallExtractなど |
| Composite Job | 既存Jobを順番に呼ぶ連携Job |
| Runner | 仕事の開始と終了を担当する係 |
| Workflow | 作業の順番を書いたもの |
| Adapter | 直接触りにくいものを、触りやすい形にする窓口 |
| DOM | ブラウザ画面の中のHTML構造 |
| DomAdapter | PowerShellから画面操作を呼ぶ窓口 |
| DomOperations | JavaScript操作を呼ぶためのボタン一覧 |
| Contract | 返すデータの形の約束 |
| Dependency | Workflowに渡す道具 |
| Port | 差し替えできる道具の差し込み口 |
| Mock / Fake | テスト用の偽物 |
| Failure CSV | 失敗した行と理由を書いたCSV |
| CDP | PowerShellからブラウザを操作するための通信方式 |
| DOM bundle | ブラウザに注入するJavaScript一式 |
| endpoint | ScanTargetSyncでCSVと画面行を突き合わせるキー |

---

## 33. 最初に読むおすすめ順

次の順番で読むと、依存の向きを追いやすくなります。

### Step 1: 入口とジョブ定義

```text
main/run_job.ps1
main/config/foundation.jobs.psd1
main/config/foundation.config.psd1
main/modules/Foundation/internal/Bootstrap.ps1
main/modules/Foundation/internal/RunContext.ps1
```

ここで、`JobName` からどのモジュール・どの関数が呼ばれるかを見ます。

### Step 2: まずDeviceListExportを1本通して読む

```text
main/modules/DeviceListExport/DeviceListExport.psm1
main/modules/DeviceListExport/internal/Runner.ps1
main/modules/DeviceListExport/internal/Workflow.ps1
main/modules/DeviceListExport/internal/DomAdapter.ps1
main/modules/DeviceListExport/internal/DomOperations.ps1
```

DeviceListExportはDOM系ジョブの中では流れが短めです。
最初に読む対象として向いています。

### Step 3: InstalledAppExportでRowActionを読む

```text
main/modules/InstalledAppExport/internal/Runner.ps1
main/modules/InstalledAppExport/internal/Workflow.ps1
main/modules/InstalledAppExport/internal/RowAction.ps1
main/modules/InstalledAppExport/internal/DomAdapter.ps1
```

ここで、1行分の業務トランザクションを理解します。

### Step 4: ScanTargetSyncでPolicyとWorkflowの分離を見る

```text
main/modules/ScanTargetSync/internal/Rules.ps1
main/modules/ScanTargetSync/internal/Reconciliation.ps1
main/modules/ScanTargetSync/internal/Workflow.Orchestration.ps1
main/modules/ScanTargetSync/internal/Workflow.UiScan.ps1
main/modules/ScanTargetSync/internal/Workflow.EndpointSync.ps1
```

ここでは、画面操作前の安全確認が重要です。

### Step 5: LastMonthInstallExtractでDOMなしジョブを見る

```text
main/modules/LastMonthInstallExtract/internal/Workflow.ps1
main/modules/LastMonthInstallExtract/internal/Input.ps1
main/modules/LastMonthInstallExtract/internal/Encoding.ps1
main/modules/LastMonthInstallExtract/internal/DelimitedText.ps1
main/modules/LastMonthInstallExtract/internal/Rules.ps1
main/modules/LastMonthInstallExtract/internal/Output.ps1
```

DOMがなくても、Input / Rules / Output / Workflow の分離に意味があることを確認します。

### Step 6: CompositeJobsを見る

```text
main/modules/CompositeJobs/CompositeJobs.psm1
main/tests/CompositeJobs.Tests.ps1
```

ここでは、子Job内部に踏み込んでいないことを確認します。

### Step 7: テストを見る

```text
main/tests/Architecture.Tests.ps1
main/tests/Dom.OperationRegistryContract.Tests.ps1
main/tests/*.*.Tests.ps1
main/tests/js/*.test.js
```

テストは設計境界を守る仕様です。

---

## 34. 迷ったとき

迷ったら、次の順番で考えます。

```text
これは何のJobか
これは作業順番か、画面操作か、CSVか、設定か
PowerShell側の話か、JavaScript側の話か
本番の動きか、テスト用の差し替えか
子Job単体の話か、Composite Jobの連携の話か
```

この問いで、見る場所を絞ります。

---

## 35. 最小理解セット

まずはこれだけ理解します。

```text
run_job.ps1 は入口
Foundation は共通準備
foundation.jobs.psd1 は JobName と実装の地図
foundation.config.psd1 は実行時設定
Context は実行中の情報の箱
Runner は開始と終了
Workflow は作業の順番
Dependencies は本番用・テスト用の道具箱
DomAdapter は画面操作の窓口
DomOperations はJavaScript呼び出しのボタン一覧
dom/features/*.js は実際に画面を触る
Rules は業務判断
Reconciliation は突き合わせ
Output はCSVを出す
CompositeJobs は既存Jobを順番に呼ぶだけ
```

---

## 36. SRP/DIPをやりすぎないための読み方

このプロジェクトでは、SRP/DIPを意識します。
ただし、JavaやC#のようにinterfaceやclass階層を増やす方向にはしません。

PowerShell 5.1では、次のもので依存の向きを管理します。

```text
関数
ScriptBlock
依存オブジェクト
pscustomobject
```

やらないことです。

```text
IDomOperations.ps1 のようなinterfaceファイルを作る
IoC container や service locator を作る
1操作1ファイルに細かく分ける
1行ラッパー関数を大量に作る
似ているだけで共通ファイルへ抜き出す
```

`Workflow` は作業順番を読みやすくする場所です。
`DomAdapter` は画面操作の窓口です。
`DomOperations` はJavaScript helperを呼ぶためのoperation表です。
JavaScript側は、selectorとDOM契約を業務意味として表します。

---

## 37. InstalledAppExport RowAction はなぜ大きく見えてよいのか

`InstalledAppExport` の `RowAction.ps1` は、1台分のアプリCSV取得という業務トランザクションです。

```text
行を開く
詳細パネルを確認する
アプリタブを開く
CSVを出す
ダウンロードを待つ
ファイル名を変える
詳細パネルを閉じる
```

これは1つの業務単位として読めます。
そのため、機械的に小さな関数やファイルへ分けません。

ただし、次のものは持たせません。

```text
selectorの詳細
raw DOM helper
raw CDP
raw file I/O
直接の時刻取得
直接のsleep
```

---

## 38. 似ているコードの扱い

`DeviceListExport`、`ScanTargetSync`、`InstalledAppExport` は、似ていても安易に共通ファイルへ抜き出しません。
ジョブごとの読みやすさと変更影響範囲を優先します。

ただし、同じ意味の `DomOperations` 骨格は、機能名やhelper名以外をできるだけ同じ書き方にします。
特に次は揃えます。

```text
helper未登録時の扱い
Await の扱い
契約scopeの渡し方
operation名とJavaScript側の対応
```

---

## 39. 抽象を残すか消すかの判断

抽象を残す理由は、SOLID原則そのものではありません。
残す価値があるのは、次のような場合です。

```text
ブラウザ操作を隠している
DOMの詳細を隠している
ファイルI/Oを隠している
時刻やsleepを差し替え可能にしている
テストで差し替えるために存在している
業務判断を外部I/Oなしでテストできるようにしている
変更理由が呼び出し元と違う
エラー診断を安定させている
```

削除・統合を検討してよいのは、次を満たす場合だけです。

```text
1. そのファイル・関数が1行ラッパーに近い
2. 呼び出し元の知識量を減らしていない
3. テスト差し替えに使われていない
4. 変更理由が呼び出し元と同じ
5. 統合しても依存方向が悪化しない
6. Architecture.Testsに反しない
```

逆に、次のものは簡単に消しません。

```text
Dependencies.ps1
DomAdapter.ps1
DomOperations.ps1
Rules.ps1
Reconciliation.ps1
Download.ps1
Output.ps1
Models.ps1
Encoding.ps1
DelimitedText.ps1
```

これらは、単なる飾りではなく、変更理由やテスト境界を分けるために存在しています。

---

## 40. Composite Job の保守方針

`WeeklyScanTargetSync` と `MonthlyInstallReport` は、Featureではなく薄いComposite Jobです。
置き場所はここです。

```text
main/modules/CompositeJobs/CompositeJobs.psm1
```

個別に次のようなモジュールを作りません。

```text
main/modules/WeeklyScanTargetSync/
main/modules/MonthlyInstallReport/
```

Composite Jobから子Jobを起動するときは、親Contextの `ConfigPath` と `JobRegistryPath` を子Jobへ渡します。
カスタムconfigやカスタムjob registryで起動した親Jobの子Jobだけがデフォルトconfigへ戻る状態は、連携Jobの意味を壊します。

`LastMonthInstallExtract` 単独実行は、手動確認・例外対応・再処理用です。
単独実行時は、従来どおりconfigの `Jobs.LastMonthInstallExtract.TargetDirectory` を使います。

`LastMonthInstallExtract` に次の処理を追加しません。

```text
最新timestampディレクトリ探索
重複ファイル判定
InstalledAppExport履歴判定
```

それらは `MonthlyInstallReport` 側の実行単位で扱う話です。
