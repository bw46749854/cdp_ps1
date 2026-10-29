# modules/Foundation/internal/Bootstrap.ps1

## 1. このファイルを一言でいうと

`Bootstrap.ps1` は、`run_job.ps1` から受け取ったジョブ名を、実際のジョブモジュールとジョブ関数へつなぐ起動制御ファイルです。

このファイルは、次の一連の起動処理を担当します。

```text
実行ルートを決める
  ↓
設定ファイルを読む
  ↓
ジョブ定義ファイルを読む
  ↓
JobNameから実行対象ジョブを解決する
  ↓
RunContextを作る
  ↓
ジョブモジュールをImportする
  ↓
ジョブ関数をGet-Commandで取得する
  ↓
& でジョブ関数を実行する
  ↓
最後にRunContextを閉じる
```

## このファイルを変更する典型ケース

- config / job registry / run context の読み込みや検証が変わった場合
- JobNameから実行commandへ到達する経路が変わった場合
- Foundation共通の初期化順序や公開サービスが変わった場合


## 2. このファイルが担当する範囲

このファイルが担当するのは、ジョブを実行できる状態にするまでの共通起動処理です。

具体的には次を行います。

- `RootPath` を実在するパスに解決する
- `foundation.config.psd1` を読み込む
- `foundation.jobs.psd1` を読み込む
- `JobName` に対応するジョブ定義を取得する
- ジョブ定義に書かれたファイルが存在することを確認する
- `New-FoundationRunContext` で実行Contextを作る
- ジョブモジュールを `Import-Module` する
- ジョブ定義に書かれた `CommandName` を実行可能な関数として取得する
- 取得したジョブ関数を実行する
- エラーをログに残し、呼び出し元へ再送出する
- 最後にCDP接続やログを閉じる

## 3. このファイルが担当しない範囲

このファイルは、各ジョブの中身を知りません。

担当しないものは次です。

- 端末一覧をどう読むか
- ScanTargetSyncでどの端末をチェックONにするか
- DeviceListExportでどのボタンを押すか
- LastMonthInstallExtract CSVをどう解析するか
- DOM selectorの詳細
- Chrome DevTools Protocol の通信実装
- CSVの入出力形式
- ダウンロードファイルのリネーム規則

`Bootstrap.ps1` は、あくまで「どのジョブを呼ぶか」を解決する場所です。ジョブの業務ロジックは対象ジョブのモジュールにあります。

## 4. このファイルが必要になる実行シナリオ

ユーザーが次のように実行したとします。

```powershell
.\run_job.ps1 -JobName InstalledAppExport
```

このとき `run_job.ps1` は、Foundationモジュールを読み込んだあと、`Invoke-FoundationEntrypoint` を呼びます。

```text
run_job.ps1
  ↓
Invoke-FoundationEntrypoint
```

`Invoke-FoundationEntrypoint` は、このファイルで定義されています。

`JobName = InstalledAppExport` の場合、処理は最終的に次へつながります。

```text
JobName = InstalledAppExport
  ↓
config/foundation.jobs.psd1 の Jobs['InstalledAppExport']
  ↓
ModulePath  = modules\InstalledAppExport\InstalledAppExport.psm1
CommandName = Invoke-InstalledAppExportJob
  ↓
Import-Module modules\InstalledAppExport\InstalledAppExport.psm1
  ↓
Get-Command Invoke-InstalledAppExportJob
  ↓
& Invoke-InstalledAppExportJob -Context $context
```

## 5. このファイル内の関数呼び出しツリー

主入口は `Invoke-FoundationEntrypoint` です。

