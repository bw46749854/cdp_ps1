# CompositeJobsの読み方

## 1. CompositeJobsとは何か

`CompositeJobs` は、既存のジョブを組み合わせて、より大きい作業単位を作るためのモジュールです。

単独ジョブとの違いは次です。

| 種別 | 例 | 主な責務 |
|---|---|---|
| 単独ジョブ | `DeviceListExport` | 画面操作やCSV出力など、1つの業務機能を実行する |
| 単独ジョブ | `InstalledAppExport` | 端末一覧を走査し、端末ごとのアプリCSVを取得する |
| 単独ジョブ | `LastMonthInstallExtract` | CSV群を読み、前月インストール行を抽出する |
| Composite Job | `WeeklyScanTargetSync` | `DeviceListExport` の結果CSVを `ScanTargetSync` に渡す |
| Composite Job | `MonthlyInstallReport` | `InstalledAppExport` の成果物ディレクトリを `LastMonthInstallExtract` の入力に渡す |

`CompositeJobs` は、業務処理を再実装しません。既存ジョブの入口を順番に呼ぶだけです。

## 2. なぜCompositeJobsが必要か

例えば、週次作業では次の2つが連続します。

```text
DeviceListExport
  ↓
端末一覧CSVが出力される
  ↓
ScanTargetSync
  ↓
そのCSVを入力として、画面上のチェックボックスを更新する
```

このとき、利用者が手作業で `DeviceListExport` のCSVパスを確認し、`ScanTargetSync` の `InputCsvPath` に設定し直すのは危険です。

`CompositeJobs` は、この「前段の成果物を後段の入力に渡す」作業を自動化します。

もう一つの例は、月次作業です。

```text
InstalledAppExport
  ↓
端末ごとのアプリCSV群が出力される
  ↓
LastMonthInstallExtract
  ↓
そのCSV群から前月インストール行を抽出する
```

ここでも、`InstalledAppExport` の出力ディレクトリを `LastMonthInstallExtract` の入力ディレクトリとして渡す必要があります。

## 3. CompositeJobsが持つべき責務

CompositeJobsが持つべき責務は次です。

```text
1. 子ジョブを正しい順番で呼ぶ
2. 子ジョブの成功・失敗を確認する
3. 前段ジョブの成果物を検証する
4. 後段ジョブへ必要な設定overrideを渡す
5. 連携全体の結果オブジェクトを返す
```

逆に、CompositeJobsが持つべきでない責務は次です。

```text
1. DOM helperを直接呼ぶ
2. CDP通信を直接扱う
3. CSVを直接解析する
4. 画面上のセレクタを知る
5. InstalledAppExport / ScanTargetSync / LastMonthInstallExtract の内部ルールを再実装する
```

これらを持ち始めると、CompositeJobsが「連携ジョブ」ではなく「巨大な業務ジョブ」になってしまいます。

## 4. 2つの連携ジョブの全体像

### WeeklyScanTargetSync

```text
Invoke-WeeklyScanTargetSyncJob
  ├─ Resolve-CompositeJobDependencies
  ├─ Invoke-CompositeChildJob JobName='DeviceListExport'
  ├─ Get-CompositeSingleFeatureResult Feature='DeviceListExport'
  ├─ Assert-DeviceListExportResultForComposite
  │   ├─ Ok が true か確認
  │   ├─ ExportedCsvPath が空でないか確認
  │   └─ ExportedCsvPath のファイルが存在するか確認
  ├─ Invoke-CompositeChildJob JobName='ScanTargetSync'
  │   └─ JobSettingsOverrides.InputCsvPath = DeviceListExportのCSVパス
  ├─ Assert-CompositeSucceededWhenResultHasOk JobName='ScanTargetSync'
  └─ 連携結果を返す
```

重要なのは、`ScanTargetSync` を実行する前に `DeviceListExport` の成果物を検証していることです。

`DeviceListExport` が失敗した、CSVパスが空だった、またはCSVが存在しなかった場合、`ScanTargetSync` は実行されません。これは安全設計です。

### MonthlyInstallReport

