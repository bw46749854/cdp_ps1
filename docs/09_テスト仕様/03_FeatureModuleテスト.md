# Feature module テスト

## 1. 対象

このドキュメントでは、Feature moduleごとのテストを整理する。

対象は以下である。

```text
DeviceListExport.*.Tests.ps1
InstalledAppExport.*.Tests.ps1
ScanTargetSync.*.Tests.ps1
LastMonthInstallExtract.*.Tests.ps1
CompositeJobs.Tests.ps1
TestSupport.Tests.ps1
```

## 2. DeviceListExport

### DeviceListExport.DomOperations.Tests.ps1

DeviceListExportのPowerShell DOM境界を固定する。

主な仕様は以下である。

```text
- DeviceListExportはFoundation共通のDOM bundle登録入口を使う
- DOM operation定義は完整である
- 未定義operation keyは拒否する
- contract operationではhelper不在を契約失敗として扱う
- workflow action / wait predicateでは、それぞれ意図したmissing-helper modeを使う
- async DOM actionではoperation metadataのAwait設定を使う
```

対応するプロダクトファイルは以下である。

```text
modules/DeviceListExport/internal/DomOperations.ps1
modules/DeviceListExport/internal/DomAdapter.ps1
modules/DeviceListExport/internal/Workflow.ps1
```

## 3. InstalledAppExport

### InstalledAppExport.BrowserBoundary.Tests.ps1

InstalledAppExportがブラウザを開くとき、直接CDPではなくBrowser service portを使うことを固定する。

特に、page identity matcherを使って対象画面を誤らないようにする契約を守る。

### InstalledAppExport.DomOperations.Tests.ps1

InstalledAppExportのPowerShell DOM operation定義を固定する。

守っていることは以下である。

```text
- DOM bundle登録は共通入口を使う
- operation定義が揃っている
- 未定義operationは拒否する
- helper不在を隠さず、適切なcontract failureやmissing-helper behaviorにする
- PowerShell operationがFoundation DOM helperへ正しいhelper名 / method名 / argumentsを渡す
```

### InstalledAppExport.Download.Tests.ps1

InstalledAppExportのCSVダウンロード待ち・リネームを固定する。

代表仕様は以下である。

```text
- .crdownload / .tmp / .download などの一時ファイルを完了扱いしない
- CSV候補が複数ある場合は誤選択しない
- サイズ安定を待つ
- ファイルロック中は読み取り可能になるまで待つ
- 端末名つきファイル名へリネームする
```

### InstalledAppExport.Models.Tests.ps1

成功結果、失敗結果、行キーなどのデータ構造を固定する。

### InstalledAppExport.Output.Tests.ps1

失敗CSV出力の列と安全性を固定する。

### InstalledAppExport.Workflow.Rows.Tests.ps1

端末一覧全体のWorkflowと、1行ごとのRowAction接続を固定する。

主な仕様は以下である。

```text
- 一覧行を重複処理しない
- 成功行と失敗行を集約する
- RowAction失敗時も一覧全体の処理継続方針に従う
- 共通ScrollableList workflowへcallbackを渡す
- RowActionは業務トランザクションとして扱う
```

対応するプロダクトファイルは以下である。

```text
modules/InstalledAppExport/internal/Runner.ps1
modules/InstalledAppExport/internal/Workflow.ps1
modules/InstalledAppExport/internal/RowAction.ps1
modules/InstalledAppExport/internal/Dependencies.ps1
modules/InstalledAppExport/internal/Download.ps1
modules/InstalledAppExport/internal/Output.ps1
```

## 4. ScanTargetSync

### ScanTargetSync.Rules.Tests.ps1

チェックON/OFF判定の業務ルールを固定する。

代表仕様は以下である。

```text
- 手動スキャンの完了が空またはハイフンならON対象
- 経過日数が閾値以上ならON対象
- 閾値未満ならOFF対象
- 手動スキャンの完了日が不正ならCSVエラー
- 最終通信日時が手動スキャン完了より古い場合はCSVエラー
- ON行、OFF行、CSVエラー行を1回の処理で分類する
```

このテストが落ちた場合、単なる実装修正ではなく、業務ルール変更かどうかを確認する。

### ScanTargetSync.CsvInput.Tests.ps1 / CsvInputFile.Tests.ps1

Vendor CSVの入力契約を固定する。

```text
- 必須列を持つ行を受け入れる
- 空CSVを拒否する
- 必須列不足を拒否する
- ISO 8601 offset timestampを表示上の日付に正規化する
- 日本語日付文字列を解析する
- blank / hyphen / unparseable dateはnullとして扱う
- comma CSV / tab TSVを読み分ける
- CSV path空、ファイル不存在、先頭行空はエラー
```

### ScanTargetSync.Reconciliation.Tests.ps1

CSV側データとUI側データの突き合わせを固定する。

```text
- ON / OFF分類からsync rowを作る
- CSV error rowがある場合はsync row作成を拒否する
- CSV内のendpoint重複を検出する
- sync row内のendpoint重複を拒否する
- workflow scanning用のendpoint lookup indexを作る
```

