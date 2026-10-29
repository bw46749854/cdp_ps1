# main/modules/LastMonthInstallExtract/internal/Models.ps1

## 1. このファイルを一言でいうと

`LastMonthInstallExtract` ジョブ内で受け渡す結果データの形を定義するファイルです。

## このファイルを変更する典型ケース

- 成功、失敗、skip、summaryなどのデータ構造が変わった場合
- WorkflowやOutputへ渡すオブジェクトのプロパティが変わった場合
- テストで比較する結果モデルの意味が変わった場合


## 2. このファイルが担当する範囲

- 出力CSVに書く成功行の形を作る。
- 失敗CSVに書く診断行の形を作る。
- Workflow全体の集約結果の形を作る。

## 3. このファイルが担当しない範囲

- 成功か失敗かの判定。
- CSVファイルの書き込み。
- ログ出力。

## 4. 関数ごとの説明

### New-LastMonthInstallExtractInstallationRow

前月インストール対象として出力する1行を作ります。

```text
InstallationRow
  '端末名'
  'アプリ名'
  'バージョン'
  '導入日'
```

プロパティ名が日本語なのは、そのまま出力CSVの列名になるためです。

### New-LastMonthInstallExtractFailureRow

失敗・スキップ診断用の1行を作ります。

```text
FailureRow
  FileName
  AssetName
  LineNumber
  Reason
  Timestamp
```

ファイル単位の失敗では `LineNumber` が空、行単位の失敗ではCSV上の行番号が入ります。

### New-LastMonthInstallExtractWorkflowResult

Workflow全体、または1ファイル分の処理結果を作ります。

```text
LastMonthInstallExtractWorkflowResult
  InstallationRows
  FailureRows
  InputFileCount
  ProcessedFileCount
  SkippedFileCount
  ReadRowCount
  MatchedRowCount
```

`Invoke-LastMonthInstallExtractCsvFileProcessing` でも `Invoke-LastMonthInstallExtractInstallationWorkflow` でも同じ形を使います。これにより、1ファイル分の結果を全体結果へ集約しやすくしています。

## 5. PowerShell文法上のポイント

`[pscustomobject]@{ ... }` は、プロパティ名付きの軽量オブジェクトを作る構文です。

`@($InstallationRows)` のように配列化しているのは、1件だけでも配列として扱えるようにするためです。PowerShellは1件だけの配列を自動的にスカラーへ潰すことがあるため、明示的に配列化しています。

## 6. 変更時の注意

`New-LastMonthInstallExtractInstallationRow` のプロパティ名を変えると、出力CSVのヘッダーも変わります。下流でCSV列名を前提にしている処理がある場合は影響します。

`New-LastMonthInstallExtractWorkflowResult` のカウント項目を減らすと、Runnerのサマリログやテストが情報不足になります。

## 7. 関連するテスト

- `LastMonthInstallExtract.Models.Tests.ps1`: 成功行と失敗行のプロパティ名を確認する。
