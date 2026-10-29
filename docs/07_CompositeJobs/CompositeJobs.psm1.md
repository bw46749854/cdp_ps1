# main/modules/CompositeJobs/CompositeJobs.psm1

## 1. このファイルを一言でいうと

既存ジョブを順番に呼び、前段ジョブの成果物を後段ジョブの設定overrideとして渡すためのComposite Jobモジュールです。

このファイルは、DOM操作、CDP通信、CSV解析、個別Featureの業務ロジックを持ちません。

## このファイルを変更する典型ケース

- 公開関数、Job入口、内部ファイル読み込み順が変わった場合
- モジュール外へ公開する関数の範囲が変わった場合
- Runner / Workflow / Dependencies への接続方法が変わった場合


## 2. このファイルが担当する範囲

- `DeviceListExport` の出力CSVを `ScanTargetSync` の入力CSVとして渡す。
- `InstalledAppExport` の成果物ディレクトリを `LastMonthInstallExtract` の入力ディレクトリとして渡す。
- 子ジョブを `Invoke-FoundationEntrypoint` 経由で実行する。
- 子ジョブの失敗結果を見て、後続ジョブを止める。
- 前段ジョブの成果物が存在するか確認する。
- Composite Job全体の結果オブジェクトを返す。

## 3. このファイルが担当しない範囲

- `DeviceListExport` の画面操作。
- `ScanTargetSync` のCSV判定ルール。
- `InstalledAppExport` の一覧走査や1行処理。
- `LastMonthInstallExtract` のCSV解析、文字コード判定、日付判定。
- DOM helper登録。
- CDP / WebSocket通信。
- CSVの中身の検証。

これらは各Feature moduleまたはFoundationの責務です。

## 4. モジュール読み込みの意味

このファイルの先頭では、FoundationモジュールをImportします。

```text
CompositeJobs.psm1
  └─ Import-Module modules/Foundation/Foundation.psm1
```

理由は、子ジョブを起動するために `Invoke-FoundationEntrypoint` が必要だからです。

CompositeJobsは子ジョブの関数を直接Importして呼ぶのではなく、Foundationの入口を再利用します。

```text
CompositeJobs
  ↓
Invoke-FoundationEntrypoint -JobName InstalledAppExport
  ↓
foundation.jobs.psd1 から InstalledAppExport の ModulePath / CommandName を解決
  ↓
Invoke-InstalledAppExportJob
```

この形にすることで、単独ジョブ実行時と同じ初期化、同じ設定読み込み、同じContext生成を通れます。

## 5. 公開される関数

このモジュールが外部公開する関数は2つです。

```text
Invoke-WeeklyScanTargetSyncJob
Invoke-MonthlyInstallReportJob
```

これらは `foundation.jobs.psd1` の `CommandName` から呼ばれます。

```text
WeeklyScanTargetSync
  ModulePath  = modules/CompositeJobs/CompositeJobs.psm1
  CommandName = Invoke-WeeklyScanTargetSyncJob

MonthlyInstallReport
  ModulePath  = modules/CompositeJobs/CompositeJobs.psm1
  CommandName = Invoke-MonthlyInstallReportJob
```

## 6. config / job registry path の扱い

Composite Job は、親Contextの設定ファイルとジョブレジストリを子Jobへ伝播します。
この境界を明示するため、現行実装には既定パス関数とContext優先関数が分かれています。

| 関数 | 役割 |
|---|---|
| `Get-CompositeDefaultConfigPath` | `RootPath` から `config/foundation.config.psd1` の既定パスを作る |
| `Get-CompositeDefaultJobRegistryPath` | `RootPath` から `config/foundation.jobs.psd1` の既定パスを作る |
| `Get-CompositeConfigPath` | `Context.ConfigPath` があれば優先し、なければ既定config pathを返す |
| `Get-CompositeJobRegistryPath` | `Context.JobRegistryPath` があれば優先し、なければ既定job registry pathを返す |

この分離により、通常実行では既定パスを使い、テストや明示的な起動ではContextに渡されたpathを保てます。
Composite Jobから子Jobを呼ぶ場合、親と子が別のconfigやjob registryを読む状態は許可しません。

## 7. 関数呼び出しツリー

### WeeklyScanTargetSync

