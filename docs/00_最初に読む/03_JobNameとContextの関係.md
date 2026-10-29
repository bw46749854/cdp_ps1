# JobName と Context の関係

## 1. この文書を一言でいうと

この文書は、`JobName`、`JobDefinition`、`JobSettings`、`Context` の違いを整理するための文書です。

この違いが曖昧なままだと、`Invoke-FoundationEntrypoint` の次の処理が分かりにくくなります。

```powershell
Import-FoundationJobModule -JobDefinition $context.JobDefinition -JobName $JobName
$command = Get-FoundationJobCommand `
    -JobDefinition $context.JobDefinition `
    -JobName $JobName
```

ここで重要なのは、`JobName` と `$context.JobDefinition` は同じものではない、という点です。

---

## 2. 最初に結論

| 名前 | 種類 | どこから来るか | 何に使うか |
|---|---|---|---|
| `JobName` | 文字列 | `run_job.ps1 -JobName InstalledAppExport` のような実行引数 | どのジョブを実行するかを指定するキー |
| `JobDefinition` | hashtable | `config/foundation.jobs.psd1` の `Jobs[$JobName]` | そのジョブの実装ファイル、入口関数、DOMファイルを知る |
| `JobSettings` | hashtable | `config/foundation.config.psd1` の `Jobs[$JobName]` | そのジョブの実行時設定を知る |
| `Context` | pscustomobject | `New-FoundationRunContext` が組み立てる | ジョブ実行中に必要な情報をまとめて渡す |

`JobName` は「名前」です。  
`JobDefinition` は「その名前のジョブをどう実行するか」です。  
`JobSettings` は「そのジョブを今回どの設定で動かすか」です。  
`Context` は「実行中に使う情報をまとめた箱」です。

---

## 3. 具体例: `-JobName InstalledAppExport` の場合

手動で次のように実行されたとします。

```powershell
powershell.exe -File main\run_job.ps1 -JobName InstalledAppExport
```

この時点で分かっているのは、`InstalledAppExport` という文字列だけです。  
まだ `Invoke-InstalledAppExportJob` は呼ばれていません。  
まだ `modules\InstalledAppExport\InstalledAppExport.psm1` も読み込まれていません。

次に `foundation.jobs.psd1` を見ることで、`InstalledAppExport` が次の実装定義に変換されます。

```text
Jobs['InstalledAppExport']
  ModulePath      = modules\InstalledAppExport\InstalledAppExport.psm1
  CommandName     = Invoke-InstalledAppExportJob
  DomFeaturePaths = dom\features\installed-app-export\...
```

さらに `foundation.config.psd1` を見ることで、`InstalledAppExport` が次の実行時設定に変換されます。

```text
Jobs['InstalledAppExport']
  TempDirectory                = monthly\tmp
  DownloadDirectory            = monthly\Downloads
  DownloadFilePrefix           = app_list_
  DownloadTimeoutSeconds       = 120
  DownloadStableSeconds        = 2
  DetailPanelCloseWaitSeconds  = 3
  MaxScanLoops                 = 500
  SameScrollLimit              = 2
```

同じ `InstalledAppExport` という名前から、2種類の情報を引いています。

```text
JobName = InstalledAppExport
  ├─ foundation.jobs.psd1  → JobDefinition
  └─ foundation.config.psd1 → JobSettings
```

---

## 4. `foundation.jobs.psd1` と `foundation.config.psd1` の違い

この2つは似ていますが、役割が違います。

## `foundation.jobs.psd1`

これは、ジョブの**実装定義**です。

```text
このジョブは、どのPowerShellモジュールにあるか
このジョブの入口関数名は何か
このジョブで読み込むDOM JavaScriptはどれか
このジョブはDOMを使うか
```

例:

```text
InstalledAppExport → modules\InstalledAppExport\InstalledAppExport.psm1 → Invoke-InstalledAppExportJob
LastMonthInstallExtract → modules\LastMonthInstallExtract\LastMonthInstallExtract.psm1 → Invoke-LastMonthInstallExtractJob
```

