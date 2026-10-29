# main/modules/LastMonthInstallExtract/internal/Workflow.ps1

## 1. このファイルを一言でいうと

`LastMonthInstallExtract` の業務処理本体です。対象CSVを列挙し、1ファイルずつ読み、前月インストール行を抽出し、失敗行を集約します。

## このファイルを変更する典型ケース

- 処理順序、分岐、リトライ、失敗時の継続方針が変わった場合
- Policy判定結果と依存portのつなぎ方が変わった場合
- Workflowが集約する結果や後続処理への渡し方が変わった場合


## 2. このファイルが担当する範囲

- 設定値から対象ディレクトリ、出力ファイル名、必要ヘッダー、ファイル名パターンを取り出す。
- 入力CSVを列挙する。
- 1ファイル単位で、ファイル名検証、文字コード判定、CSV解析、ヘッダー検証、行抽出を行う。
- ファイル単位・行単位の失敗を `FailureRows` に追加する。
- 全ファイル分の処理結果を `LastMonthInstallExtractWorkflowResult` に集約する。

## 3. このファイルが担当しない範囲

- 出力CSVの実ファイル作成。
- ログの実装。
- 実際のファイル読み取りAPI。
- 文字コード判定の細部。
- CSV parserの細部。

これらは `Dependencies` 経由または専用ファイルに委譲します。

## 4. 関数呼び出しツリー

```text
Invoke-LastMonthInstallExtractInstallationWorkflow
  ├─ Resolve-LastMonthInstallExtractInstallationWorkflowDependencies
  ├─ Get-LastMonthInstallExtractTargetDirectoryFromSettings
  ├─ Get-LastMonthInstallExtractOutputCsvFileNameFromSettings
  ├─ Get-LastMonthInstallExtractRequiredHeadersFromSettings
  ├─ Get-LastMonthInstallExtractFileNamePatternFromSettings
  ├─ Get-LastMonthInstallExtractFailureCsvFileNameFromSettings
  ├─ Input.GetTargetCsvFiles
  ├─ foreach file
  │   └─ Invoke-LastMonthInstallExtractCsvFileProcessing
  │       ├─ Get-LastMonthInstallExtractAssetNameFromFileName
  │       ├─ Input.ReadAllBytes
  │       ├─ ConvertFrom-LastMonthInstallExtractSupportedBytes
  │       ├─ Get-LastMonthInstallExtractDelimiterFromText
  │       ├─ Import-LastMonthInstallExtractDelimitedText
  │       ├─ Test-LastMonthInstallExtractRequiredHeadersExact
  │       ├─ foreach csv row
  │       │   ├─ ConvertTo-LastMonthInstallExtractInstallDateOrNull
  │       │   ├─ Test-LastMonthInstallExtractDateInRange
  │       │   ├─ New-LastMonthInstallExtractInstallationRow
  │       │   └─ Add-LastMonthInstallExtractFailure
  │       └─ New-LastMonthInstallExtractWorkflowResult
  ├─ Add-LastMonthInstallExtractWorkflowFileResult
  └─ New-LastMonthInstallExtractWorkflowResult
```

## 5. 主要関数の説明

### Get-LastMonthInstallExtractSettingValue

`Settings` が hashtable でも pscustomobject でも、同じように値を取り出すための補助関数です。

設定は `.psd1` 由来なので hashtable になることがあります。一方、テストや呼び出し方によっては pscustomobject になることもあります。この差をWorkflow側で吸収します。

### Get-LastMonthInstallExtractRequiredHeadersFromSettings

`RequiredHeaders` が設定されていればそれを使い、なければ `Get-LastMonthInstallExtractDefaultRequiredHeaders` を使います。

既定値は次です。

```text
アプリ名
バージョン
導入日
```

### Add-LastMonthInstallExtractFailure

失敗理由をログに出し、同時に `FailureRows` に失敗行を追加します。

失敗行にはファイル名、端末名、行番号、理由、タイムスタンプが入ります。

### Invoke-LastMonthInstallExtractCsvFileProcessing

1つのCSVファイルを処理する中核関数です。

処理順序は次です。

```text
1. ファイル名から端末名を抽出できるか確認する
2. バイト列を読む
3. 対応文字コードとしてデコードする
4. 1行目から区切り文字を判定する
5. CSV/TSVをレコード化する
6. ヘッダーが期待通りか確認する
7. 各行の導入日を日付化する
8. 前月範囲内ならInstallationRowに追加する
9. 異常があればFailureRowに追加する
```

この関数は、ファイル名不正・読み取り失敗・CSV解析失敗・ヘッダー不一致の場合、そのファイル全体をスキップします。

一方、列数不一致行や日付不正行は、ファイル全体ではなく行単位でスキップします。

### Add-LastMonthInstallExtractWorkflowFileResult

1ファイル分の結果を、全体用の `InstallationRows` と `FailureRows` に追加します。

### Invoke-LastMonthInstallExtractInstallationWorkflow

全CSVファイルを処理する最上位Workflowです。最終的に全体の `LastMonthInstallExtractWorkflowResult` を返します。

## 6. 失敗時の扱い

| 失敗 | 扱い |
|---|---|
| ファイル名が期待形式でない | ファイル全体をスキップ |
| ファイル読み取り失敗 | ファイル全体をスキップ |
| 文字コード非対応 | ファイル全体をスキップ |
| CSV解析失敗 | ファイル全体をスキップ |
| ヘッダー不一致 | ファイル全体をスキップ |
| 行の列数不一致 | その行だけスキップ |
| 導入日が日付として読めない | その行だけスキップ |
| 導入日が前月範囲外 | 失敗ではなく対象外 |

## 7. 戻り値の形

```text
LastMonthInstallExtractWorkflowResult
  InstallationRows   : 出力対象のアプリ行
  FailureRows        : 失敗・スキップ診断行
  InputFileCount     : 入力候補CSV数
  ProcessedFileCount : 処理できたCSV数
  SkippedFileCount   : ファイル単位でスキップしたCSV数
  ReadRowCount       : 読み取ったデータ行数
  MatchedRowCount    : 前月条件に一致した行数
```

## 8. 変更時の注意

ファイル単位スキップと行単位スキップを混同しないでください。ヘッダー不一致はファイル全体の構造が信用できないためファイル単位スキップです。導入日不正はその行だけの問題なので行単位スキップです。

`Test-LastMonthInstallExtractRequiredHeadersExact` を緩めると、列の意味がずれたまま出力される危険があります。

`ConvertFrom-LastMonthInstallExtractSupportedBytes` の例外を握りつぶすと、文字化けしたCSVを正常データとして扱う可能性があります。

## 9. 関連するテスト

- `LastMonthInstallExtract.Workflow.Tests.ps1`: 前月抽出、スキップ、TSV処理、行単位失敗、依存差し替えを確認する。
- `LastMonthInstallExtract.Architecture.Tests.ps1`: Workflowが直接I/O、直接時刻、DOM、CDPに依存しないことを確認する。