```text
Invoke-MonthlyInstallReportJob
  ├─ Resolve-CompositeJobDependencies
  ├─ New-MonthlyInstallReportRunDirectories
  │   ├─ RunTimestamp を作る
  │   ├─ RunDirectory を作る
  │   ├─ InstalledAppExportTempDirectory を作る
  │   └─ InstalledAppExportDownloadDirectory を作る
  ├─ Invoke-CompositeChildJob JobName='InstalledAppExport'
  │   ├─ JobSettingsOverrides.TempDirectory = InstalledAppExportTempDirectory
  │   └─ JobSettingsOverrides.DownloadDirectory = InstalledAppExportDownloadDirectory
  ├─ Assert-CompositeSucceededWhenResultHasOk JobName='InstalledAppExport'
  ├─ Assert-InstalledAppExportExportArtifactsExist
  │   └─ InstalledAppExport成果物CSVが存在するか確認
  ├─ Invoke-CompositeChildJob JobName='LastMonthInstallExtract'
  │   └─ JobSettingsOverrides.TargetDirectory = InstalledAppExportDownloadDirectory
  ├─ Assert-CompositeSucceededWhenResultHasOk JobName='LastMonthInstallExtract'
  └─ 連携結果を返す
```

ここでは、`InstalledAppExport` のダウンロード先を固定し、その同じディレクトリを `LastMonthInstallExtract` の入力ディレクトリとして渡します。

これにより、`LastMonthInstallExtract` は「どのInstalledAppExport成果物を読むべきか」を自分で探索しなくて済みます。

## 5. JobSettingsOverridesとは何か

`JobSettingsOverrides` は、通常の `foundation.config.psd1` の設定に対して、今回の子ジョブ実行だけ一時的に上書きする設定です。

例です。

```text
ScanTargetSync に渡すoverride
  InputCsvPath = DeviceListExport が出力したCSV

InstalledAppExport に渡すoverride
  TempDirectory     = 今回専用の一時ディレクトリ
  DownloadDirectory = 今回専用の成果物ディレクトリ

LastMonthInstallExtract に渡すoverride
  TargetDirectory = InstalledAppExport の成果物ディレクトリ
```

この仕組みにより、設定ファイルを毎回書き換えなくても、CompositeJobsが子ジョブの入力先・出力先を制御できます。

## 6. 混乱しやすい点

### 「CompositeJobsは各ジョブを直接呼ぶのか」

直接 `Invoke-DeviceListExportJob` や `Invoke-InstalledAppExportJob` を呼んでいるわけではありません。

実際には `Invoke-FoundationEntrypoint` を、`JobName` を変えて再実行します。

```text
CompositeJobs
  ↓
Invoke-FoundationEntrypoint JobName='InstalledAppExport'
  ↓
foundation.jobs.psd1 から InstalledAppExport の ModulePath / CommandName を解決
  ↓
Invoke-InstalledAppExportJob
```

この形にしているため、通常のジョブ実行と同じ起動経路、同じ設定読み込み、同じContext生成を使えます。

### 「UsesDom = false なのに、子ジョブがDOMを使うのは矛盾しないか」

矛盾しません。

`CompositeJobs` 自体はDOMを使わないため、`WeeklyScanTargetSync` や `MonthlyInstallReport` の `UsesDom` は `$false` です。

ただし、子ジョブとして呼ばれる `DeviceListExport`、`InstalledAppExport`、`ScanTargetSync` はそれぞれ自分の `JobName` で起動され、その子ジョブ側の `UsesDom` / `DomFeaturePaths` に従ってDOM bundleを登録します。

### 「なぜInstalledAppExport成果物CSVを中身まで見ないのか」

CompositeJobsの責務は、成果物が存在することを確認して、次のジョブに渡すことです。

CSVの中身が正しいかどうかは `LastMonthInstallExtract` の責務です。CompositeJobsでCSV解析を始めると、`LastMonthInstallExtract` と責務が重複します。

## 7. 変更時の基本判断

CompositeJobsを変更するときは、次の問いで判断してください。

```text
これは連携順序の変更か？
  → CompositeJobsに書いてよい。

これは前段ジョブの成果物を後段ジョブに渡す処理か？
  → CompositeJobsに書いてよい。

これはCSVの中身を解釈する処理か？
  → LastMonthInstallExtract、ScanTargetSync、または該当ジョブ側に置く。

これは画面操作やDOM helper呼び出しか？
  → CompositeJobsに置かない。

これはダウンロード待ちやリネーム処理か？
  → 各Feature moduleのDownloadに置く。
```