## `foundation.config.psd1`

これは、ジョブの**実行時設定**です。

```text
どのフォルダを使うか
何秒待つか
どのCSVファイル名で出力するか
どの閾値で判定するか
```

例:

```text
ScanTargetSync.DaysThreshold = 7
DeviceListExport.DownloadTimeoutSeconds = 120
LastMonthInstallExtract.RequiredHeaders = アプリ名, バージョン, 導入日
```

---

## 5. なぜ `JobName` だけでは足りないのか

`JobName` は、あくまで辞書を引くためのキーです。  
`InstalledAppExport` という文字列だけでは、次のことが分かりません。

```text
- どの .psm1 を Import-Module するのか
- どの関数を Get-Command するのか
- DOM feature を読み込む必要があるのか
- どの設定値を使うのか
```

そのため、起動時に次の解決処理が必要になります。

```text
JobName
  ↓
Get-FoundationJobDefinition
  ↓
JobDefinition
  ↓
Import-FoundationJobModule
Get-FoundationJobCommand
```

そして実行時設定は別に解決されます。

```text
JobName
  ↓
Get-FoundationJobConfig
  ↓
JobSettings
```

---

## 6. `$context` に入る代表的な値

`New-FoundationRunContext` は、次のような `pscustomobject` を作ります。

```text
Context
  RootPath        : main フォルダの絶対パス
  RunId           : 実行ごとのID
  JobName         : 実行対象ジョブ名
  JobDefinition   : foundation.jobs.psd1 から取得した実装定義
  ConfigPath      : 実際に使用した foundation.config.psd1 の絶対パス
  JobRegistryPath : 実際に使用した foundation.jobs.psd1 の絶対パス
  Config          : config 全体
  CommonSettings  : Config.Common
  JobSettings     : Config.Jobs[JobName]
  Logger          : ログ出力先
  Services        : 共通サービス群
  Page            : ブラウザページ。初期値は null
```

`JobDefinition` と `JobSettings` の両方が入ります。  
理由は、ジョブ実行中に両方が必要になるからです。

---

## 7. `$context.JobDefinition` は何に使われるか

主に起動処理で使います。

```text
JobDefinition.ModulePath
  ↓
Import-FoundationJobModule
  ↓
Feature module を Import-Module する
```

```text
JobDefinition.CommandName
  ↓
Get-FoundationJobCommand
  ↓
実行する関数を Get-Command で取得する
```

```text
JobDefinition.DomFeaturePaths
  ↓
DOMを使うジョブの初期化
  ↓
ブラウザに登録する JavaScript feature を知る
```

`JobDefinition` は「どう実装されているか」を表します。

---

## 8. `$context.JobSettings` は何に使われるか

Feature module の処理中に使います。

例: `InstalledAppExport` の場合

```text
$context.JobSettings.DownloadDirectory
$context.JobSettings.DownloadTimeoutSeconds
$context.JobSettings.DownloadStableSeconds
$context.JobSettings.MaxScanLoops
```

例: `ScanTargetSync` の場合

```text
$context.JobSettings.InputCsvPath
$context.JobSettings.OutputDirectory
$context.JobSettings.DaysThreshold
```

`JobSettings` は「今回どの設定値で実行するか」を表します。

---

## 9. `$context.Config` は何に使われるか

`$context.Config` は、設定ファイル全体です。

```text
Config
  Common
  Jobs
```

多くのFeature moduleでは、通常 `$context.JobSettings` を使えば十分です。  
`$context.Config` 全体を直接読む必要があるケースは限定的です。

`$context.Config` を直接参照しすぎると、関数が「自分に必要な設定だけを見る」のではなく、「設定ファイル全体を知っている」状態になります。変更影響が広がりやすくなります。

---

## 10. `.bat` から実行した場合に何が取得されるか