```text
Invoke-WeeklyScanTargetSyncJob
  ├─ Resolve-CompositeJobDependencies
  │   └─ New-CompositeFoundationDependencies
  ├─ Invoke-CompositeChildJob JobName='DeviceListExport'
  │   ├─ Get-CompositeConfigPath
  │   ├─ Get-CompositeJobRegistryPath
  │   ├─ Get-CompositeCallbackScriptBlock Foundation.InvokeJob
  │   └─ Invoke-FoundationEntrypoint
  ├─ Get-CompositeSingleFeatureResult Feature='DeviceListExport'
  ├─ Assert-DeviceListExportResultForComposite
  │   ├─ Ok確認
  │   ├─ ExportedCsvPath空チェック
  │   └─ FileSystem.TestPath
  ├─ Invoke-CompositeChildJob JobName='ScanTargetSync'
  │   └─ JobSettingsOverrides.InputCsvPath = ExportedCsvPath
  ├─ Assert-CompositeSucceededWhenResultHasOk JobName='ScanTargetSync'
  └─ return WeeklyScanTargetSync result
```

### MonthlyInstallReport

```text
Invoke-MonthlyInstallReportJob
  ├─ Resolve-CompositeJobDependencies
  │   └─ New-CompositeFoundationDependencies
  ├─ New-MonthlyInstallReportRunDirectories
  │   ├─ Timing.RunTimestamp
  │   ├─ Get-MonthlyInstallReportRunRootDirectory
  │   ├─ FileSystem.InitializeDirectory RunDirectory
  │   ├─ FileSystem.InitializeDirectory InstalledAppExportTempDirectory
  │   └─ FileSystem.InitializeDirectory InstalledAppExportDownloadDirectory
  ├─ Invoke-CompositeChildJob JobName='InstalledAppExport'
  │   └─ JobSettingsOverrides
  │       ├─ TempDirectory
  │       └─ DownloadDirectory
  ├─ Assert-CompositeSucceededWhenResultHasOk JobName='InstalledAppExport'
  ├─ Assert-InstalledAppExportExportArtifactsExist
  │   ├─ Get-InstalledAppExportExportArtifactFileFilter
  │   └─ FileSystem.GetFiles
  ├─ Invoke-CompositeChildJob JobName='LastMonthInstallExtract'
  │   └─ JobSettingsOverrides.TargetDirectory = InstalledAppExportDownloadDirectory
  ├─ Assert-CompositeSucceededWhenResultHasOk JobName='LastMonthInstallExtract'
  └─ return MonthlyInstallReport result
```

## 8. 扱うデータの形

### Dependencies

`New-CompositeFoundationDependencies` は、CompositeJobsで使う外部依存をまとめて返します。

```text
Dependencies
  Foundation
    InvokeJob              : 子ジョブをFoundation入口経由で起動するscriptblock
  FileSystem
    TestPath               : ファイル・ディレクトリ存在確認
    InitializeDirectory    : ディレクトリ作成
    GetFiles               : 指定ディレクトリからファイル一覧取得
  Timing
    RunTimestamp           : yyyyMMdd_HHmmss形式の実行タイムスタンプ
```

この形にしている理由は、テスト時に実際のジョブ起動やファイル操作を差し替えるためです。

### WeeklyScanTargetSync result

```text
WeeklyScanTargetSyncResult
  Ok             : true
  Feature        : WeeklyScanTargetSync
  DeviceListExport    : DeviceListExportの結果
  ScanTargetSync : ScanTargetSyncの結果
  InputCsvPath   : ScanTargetSyncへ渡したCSVパス
```

`InputCsvPath` は、`DeviceListExport` が返した `ExportedCsvPath` と同じ値です。

### MonthlyInstallReport result

```text
MonthlyInstallReportResult
  Ok                         : true
  Feature                    : MonthlyInstallReport
  RunTimestamp               : yyyyMMdd_HHmmss形式の実行時刻
  RunDirectory               : 今回の月次実行ディレクトリ
  InstalledAppExportTempDirectory      : InstalledAppExport用一時ディレクトリ
  InstalledAppExportDownloadDirectory  : InstalledAppExport成果物CSV出力先
  InstalledAppExportExportedCsvPaths   : 検出されたInstalledAppExport成果物CSVパス配列
  InstalledAppExport                   : InstalledAppExportの結果
  LastMonthInstallExtract                   : LastMonthInstallExtractの結果
  TargetDirectory            : LastMonthInstallExtractへ渡した入力ディレクトリ
```

## 8. 主要関数の説明

### Get-CompositeCallbackScriptBlock

指定した依存オブジェクトから、指定名のscriptblockを取り出します。

例えば、次のように使われます。

```text
Get-CompositeCallbackScriptBlock -Callbacks $Dependencies.Foundation -Name 'InvokeJob'
```

この関数は、依存が存在しない場合、または指定プロパティがscriptblockでない場合に例外を投げます。