```text
Invoke-FoundationEntrypoint
│
├─ Resolve-FoundationRoot
│
├─ Initialize-FoundationRuntime
│  │
│  ├─ Test-Path
│  │    └─ ConfigPath の存在確認
│  │
│  ├─ Resolve-Path
│  │    └─ ConfigPath を実パスへ変換
│  │
│  ├─ Import-FoundationConfig
│  │    └─ foundation.config.psd1 を読む
│  │
│  ├─ Get-FoundationDefaultJobRegistryPath
│  │    └─ JobRegistryPath 未指定時の標準パスを作る
│  │
│  ├─ Test-Path
│  │    └─ JobRegistryPath の存在確認
│  │
│  ├─ Resolve-Path
│  │    └─ JobRegistryPath を実パスへ変換
│  │
│  ├─ Import-FoundationJobRegistry
│  │    └─ foundation.jobs.psd1 を読む
│  │
│  ├─ Get-FoundationJobDefinition
│  │    └─ JobName に対応する定義を取得
│  │
│  ├─ Assert-FoundationJobDefinitionFiles
│  │    └─ ModulePath や DOM feature file の存在確認
│  │
│  └─ New-FoundationRunContext
│       └─ 実行中に使う設定・logger・servicesをまとめる
│
├─ JobSettingsOverrides の反映
│
├─ Import-FoundationJobModule
│  │
│  ├─ Get-FoundationJobDefinitionValue
│  │    └─ ModulePath を取得
│  │
│  ├─ Test-Path
│  │    └─ ジョブモジュールの存在確認
│  │
│  └─ Import-Module
│       └─ 対象ジョブの .psm1 を読み込む
│
├─ Get-FoundationJobCommand
│  │
│  ├─ Get-FoundationJobDefinitionValue
│  │    └─ CommandName を取得
│  │
│  └─ Get-Command
│       └─ 実行可能な関数として取得
│
├─ Write-FoundationSection
│    └─ ジョブ開始ログ
│
├─ & $command -Context $context
│    └─ 実ジョブを実行
│
├─ Write-FoundationSection
│    └─ ジョブ正常終了ログ
│
└─ finally
   └─ Close-FoundationRunContext
      └─ CDP接続やloggerを閉じる
```

## 6. 扱うデータの形

### `JobDefinition`

`JobDefinition` は、`foundation.jobs.psd1` の `Jobs` から取得されるジョブ定義です。

例: `InstalledAppExport`

```text
JobDefinition
  ModulePath      : modules\InstalledAppExport\InstalledAppExport.psm1
  CommandName     : Invoke-InstalledAppExportJob
  DomFeaturePaths :
    - dom\features\installed-app-export\contract.js
    - dom\features\installed-app-export\list.js
    - dom\features\installed-app-export\detail.js
    - dom\features\installed-app-export\apps.js
    - dom\features\installed-app-export\actions.js
    - dom\features\installed-app-export\index.js
```

このデータは、「ジョブを実行するには何を読み、何を呼ぶか」を表します。

### `Context`

`Initialize-FoundationRuntime` は、最後に `New-FoundationRunContext` を呼びます。

`Context` は、実行中に必要な共通情報の箱です。

```text
Context
  RootPath
  RunId
  JobName
  JobDefinition
  ConfigPath
  JobRegistryPath
  Config
  CommonSettings
  JobSettings
  Logger
  Services
  Page
```

このファイルでは、`Context` を作り、ジョブ関数へ渡します。

```text
& $command -Context $context
```

つまり、各ジョブは `Context` を受け取ることで、設定、logger、ファイルシステムサービス、ブラウザサービスなどを利用できます。

### `JobSettingsOverrides`

`Invoke-FoundationEntrypoint` は、任意で `$JobSettingsOverrides` を受け取ります。

これは、ジョブ設定を一時的に上書きするためのhashtableです。

```text
JobSettingsOverrides
  Key   : 上書きしたい設定名
  Value : 上書き後の値
```

CompositeJobsのように、あるジョブから別ジョブを呼ぶ場合、次のジョブにだけ設定を一時的に渡す用途で使います。

## 7. 関数ごとの説明

## Resolve-FoundationRoot

### 何をするか

実行ルートディレクトリを決めます。