root の `.bat` は、利用者向けの薄い起動入口です。
`.bat` 自身は業務処理を持たず、`main\run_job.ps1` に `-JobName` を渡します。

| 起動ファイル | 渡される `JobName` | 実行される入口関数 | 種別 |
|---|---|---|---|
| `週次作業_スキャン対象整合.bat` | `WeeklyScanTargetSync` | `Invoke-WeeklyScanTargetSyncJob` | Composite Job |
| `月次作業_インストールレポート.bat` | `MonthlyInstallReport` | `Invoke-MonthlyInstallReportJob` | Composite Job |

週次作業は `ScanTargetSync` 単体ではありません。  
`DeviceListExport` で取得したCSVを、後続の `ScanTargetSync` が使う連携ジョブです。

月次作業も `LastMonthInstallExtract` 単体ではありません。  
`InstalledAppExport` で取得したLastMonthInstallExtract CSV群を、後続の `LastMonthInstallExtract` が解析する連携ジョブです。

例: `週次作業_スキャン対象整合.bat` の場合

```text
週次作業_スキャン対象整合.bat
  ↓
powershell.exe -File main\run_job.ps1 -JobName WeeklyScanTargetSync
```

この場合、`run_job.ps1` の `param` で次が受け取られます。

| 変数 | 値 |
|---|---|
| `$JobName` | `WeeklyScanTargetSync` |
| `$ConfigPath` | 指定がなければ `main\config\foundation.config.psd1` |
| `$JobRegistryPath` | 指定がなければ空文字。後で `main\config\foundation.jobs.psd1` に解決される |

その後、Foundationで以下が取得されます。

```text
Config        = foundation.config.psd1 の内容
JobRegistry   = foundation.jobs.psd1 の内容
JobDefinition = JobRegistry.Jobs['WeeklyScanTargetSync']
JobSettings   = Config.Jobs['WeeklyScanTargetSync']
Context       = 上記をまとめた実行時オブジェクト
```

Composite Job が子ジョブを呼ぶときは、子ジョブ側で別の `Context` が作られます。  
たとえば `WeeklyScanTargetSync` の内部で `DeviceListExport` を呼ぶと、子ジョブ側では `JobRegistry.Jobs['DeviceListExport']` と `Config.Jobs['DeviceListExport']` が使われます。

root `.bat` と `JobName` の対応だけを確認したい場合は、`docs/01_起動設定/bat起動入口とJobName.md` を参照してください。

---

## 11. よくある誤解

## 誤解1: `JobName` と `JobDefinition` は同じ

違います。

```text
JobName       = InstalledAppExport
JobDefinition = @{ ModulePath=...; CommandName=...; DomFeaturePaths=... }
```

`JobName` はキーです。  
`JobDefinition` はキーで引いた結果です。

## 誤解2: `ModulePath`, `CommandName`, `DomFeaturePaths` は `foundation.config.psd1` から来る

違います。  
これらは `foundation.jobs.psd1` から来ます。

```text
implementation definition = foundation.jobs.psd1
runtime settings          = foundation.config.psd1
```

## 誤解3: `$context` は設定値だけを持つ

違います。  
`$context` は設定値だけでなく、logger、services、ページ情報、実行ID、実装定義も持ちます。

---

## 12. 本ドキュメント内容の要点

```text
- JobName は、実行対象を示す文字列キーである
- JobDefinition は、foundation.jobs.psd1 から取れる実装定義である
- JobSettings は、foundation.config.psd1 から取れる実行時設定である
- Context は、JobDefinition と JobSettings の両方を持つ
- ModulePath / CommandName / DomFeaturePaths は foundation.jobs.psd1 側の情報である
- DownloadDirectory / DaysThreshold / RequiredHeaders などは foundation.config.psd1 側の情報である
- run_job.ps1 は JobName を受け取り、Foundationへ渡すだけの薄い入口である
```
