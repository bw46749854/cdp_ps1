# main/modules/LastMonthInstallExtract/internal/Runner.ps1

## 1. このファイルを一言でいうと

`LastMonthInstallExtract` ジョブの入口です。設定を検証し、依存関係を解決し、出力先を初期化し、Workflowを実行し、最後にCSV出力とサマリログ出力を行います。

## このファイルを変更する典型ケース

- Job開始時の初期化、依存解決、最終結果検査が変わった場合
- Context / Config / JobSettings の渡し方が変わった場合
- Workflow呼び出し前後のログや終了判定が変わった場合


## 2. このファイルが担当する範囲

- `Jobs.LastMonthInstallExtract` の必須設定確認。
- 出力ディレクトリの初期化。
- 前月判定範囲の作成。
- `Invoke-LastMonthInstallExtractInstallationWorkflow` の呼び出し。
- 成功CSV・失敗CSVの出力。
- 実行結果サマリのログ出力。

## 3. このファイルが担当しない範囲

- CSVの読み取り処理そのもの。
- 文字コード判定。
- CSV/TSVパース。
- 導入日が前月かどうかの判定。

それらは `Workflow.ps1`、`Encoding.ps1`、`DelimitedText.ps1`、`Rules.ps1` に委譲します。

## 4. 関数呼び出しツリー

```text
Invoke-LastMonthInstallExtractJob
  ├─ Assert-LastMonthInstallExtractJobSettings
  ├─ Resolve-LastMonthInstallExtractJobDependencies
  ├─ Initialize-LastMonthInstallExtractOutputDirectory
  │   └─ Dependencies.Output.InitializeOutputDirectory
  ├─ New-LastMonthInstallExtractJobDateRange
  │   ├─ Dependencies.Timing.Now
  │   └─ New-LastMonthInstallExtractMonthlyDateRange
  ├─ Invoke-LastMonthInstallExtractInstallationWorkflow
  ├─ Export-LastMonthInstallExtractJobResults
  │   ├─ ExportInstallationCsv callback
  │   └─ ExportFailureCsv callback
  ├─ Write-LastMonthInstallExtractWorkflowSummary
  │   ├─ Logger.WriteSection
  │   ├─ Logger.WriteInfo
  │   └─ Logger.WriteWarning
  └─ return result object
```

## 5. 関数ごとの説明

### Assert-LastMonthInstallExtractJobSettings

`TargetDirectory` と `OutputCsvFileName` が設定されているか確認します。

この2つがない場合、どこからCSVを読むか、どこへ出力するかが決まりません。そのため、処理継続せずに例外で止めます。

### Initialize-LastMonthInstallExtractOutputDirectory

`TargetDirectory` を出力ディレクトリとして初期化します。

`LastMonthInstallExtract` は入力CSVを読むディレクトリと、結果CSVを書き込むディレクトリが同じです。そのため、まずこのディレクトリが存在し、安全に使える状態か確認します。

### New-LastMonthInstallExtractJobDateRange

依存関係の `Timing.Now` callback から現在日時を取得し、`New-LastMonthInstallExtractMonthlyDateRange` で前月範囲を作ります。

直接 `Get-Date` を呼ばないのは、テストで「現在日付」を固定できるようにするためです。

### Export-LastMonthInstallExtractJobResults

Workflowが返した `InstallationRows` と `FailureRows` を、それぞれCSVへ出力します。

| 出力 | 内容 |
|---|---|
| InstallationCsv | 前月インストール対象として抽出された成功行 |
| FailureCsv | ファイル単位・行単位の失敗やスキップ理由 |

失敗行が0件の場合、失敗CSVは作成せず、古い失敗CSVがあれば削除します。

### Write-LastMonthInstallExtractWorkflowSummary

処理結果をログにまとめます。

出力する主な情報は、対象ディレクトリ、出力CSV、前月判定範囲、入力CSV数、処理CSV数、スキップCSV数、読み取り行数、出力件数です。

失敗行がある場合は warning、ない場合は info として出力します。

### Invoke-LastMonthInstallExtractJob

外部から呼ばれる唯一の入口です。

`run_job.ps1 -JobName LastMonthInstallExtract` の最終的な実行先はこの関数です。

## 6. 戻り値の形

```text
LastMonthInstallExtractJobResult
  DateRange
    Today
    StartInclusive
    EndExclusive
  WorkflowResult
    InstallationRows
    FailureRows
    InputFileCount
    ProcessedFileCount
    SkippedFileCount
    ReadRowCount
    MatchedRowCount
  ExportResult
    InstallationCsv
    FailureCsv
    OutputPath
    FailurePath
```

## 7. PowerShell文法上のポイント

`Get-LastMonthInstallExtractCallbackScriptBlock` で取得した callback は、`& $callback` または `.Invoke()` で実行されます。

このプロジェクトでは、実処理の直接呼び出しではなく、callback経由にすることでテスト時に入出力処理を差し替えられるようにしています。

## 8. 変更時の注意

`Invoke-LastMonthInstallExtractInstallationWorkflow` より前にCSV出力を置いてはいけません。出力はWorkflow結果が確定してから行うべきです。

`New-LastMonthInstallExtractJobDateRange` で直接 `Get-Date` を使うと、テストで前月範囲を固定できなくなります。

設定検証を弱めると、空の出力先や存在しないディレクトリに対する後続エラーが分かりにくくなります。

## 9. 関連するテスト

- `LastMonthInstallExtract.Runner.Tests.ps1`: 出力初期化、Workflow呼び出し、CSV出力、サマリログ、設定不足時の例外を確認する。
- `LastMonthInstallExtract.Architecture.Tests.ps1`: Runnerが直接I/OやDOM/CDPに依存しないことを確認する。