このチェックがないと、後続で `& $invokeJob` を実行したときに、原因が分かりにくいエラーになります。CompositeJobsでは、依存不備を早い段階で明示的に失敗させています。

### New-CompositeFoundationDependencies

本番実行用の依存セットを作ります。

最も重要なのは `Foundation.InvokeJob` です。これは `Invoke-FoundationEntrypoint` を呼ぶscriptblockです。

```text
Foundation.InvokeJob
  ↓
Invoke-FoundationEntrypoint
```

このscriptblockは、次の引数を受け取ります。

```text
RootPath
ConfigPath
JobName
JobRegistryPath
JobSettingsOverrides
```

`JobSettingsOverrides` が指定されている場合だけ、`Invoke-FoundationEntrypoint` に渡します。

### Resolve-CompositeJobDependencies

テスト用依存が渡されていればそれを使い、渡されていなければ本番依存を作ります。

```text
Dependencies引数あり
  → そのまま使う

Dependencies引数なし
  → New-CompositeFoundationDependencies を使う
```

この構造により、テストでは実際の `DeviceListExport` や `InstalledAppExport` を起動せず、呼び出し記録だけを確認できます。

### Get-CompositeConfigPath / Get-CompositeJobRegistryPath

Contextに `ConfigPath` / `JobRegistryPath` が入っていればそれを使います。空なら既定パスを作ります。

```text
ConfigPath既定値
  <RootPath>/config/foundation.config.psd1

JobRegistryPath既定値
  <RootPath>/config/foundation.jobs.psd1
```

CompositeJobsが子ジョブを呼ぶとき、親と同じ設定ファイル・ジョブ定義ファイルを使うために必要です。

### Invoke-CompositeChildJob

子ジョブを1つ起動する共通関数です。

処理内容は次です。

```text
1. Foundation.InvokeJob scriptblockを取得する
2. RootPath / ConfigPath / JobRegistryPath / JobName をまとめる
3. 必要なら JobSettingsOverrides を追加する
4. & $invokeJob @invokeArgs で起動する
```

`&` はPowerShellの呼び出し演算子です。変数に入ったscriptblockやCommandInfoを実行するときに使います。

`@invokeArgs` はスプラッティングです。hashtableのキーをパラメータ名として関数に渡します。

### Assert-CompositeSucceededWhenResultHasOk

子ジョブの戻り値に `Ok` プロパティがある場合、`Ok` が `$true` でなければ失敗扱いにします。

戻り値が配列でも単一オブジェクトでも処理できるよう、`@($Result | Where-Object { ... })` で配列化しています。

`Ok` プロパティが存在しない結果は、この関数では失敗扱いにしません。これは、全ジョブの戻り値が必ず同じ形とは限らないためです。ただし、`DeviceListExport` のように明示的に必要な結果は、専用の検証関数で厳密に確認します。

### Get-CompositeSingleFeatureResult

戻り値の中から、指定した `Feature` の結果を1件だけ取り出します。

```text
Feature='DeviceListExport'
  ↓
Resultの中から Feature が DeviceListExport のオブジェクトだけを抽出
  ↓
1件でなければ例外
```

DeviceListExportの結果は、後続の `ExportedCsvPath` 検証に必要です。複数件あっても0件でも、どの結果を使うべきか判断できないため例外にします。

### Assert-DeviceListExportResultForComposite

DeviceListExportの結果が、ScanTargetSyncへ渡せる状態かを確認します。

確認内容は次です。

| 確認 | 失敗時の意味 |
|---|---|
| `Ok` が true | DeviceListExport自体が成功していない |
| `ExportedCsvPath` が空でない | 後段に渡すCSVパスがない |
| `ExportedCsvPath` が存在する | 後段が読むCSVファイルが実在しない |

この検証に失敗した場合、`ScanTargetSync` は実行されません。

これは重要です。存在しないCSVを渡して `ScanTargetSync` を動かすと、後段ジョブで分かりにくい入力エラーになります。CompositeJobs側で前段成果物として検証する方が、失敗理由が明確です。

### Get-CompositeSettingValue

設定値を取り出す補助関数です。

CompositeJobsでは、`Context.JobSettings` から `RunRootDirectory` を取り出すために使います。

この関数は hashtable 前提で `ContainsKey` を使っています。CompositeJobsの設定は `.psd1` 由来のhashtableとして扱われます。

### Get-MonthlyInstallReportRunRootDirectory

`MonthlyInstallReport` の実行ルートディレクトリを取得します。

設定キーは次です。