`RootPath` が指定されていれば、そのパスを `Resolve-Path` で実在パスに変換して返します。指定されていなければ、現在の作業ディレクトリを返します。

### 入力

| 引数 | 型 | 必須 | 意味 |
|---|---|---|---|
| `RootPath` | string | いいえ | 実行ルート候補。未指定なら現在ディレクトリを使う |

### 出力

実在するルートディレクトリのパス文字列です。

### 副作用

ありません。ファイルは読み書きしません。

### 失敗条件

`RootPath` が指定されていて、そのパスが存在しない場合、`Resolve-Path` が失敗します。

### PowerShell文法上のポイント

```powershell
[string]::IsNullOrWhiteSpace($RootPath)
```

これは、`RootPath` が未指定、空文字、空白だけかどうかを判定しています。

## Initialize-FoundationRuntime

### 何をするか

ジョブ実行前に必要な設定・ジョブ定義・Contextを作ります。

この関数は、`Bootstrap.ps1` の中で最も重要な準備関数です。

### 入力

| 引数 | 型 | 必須 | 意味 |
|---|---|---|---|
| `RootPath` | string | はい | mainディレクトリ |
| `ConfigPath` | string | はい | foundation.config.psd1 のパス |
| `JobName` | string | はい | 実行するジョブ名 |
| `JobRegistryPath` | string | いいえ | foundation.jobs.psd1 のパス。未指定なら標準パス |

### 出力

`New-FoundationRunContext` が作った `Context` を返します。

### 処理の順序

```text
ConfigPath が存在するか確認
  ↓
ConfigPath を実パス化
  ↓
Import-FoundationConfig で設定を読む
  ↓
JobRegistryPath が未指定なら標準パスを使う
  ↓
JobRegistryPath が存在するか確認
  ↓
JobRegistryPath を実パス化
  ↓
Import-FoundationJobRegistry でジョブ定義を読む
  ↓
Get-FoundationJobDefinition で JobName に対応する定義を取得
  ↓
Assert-FoundationJobDefinitionFiles で必要ファイルの存在確認
  ↓
New-FoundationRunContext でContextを作る
```

### 副作用

- 設定ファイルを読みます。
- ジョブ定義ファイルを読みます。
- Context作成時にloggerなどのサービスを作ります。

### 失敗条件

| 条件 | エラーの意味 |
|---|---|
| `ConfigPath` が存在しない | 実行設定が見つからない |
| `JobRegistryPath` が存在しない | ジョブ一覧が見つからない |
| `JobName` がジョブ定義にない | 指定されたジョブを実行できない |
| ジョブ定義の `ModulePath` が存在しない | 対象ジョブのモジュールが見つからない |
| DOMジョブの `DomFeaturePaths` が存在しない | DOM bundle登録に必要なJavaScriptが見つからない |

### 変更時の注意

この関数は、設定読み込みとジョブ定義読み込みの順序を固定しています。

特に、`New-FoundationRunContext` の前に `Get-FoundationJobDefinition` を済ませている点が重要です。Contextには `JobDefinition` と `JobSettings` が入るため、ジョブ定義が未解決のままContextを作ると、後続のジョブが自分のDOM bundleやmodule pathを判断できなくなります。

## Import-FoundationJobModule

### 何をするか

ジョブ定義の `ModulePath` を読み取り、そのPowerShellモジュールを `Import-Module` します。

たとえば `InstalledAppExport` の場合、次を読み込みます。

```text
modules\InstalledAppExport\InstalledAppExport.psm1
```

### 入力

| 引数 | 型 | 必須 | 意味 |
|---|---|---|---|
| `JobDefinition` | object | はい | foundation.jobs.psd1 から取得したジョブ定義 |
| `JobName` | string | はい | エラーメッセージ用のジョブ名 |

### 出力

明示的な戻り値はありません。

### 副作用

PowerShellモジュールを読み込みます。

