# LastMonthInstallExtractの読み方

## 1. この機能を一言でいうと

`LastMonthInstallExtract` は、複数台のPCから取得済みのアプリ一覧CSVを読み、前月にインストールされたアプリだけを1つのCSVに集約するジョブです。

このジョブはブラウザを開きません。CDPもDOM helperも使いません。

## 2. 他の機能との違い

| 観点 | DOM系ジョブ | LastMonthInstallExtract |
|---|---|---|
| 主な入力 | ブラウザ画面 | ディレクトリ内CSV |
| 主な出力 | ダウンロードCSV、画面状態変更 | 集約CSV、失敗CSV |
| 低レベル依存 | CDP、DOM helper、Download | FileSystem、Encoding、CSV parser |
| 失敗の種類 | 画面契約違反、クリック失敗、ダウンロード失敗 | 文字コード不正、CSV不正、日付不正、ヘッダー不一致 |
| 読む順番 | Runner → Workflow → DOM | Runner → Workflow → Input / Encoding / Rules / Output |

## 3. 処理全体の流れ

```text
Invoke-LastMonthInstallExtractJob
  ├─ Assert-LastMonthInstallExtractJobSettings
  ├─ Resolve-LastMonthInstallExtractJobDependencies
  ├─ Initialize-LastMonthInstallExtractOutputDirectory
  ├─ New-LastMonthInstallExtractJobDateRange
  │   └─ New-LastMonthInstallExtractMonthlyDateRange
  ├─ Invoke-LastMonthInstallExtractInstallationWorkflow
  │   ├─ Get-LastMonthInstallExtractTargetCsvFileInfos
  │   ├─ foreach CSV file
  │   │   └─ Invoke-LastMonthInstallExtractCsvFileProcessing
  │   │       ├─ Get-LastMonthInstallExtractAssetNameFromFileName
  │   │       ├─ ReadAllBytes
  │   │       ├─ ConvertFrom-LastMonthInstallExtractSupportedBytes
  │   │       ├─ Get-LastMonthInstallExtractDelimiterFromText
  │   │       ├─ Import-LastMonthInstallExtractDelimitedText
  │   │       ├─ Test-LastMonthInstallExtractRequiredHeadersExact
  │   │       └─ foreach CSV row
  │   │           ├─ ConvertTo-LastMonthInstallExtractInstallDateOrNull
  │   │           ├─ Test-LastMonthInstallExtractDateInRange
  │   │           └─ New-LastMonthInstallExtractInstallationRow / New-LastMonthInstallExtractFailureRow
  │   └─ New-LastMonthInstallExtractWorkflowResult
  ├─ Export-LastMonthInstallExtractJobResults
  │   ├─ Export-LastMonthInstallExtractInstallationCsv
  │   └─ Export-LastMonthInstallExtractFailureCsv
  └─ Write-LastMonthInstallExtractWorkflowSummary
```

## 4. 設定値の意味

`LastMonthInstallExtract` は主に `foundation.config.psd1` の `Jobs.LastMonthInstallExtract` を使います。

| 設定 | 意味 |
|---|---|
| `TargetDirectory` | 入力CSVを探すディレクトリであり、出力CSVを書き込むディレクトリでもある |
| `OutputCsvFileName` | 集約結果CSVのファイル名 |
| `FailureCsvFileName` | 失敗・スキップ一覧CSVのファイル名。未指定なら `pc_installation_failure_list.csv` |
| `RequiredHeaders` | 入力CSVに必要なヘッダー。未指定なら `アプリ名`, `バージョン`, `導入日` |
| `FileNamePattern` | CSVファイル名から端末名を取り出す正規表現。未指定なら `^.+_(PCXX-\d{2}-\d{3})\.csv$` |

## 5. 重要なデータ構造

### InstallationRow

出力CSVに書かれる成功行です。

```text
'端末名'
'アプリ名'
'バージョン'
'導入日'
```

### FailureRow

失敗CSVに書かれる診断行です。

```text
FileName
AssetName
LineNumber
Reason
Timestamp
```

ファイル全体をスキップした場合は `LineNumber` が空になり、行単位でスキップした場合は該当行番号が入ります。

### WorkflowResult

ジョブ全体の処理結果です。

```text
InstallationRows
FailureRows
InputFileCount
ProcessedFileCount
SkippedFileCount
ReadRowCount
MatchedRowCount
```

この形に集約することで、Runnerは「CSVをどう読んだか」を知らずに、結果出力とサマリ表示だけを行えます。

## 6. 混乱しやすい点

### `Import-Csv` を使っていない理由

このジョブは、入力CSVの文字コードや区切り文字が一定でない可能性を考慮しています。また、行ごとの列数不一致を「即例外」ではなく「失敗行として記録して処理継続」したい設計です。

そのため、`Import-Csv` に丸投げせず、`Encoding.ps1` と `DelimitedText.ps1` で段階的に読みます。

### 失敗してもすぐ止めない理由

1つのCSVや1行が壊れていても、他のCSV・他の行は処理できる可能性があります。そのため、`Workflow.ps1` は失敗を `FailureRows` に集め、可能な限り最後まで処理します。

ただし、`TargetDirectory` や `OutputCsvFileName` のような必須設定が欠けている場合は、ジョブ開始前に例外で止めます。これは処理継続しても意味がないためです。

### 前月判定が `EndExclusive` になっている理由

日付範囲は「開始以上、終了未満」です。

```text
StartInclusive <= 導入日 < EndExclusive
```

たとえば現在日付が 2026-06-23 なら、前月範囲は次です。

```text
2026-05-01 以上
2026-06-01 未満
```

`2026-06-01` を含めないことで、月境界の判定が安定します。

## 7. この機能で変更時に特に危険な箇所

`Rules.ps1` のヘッダー検証を緩めると、入力CSVの列ずれを見逃す可能性があります。

`Encoding.ps1` でShift_JISを実際の対応文字コードに追加する場合は、誤判定リスクを考える必要があります。現在はCP932を推定には使いますが、実読み込み対象としては許可していません。

`Output.ps1` の安全確認を外すと、設定ミスで意図しない場所にCSVを書き込む可能性があります。