```text
Jobs.MonthlyInstallReport.RunRootDirectory
```

この値が空なら例外になります。

このディレクトリの下に、実行ごとのタイムスタンプディレクトリが作られます。

### New-MonthlyInstallReportRunDirectories

月次連携用のディレクトリを作成します。

作られるディレクトリは次です。

```text
RunRootDirectory
  └─ yyyyMMdd_HHmmss
       ├─ installed_app_export_tmp
       └─ installed_app_export_downloads
```

それぞれの意味です。

| ディレクトリ | 意味 |
|---|---|
| `RunDirectory` | 今回1回分の月次連携実行ディレクトリ |
| `InstalledAppExportTempDirectory` | InstalledAppExportジョブが一時ファイルを置く場所 |
| `InstalledAppExportDownloadDirectory` | InstalledAppExportジョブが成果物CSVを出力する場所 |

`RunTimestamp` は `yyyyMMdd_HHmmss` 形式である必要があります。形式が不正なら例外になります。

### Get-InstalledAppExportExportArtifactFileFilter

InstalledAppExport成果物CSVを探すためのファイル名filterを作ります。

元になる設定は次です。

```text
Config.Jobs.InstalledAppExport.DownloadFilePrefix
```

例えば `DownloadFilePrefix = 'app_list_'` の場合、filterは次になります。

```text
app_list_*.csv
```

`installed_app_export_error_list.csv` のような失敗一覧CSVを、成果物CSVとして誤認しないためにprefixで絞り込んでいます。

### Assert-InstalledAppExportExportArtifactsExist

InstalledAppExportの成果物CSVが存在するか確認します。

処理内容は次です。

```text
1. InstalledAppExportのDownloadFilePrefixからfilterを作る
2. InstalledAppExportDownloadDirectory内のCSVを検索する
3. 1件もなければ例外
4. 見つかったCSVのFullName配列を返す
```

ここではCSVの中身は見ません。中身の妥当性は `LastMonthInstallExtract` が判断します。

### Invoke-WeeklyScanTargetSyncJob

週次連携ジョブの入口です。

処理順序は次です。

```text
1. 依存を解決する
2. DeviceListExportを実行する
3. DeviceListExport結果からFeature='DeviceListExport'の結果を1件取り出す
4. ExportedCsvPathを検証する
5. ScanTargetSyncを実行する
6. ScanTargetSyncへ InputCsvPath override を渡す
7. ScanTargetSyncの失敗結果を確認する
8. 連携結果を返す
```

後段に渡すoverrideは次です。

```text
ScanTargetSync.JobSettingsOverrides
  InputCsvPath = DeviceListExport.ExportedCsvPath
```

### Invoke-MonthlyInstallReportJob

月次連携ジョブの入口です。

処理順序は次です。

```text
1. 依存を解決する
2. 今回実行用のディレクトリを作る
3. InstalledAppExportを実行する
4. InstalledAppExportへ TempDirectory / DownloadDirectory override を渡す
5. InstalledAppExportの失敗結果を確認する
6. InstalledAppExport成果物CSVが存在することを確認する
7. LastMonthInstallExtractを実行する
8. LastMonthInstallExtractへ TargetDirectory override を渡す
9. LastMonthInstallExtractの失敗結果を確認する
10. 連携結果を返す
```

子ジョブへ渡すoverrideは次です。

```text
InstalledAppExport.JobSettingsOverrides
  TempDirectory     = <RunDirectory>/installed_app_export_tmp
  DownloadDirectory = <RunDirectory>/installed_app_export_downloads

LastMonthInstallExtract.JobSettingsOverrides
  TargetDirectory = <RunDirectory>/installed_app_export_downloads
```

## 9. PowerShell文法上のポイント

### scriptblock

このファイルでは、外部処理をscriptblockとしてDependenciesに入れています。

```text
Foundation.InvokeJob
FileSystem.TestPath
FileSystem.InitializeDirectory
FileSystem.GetFiles
Timing.RunTimestamp
```

これにより、テストでは本物のジョブ起動や本物のファイル操作を使わず、呼び出された引数だけを検証できます。

### GetNewClosure()

scriptblockの末尾に `.GetNewClosure()` が付いています。

これは、scriptblockが作られた時点の変数スコープを保持するためです。

特にテストでは、`$calls` のような呼び出し記録用変数をscriptblock内から参照します。`GetNewClosure()` がないと、後から実行されたときに期待した変数を参照できない場合があります。

### スプラッティング `@invokeArgs`

`Invoke-CompositeChildJob` では、hashtableに引数を詰めてから `@invokeArgs` で渡します。