読み込まれた `.psm1` は、さらに `internal/*.ps1` をdot-sourceします。たとえば `InstalledAppExport.psm1` は、`Models.ps1`、`DomOperations.ps1`、`DomAdapter.ps1`、`Download.ps1`、`Output.ps1`、`RowAction.ps1`、`Dependencies.ps1`、`Workflow.ps1`、`Runner.ps1` を同じモジュールスコープへ読み込みます。

### 失敗条件

- `ModulePath` がジョブ定義にない
- `ModulePath` が空
- `ModulePath` のファイルが存在しない
- `Import-Module` 中に、対象モジュール内のdot-sourceが失敗する

### PowerShell文法上のポイント

```powershell
Import-Module -Name $modulePath -Force -DisableNameChecking
```

`-Force` は再読み込みを許可します。テストや繰り返し実行時に古い関数定義が残る問題を避けやすくなります。

`-DisableNameChecking` は、PowerShellの命名警告を抑制します。プロジェクト内の関数名がPowerShellの推奨動詞と完全一致しない場合でも警告を出さないためです。

## Get-FoundationJobCommand

### 何をするか

ジョブ定義の `CommandName` を読み取り、PowerShellが実行できる関数として取得します。

例:

```text
CommandName = Invoke-InstalledAppExportJob
```

この場合、`Get-Command Invoke-InstalledAppExportJob -CommandType Function` を実行し、関数が存在するか確認します。

### 入力

| 引数 | 型 | 必須 | 意味 |
|---|---|---|---|
| `JobDefinition` | object | はい | ジョブ定義 |
| `JobName` | string | はい | エラーメッセージ用のジョブ名 |

### 出力

PowerShellのCommandInfoオブジェクトです。後で `& $command` により実行されます。

### 失敗条件

- `CommandName` がジョブ定義にない
- `CommandName` が空
- モジュールをImportしたあとでも、その名前の関数が存在しない

### 変更時の注意

`foundation.jobs.psd1` の `CommandName` と、ジョブモジュールの `Export-ModuleMember` で公開されている関数名は一致している必要があります。

たとえば、`InstalledAppExport.psm1` が `Invoke-InstalledAppExportJob` をExportしているのに、`foundation.jobs.psd1` 側を `Invoke-InstalledAppExport` に変えると、この関数で失敗します。

## Invoke-FoundationEntrypoint

### 何をするか

Foundationの公開入口です。

`run_job.ps1` やCompositeJobsから呼ばれ、指定されたジョブを実行します。

### 入力

| 引数 | 型 | 必須 | 意味 |
|---|---|---|---|
| `RootPath` | string | はい | mainディレクトリ |
| `ConfigPath` | string | はい | 設定ファイルパス |
| `JobName` | string | はい | 実行するジョブ名 |
| `JobRegistryPath` | string | いいえ | ジョブ定義ファイルパス |
| `JobSettingsOverrides` | hashtable | いいえ | 一時的なジョブ設定上書き |

### 出力

実行したジョブ関数の戻り値です。

たとえば `InstalledAppExport` ジョブなら、InstalledAppExport側のRunner/Workflowが作った結果オブジェクトが返ります。

### 処理の順序

```text
RootPathを解決
  ↓
Contextを初期化
  ↓
JobSettingsOverridesがあればContext.JobSettingsへ反映
  ↓
対象ジョブモジュールをImport
  ↓
対象ジョブ関数を取得
  ↓
開始ログ出力
  ↓
& $command -Context $context でジョブ実行
  ↓
正常終了ログ出力
  ↓
戻り値を返す
  ↓
finallyでContextを閉じる
```

### 副作用

- 設定ファイルを読む
- ジョブ定義ファイルを読む
- ジョブモジュールをImportする
- ログを書く
- 実ジョブを実行する
- ジョブ次第でブラウザ操作やファイル操作が発生する
- 最後にCDP接続やloggerを閉じる

### エラー処理

`try/catch/finally` を使っています。