### ScanTargetSync.Workflow.Tests.ps1 / Workflow.Normal.Tests.ps1

ScanTargetSync全体Workflowの正常系・異常系を固定する。

代表仕様は以下である。

```text
正常系:
  CSV件数、UI件数、checkbox同期件数が一致すれば完了

異常系:
  CSVデータエラーがあればCDP前に止まる
  CSV分類件数が不整合ならCDP前に止まる
  sync row件数が不整合ならCDP前に止まる
  input CSVにデータ行がなければCDP前に止まる
  UI total countが0ならcheckbox変更前に止まる
  CSV件数とUI件数が違えばcheckbox変更前に止まる
```

このテスト群は、`Workflow.Orchestration.ps1`、`Workflow.CsvPlan.ps1`、`Workflow.Page.ps1`、`Workflow.UiScan.ps1`、`Workflow.EndpointSync.ps1`、`Workflow.Result.ps1` の接続を守る。

### ScanTargetSync.Dependencies.Tests.ps1

ScanTargetSync Workflowの依存注入境界を固定する。

```text
- supplied dependency portを保持する
- Browser / Dom port経由でページを開き検証する
- endpoint action port経由でvisible endpointsを同期する
```

### ScanTargetSync.BrowserBoundary.Tests.ps1

Browser service境界を固定する。

```text
- page identity matcherをDependenciesで作る
- readiness assertionなしの軽量DOM operationでpage identityを判定する
- DOM contractでページを開いてからDOM portsで検証する
- CSV/UI件数不一致ならスクロール前に止まる
```

### ScanTargetSync.FileSystemBoundary.Tests.ps1 / Output.Tests.ps1

出力ディレクトリ初期化と失敗CSV出力の安全性を固定する。

## 5. LastMonthInstallExtract

### LastMonthInstallExtract.Rules.Tests.ps1

LastMonthInstallExtractの業務ルールを固定する。

```text
- 想定CSVファイル名から端末名を抽出する
- 想定外ファイル名を拒否する
- 必須ヘッダーは完全一致・順序一致が必要
- supported installation date formatを解析する
- injected current dateから前月範囲を作る
```

### LastMonthInstallExtract.Encoding.Tests.ps1

文字コード判定を固定する。

```text
- UTF-8 without BOMをstrictに読む
- UTF-8 BOMを認識してBOMを除去する
- UTF-16 LE / BE BOMを読む
- UTF-32 LE / BE BOMを読む
- supported textとしてdecodeできない場合はencoding guessを返す
- 空ファイルを拒否する
```

### LastMonthInstallExtract.DelimitedText.Tests.ps1

CSV / TSV parserを固定する。

```text
- 先頭行にtabがあればTSV
- defaultはcomma CSV
- quoted comma / escaped quote / quoted newlineを解析する
- 列数不一致行はmalformedとして扱う
- 閉じていないquoteはthrowする
```

### LastMonthInstallExtract.Workflow.Tests.ps1

LastMonthInstallExtract Workflow全体を固定する。

```text
- 前月インストール行だけ抽出する
- invalid headersのファイルはworkflow停止せずskipped fileに記録する
- TSVも同じworkflow境界で処理する
- malformed rowはrow failureとして記録し処理を継続する
- workflow-only dependenciesを使う
```

### LastMonthInstallExtract.Runner.Tests.ps1

LastMonthInstallExtractジョブ入口を固定する。

```text
- workflow前に出力初期化する
- workflow後にCSVをexportする
- result objectを返す
- standalone実行ではconfig TargetDirectoryを使う
- 必須JobSettings不足ならthrow
- FailureCsvFileName省略時はdefault名を使う
- skipped/failed rowsがあればwarning summaryを出す
```

### LastMonthInstallExtract.Output.Tests.ps1 / Input.Tests.ps1 / Models.Tests.ps1 / Dependencies.Tests.ps1

Input、Output、Models、Dependenciesの境界を固定する。

## 6. CompositeJobs

### CompositeJobs.Tests.ps1

CompositeJobsは、既存ジョブを順番に呼ぶ連携ジョブである。

守っている仕様は以下である。

```text
WeeklyScanTargetSync:
  DeviceListExportを実行する
  ExportedCsvPathを検証する
  ScanTargetSyncへInputCsvPath overrideとして渡す

MonthlyInstallReport:
  月次ディレクトリを作成する
  InstalledAppExportへDownloadDirectory overrideを渡す
  InstalledAppExportの出力先をLastMonthInstallExtractのTargetDirectoryとして渡す
```

CompositeJobsが子ジョブ内部のCSV解析やDOM操作に踏み込まないことが重要である。

## 7. TestSupport

### TestSupport.ps1 / TestSupport.Tests.ps1

テスト用のfake port / fake contextを提供する。

```text
- logger callを記録する
- filesystem boundary callを記録する
- browser callを記録する
- Foundation-like contextを作る
- 必要な場合だけ実ディレクトリ操作を行う
```

プロダクト本体ではないが、DependenciesやServices境界をテストするために重要である。