```text
invokeArgs
  RootPath
  ConfigPath
  JobName
  JobRegistryPath
  JobSettingsOverrides
```

これは、引数が増えたときにも読みやすくするためです。

### `@(...)` による配列化

子ジョブの戻り値は、単一オブジェクトの場合も、配列の場合もあります。

そのため、このファイルでは `@($Result | Where-Object { ... })` のように配列化してから件数を確認します。

この配列化を外すと、戻り値が1件のときと複数件のときで挙動が変わる可能性があります。

## 10. 失敗時の扱い

| 失敗 | 後続ジョブ | 理由 |
|---|---|---|
| DeviceListExportが `Ok=false` を返す | ScanTargetSyncを実行しない | 入力CSVの信頼性がないため |
| DeviceListExportの `ExportedCsvPath` が空 | ScanTargetSyncを実行しない | 入力CSVパスがないため |
| DeviceListExportのCSVが存在しない | ScanTargetSyncを実行しない | 後段が読めないため |
| InstalledAppExportが `Ok=false` を返す | LastMonthInstallExtractを実行しない | InstalledAppExport成果物を信頼できないため |
| InstalledAppExport成果物CSVが0件 | LastMonthInstallExtractを実行しない | 入力対象がないため |
| InstalledAppExport `DownloadFilePrefix` が空 | LastMonthInstallExtractを実行しない | 成果物CSVを安全に識別できないため |
| LastMonthInstallExtractが `Ok=false` を返す | Composite Jobを失敗させる | 月次連携全体が成功していないため |

## 11. 変更時の注意

### 子ジョブの内部処理をCompositeJobsへ移さない

例えば、`LastMonthInstallExtract` に渡す前にCSVの中身をCompositeJobsで解析し始めるのは避けてください。

理由は、CSV解析の責務は `LastMonthInstallExtract` にあるためです。CompositeJobsがCSV構造を知ると、`LastMonthInstallExtract` の仕様変更時にCompositeJobsも壊れやすくなります。

### InstalledAppExport成果物の判定条件を緩めすぎない

`Assert-InstalledAppExportExportArtifactsExist` は、`DownloadFilePrefix` を使って成果物CSVを探します。

これを `*.csv` に変えると、`installed_app_export_error_list.csv` のような失敗CSVまで成果物として扱う危険があります。

### 子ジョブ失敗時に後続ジョブを実行しない

`DeviceListExport` が失敗した状態で `ScanTargetSync` を実行する、または `InstalledAppExport` が失敗した状態で `LastMonthInstallExtract` を実行する変更は避けてください。

CompositeJobsの重要な役割は、前段が安全に成功している場合だけ後段へ進めることです。

### ConfigPath / JobRegistryPath を落とさない

`Invoke-CompositeChildJob` は、親Contextの `ConfigPath` と `JobRegistryPath` を子ジョブに渡します。

これを落とすと、カスタム設定ファイルやテスト用ジョブ定義ファイルを使っている場合に、子ジョブだけ既定パスを読みに行ってしまいます。

## 12. 関連するテスト

- `CompositeJobs.Tests.ps1`: 子ジョブ呼び出し順、override引き渡し、失敗時に後続を止めること、成果物CSV検出を確認する。
- `CompositeJobs.Tests.ps1` の source contract: CompositeJobsがDOM、CDP、CSV解析責務を持たないことを確認する。

特にsource contractは重要です。このテストは、CompositeJobsが次のような関数を持ち込まないことを確認しています。

```text
Invoke-FoundationDomHelperMethod
Send-CDPCommand
Receive-CDPMessage
Open-CDPConnection
Import-Csv
ConvertFrom-Csv
Export-Csv
```

つまり、CompositeJobsは「子ジョブをつなぐ層」であり、「子ジョブの中身を再実装する層」ではない、という設計境界をテストで守っています。

## 13. 本ドキュメント内容の要点

このファイルを読み終えた時点で、次を説明できれば十分です。

```text
- CompositeJobsは既存ジョブを順番に呼ぶだけである
- 子ジョブは Invoke-FoundationEntrypoint 経由で起動される
- DeviceListExportのExportedCsvPathがScanTargetSyncのInputCsvPathになる
- InstalledAppExportのDownloadDirectoryがLastMonthInstallExtractのTargetDirectoryになる
- 子ジョブが失敗したら後続ジョブは実行しない
- CompositeJobsはDOM、CDP、CSV解析を直接持たない
- JobSettingsOverridesは今回の子ジョブ実行だけの一時設定である
```