```text
try
  通常の起動・ジョブ実行

catch
  エラーメッセージをloggerまたはWrite-Hostへ出す
  throwで再送出する

finally
  ContextがあればClose-FoundationRunContextを呼ぶ
```

`catch` でログを書いた後に `throw` している点が重要です。

ログを書いて終わるのではなく、呼び出し元にも失敗を伝えます。これにより、batやCIなど外側の仕組みが失敗を検知できます。

### PowerShell文法上のポイント

#### `& $command`

`$command` には `Get-Command` で取得した関数情報が入っています。

```powershell
$jobResult = & $command -Context $context
```

この書き方により、`JobName` に応じて別の関数を動的に実行できます。

`InstalledAppExport` なら実質的に次です。

```powershell
Invoke-InstalledAppExportJob -Context $context
```

`LastMonthInstallExtract` なら実質的に次です。

```powershell
Invoke-LastMonthInstallExtractJob -Context $context
```

#### `finally`

```powershell
finally {
    if ($context) { Close-FoundationRunContext -Context $context }
}
```

ジョブが成功しても失敗しても、Contextを閉じます。

ブラウザ/CDP接続やログ出力を開いたままにしないための後始末です。

## 8. このファイルを変更するときの判断基準

### 変更してよい可能性があるもの

- エラーメッセージをより具体的にする
- 開始/終了ログの文言を改善する
- `JobSettingsOverrides` の扱いを明確化する
- 起動前検証を追加する

### 慎重に扱うべきもの

| 箇所 | 理由 |
|---|---|
| `Initialize-FoundationRuntime` の順序 | Context作成前に設定とジョブ定義が必要だから |
| `Import-FoundationJobModule` と `Get-FoundationJobCommand` の順序 | モジュールをImportしないと関数が存在しないから |
| `catch` 内の `throw` | これを消すと外側が失敗を検知できなくなるから |
| `finally` の `Close-FoundationRunContext` | これを消すとCDP接続やloggerが残る可能性があるから |
| `& $command -Context $context` | JobNameに応じた動的実行の中心だから |

### やってはいけない変更

- `Bootstrap.ps1` にInstalledAppExportやScanTargetSync固有の業務処理を書く
- `Bootstrap.ps1` からDOM操作を直接呼ぶ
- `Bootstrap.ps1` からCSV解析やダウンロード処理を直接呼ぶ
- `JobName` ごとの `if` / `switch` を大量に増やして、特定ジョブ専用分岐を持たせる

このファイルは共通入口です。特定ジョブの都合を入れ始めると、共通基盤が肥大化します。

## 9. 関連するテスト観点

このファイルに関係するテスト観点は次です。

| 観点 | 内容 |
|---|---|
| Entrypoint | 指定JobNameに対応するジョブが呼ばれるか |
| Config | 設定ファイルが正しく読まれるか |
| JobRegistry | `ModulePath`, `CommandName`, `DomFeaturePaths` が検証されるか |
| PublicApi | Foundationモジュールが必要な関数を外部公開しているか |
| Architecture | Entry point / Bootstrap は例外的に共通起動処理を持ってよいが、業務詳細は持たないこと |

`Bootstrap.ps1` を変更した場合、失敗する可能性が高いのは次の種類のテストです。

```text
Foundation.Entrypoint.Tests.ps1
Foundation.Config.Tests.ps1
Foundation.JobRegistry.Tests.ps1
Foundation.PublicApi.Tests.ps1
Architecture.Tests.ps1
```

## 10. 本ドキュメント内容の要点

このファイルを読んだ後は、次を説明できる状態になっているべきです。

```text
run_job.ps1 から Invoke-InstalledAppExportJob まで、どうつながるか
JobName がどこで ModulePath / CommandName に変換されるか
Context がどのタイミングで作られるか
JobSettingsOverrides がどこで反映されるか
& $command がなぜ必要か
catch でログを書いたあと throw する理由
finally で Close-FoundationRunContext を呼ぶ理由
Bootstrap.ps1 に業務ロジックを書いてはいけない理由
```
