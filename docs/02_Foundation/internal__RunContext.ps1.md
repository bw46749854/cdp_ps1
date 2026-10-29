# main/modules/Foundation/internal/RunContext.ps1

## 1. このファイルを一言でいうと

このファイルは、ジョブ実行中に使う情報を `$context` として組み立てるファイルです。

`$context` は単なる設定値ではありません。  
実行ID、ジョブ名、ジョブ定義、実行時設定、logger、共通サービス、ブラウザページ状態をまとめた実行時オブジェクトです。

---

## このファイルを変更する典型ケース

- config / job registry / run context の読み込みや検証が変わった場合
- JobNameから実行commandへ到達する経路が変わった場合
- Foundation共通の初期化順序や公開サービスが変わった場合


## 2. このファイルが担当する範囲

担当すること:

```text
- 実行ごとのRunIdを作る
- logger serviceを作る
- filesystem serviceを作る
- browser serviceを作る
- workflow serviceを作る
- timing serviceを作る
- ConfigからCommonSettingsとJobSettingsを取り出す
- Contextオブジェクトを作る
- 実行終了時にCDP接続とloggerを閉じる
```

担当しないこと:

```text
- configファイルを読み込む
- job registryファイルを読み込む
- Feature moduleをImport-Moduleする
- JobDefinitionを取得する
- DOM操作そのものを実装する
- CSV読み書きの業務処理を実装する
```

`RunContext.ps1` は、すでに読み込まれた `Config` と `JobDefinition` を受け取って、実行時に使いやすい形へまとめます。

---

## 3. 関数呼び出しツリー

```text
New-FoundationRunContext
  ├─ Get-FoundationRunId
  ├─ Get-FoundationJobConfig
  ├─ New-FoundationLogger
  └─ New-FoundationServices
       ├─ New-FoundationTimingService
       ├─ New-FoundationLoggerService
       │    ├─ Get-Command Write-FoundationLog
       │    ├─ Get-Command Write-FoundationObject
       │    └─ Get-Command Write-FoundationSection
       ├─ New-FoundationFileSystemService
       │    ├─ Get-Command Initialize-FoundationOutputDirectory
       │    ├─ Get-Command Clear-DirectoryContentsSafely
       │    ├─ Get-Command Assert-FoundationSafeDirectory
       │    ├─ Get-Command Test-PathUnderDirectory
       │    └─ Get-Command Remove-FileIfExistsSafely
       ├─ New-FoundationBrowserService
       │    ├─ Get-Command Open-FoundationPage
       │    ├─ Get-Command Open-FoundationPageMatchingIdentity
       │    └─ Get-Command Set-FoundationDownloadDirectory
       └─ New-FoundationWorkflowService
            └─ Get-Command Invoke-ScrollableListWorkflow

Close-FoundationRunContext
  ├─ Close-CDPConnection
  └─ Close-FoundationLogger
```

---

## 4. `$context` の構造

`New-FoundationRunContext` は次のような `pscustomobject` を返します。

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

各プロパティの意味:

| プロパティ | 意味 |
|---|---|
| `RootPath` | `main` フォルダの絶対パス |
| `RunId` | 実行ごとの識別子 |
| `JobName` | 実行対象ジョブ名 |
| `JobDefinition` | `foundation.jobs.psd1` から取った実装定義 |
| `ConfigPath` | 使用した設定ファイルの絶対パス |
| `JobRegistryPath` | 使用したジョブ定義ファイルの絶対パス |
| `Config` | 設定全体 |
| `CommonSettings` | `Config.Common` |
| `JobSettings` | `Config.Jobs[JobName]` |
| `Logger` | ログ出力実体 |
| `Services` | 共通サービスの束 |
| `Page` | ブラウザページ。初期値は `$null` |

---

## 5. `JobDefinition` と `JobSettings` が両方入る理由

`JobDefinition` は、ジョブの実装定義です。

```text
ModulePath
CommandName
DomFeaturePaths
UsesDom
```

`JobSettings` は、ジョブの実行時設定です。

```text
DownloadDirectory
InputCsvPath
DaysThreshold
RequiredHeaders
```

両者は別のファイルから来ます。

```text
JobDefinition ← foundation.jobs.psd1
JobSettings   ← foundation.config.psd1
```

`Context` は、実行中に必要なこれらの情報をまとめて渡すため、両方を持ちます。

---

## 6. `Get-FoundationRunId`

## 何をするか

現在日時から実行IDを作ります。

形式:

```text
yyyyMMdd_HHmmss_fff
```

例:

```text
20260623_101530_123
```

## 何に使うか

実行ごとのログや成果物を識別するために使います。  
Composite jobや出力ファイル名で、過去実行と今回実行を区別する目的にも使えます。

---

## 7. `New-FoundationLoggerService`

## 何をするか

loggerに関する操作を、scriptblockとしてまとめたサービスを作ります。

返す構造:

```text
LoggerService
  WriteInfo
  WriteWarning
  WriteObject
  WriteSection
```

各プロパティは scriptblock です。

例:

```text
$context.Services.Logger.WriteInfo.Invoke('message')
```

## なぜ `Get-Command` してからscriptblockに閉じ込めるのか

`Write-FoundationLog` などの関数を直接名前で呼ぶのではなく、`Get-Command` で取得したコマンドを `&` で呼んでいます。

これにより、scriptblockが作られた時点で、呼び出す関数の実体を保持できます。  
`.GetNewClosure()` によって、`$Logger` や `$writeFoundationLogCommand` の値もscriptblock内に閉じ込めます。

---

## 8. `New-FoundationFileSystemService`

## 何をするか

安全なファイル・ディレクトリ操作をサービスとしてまとめます。

返す構造:

```text
FileSystemService
  InitializeOutputDirectory
  ClearDirectory
  AssertSafeDirectory
  TestPathUnderDirectory
  RemoveFileIfExists
```

Feature moduleは、可能な限りこれらのサービス経由でファイル操作を行います。  
これにより、出力ディレクトリ初期化や安全確認のルールを共通化できます。

## 副作用

このサービスの各scriptblockは、実際にファイルシステムを変更する可能性があります。

```text
- ディレクトリ作成
- ディレクトリ内ファイル削除
- ファイル削除
```

そのため、Rules系の純粋な業務判定関数から呼ぶべきではありません。

---

## 9. `New-FoundationBrowserService`

## 何をするか

ブラウザ/CDP関連の操作をサービスとしてまとめます。

返す構造:

```text
BrowserService
  OpenPage
  OpenPageMatchingIdentity
  SetDownloadDirectory
```

この時点では、まだブラウザ接続を開きません。  
`New-FoundationBrowserService` は「呼び出すためのscriptblock」を用意するだけです。

`Foundation.RunContext.Tests.ps1` でも、Browser service portを作るだけではCDPを呼ばないことが確認されています。

---

## 10. `New-FoundationWorkflowService`

## 何をするか

スクロール一覧走査の共通workflowを呼ぶためのサービスを作ります。

返す構造:

```text
WorkflowService
  InvokeScrollableList
```

`InvokeScrollableList` は、一覧画面をスクロールしながら行を処理する共通処理です。  
InstalledAppExportやScanTargetSyncのような画面一覧処理から利用されます。

`TimingService.SleepMilliseconds` が渡されている場合、スクロール処理の待機にも同じタイミングサービスを渡します。

---

## 11. `New-FoundationTimingService`

## 何をするか

時刻取得とsleepをまとめたサービスを作ります。

返す構造:

```text
TimingService
  Now
  TimestampText
  SleepMilliseconds
```

| scriptblock | 意味 |
|---|---|
| `Now` | 現在時刻を返す |
| `TimestampText` | `yyyy-MM-dd HH:mm:ss` 形式の文字列を返す |
| `SleepMilliseconds` | 指定ミリ秒だけ待機する |

時刻やsleepはテストで扱いにくい外部依存です。  
サービスとして束ねることで、テスト時に差し替えやすくなります。

---

## 12. `New-FoundationServices`

## 何をするか

各種サービスを1つの `Services` オブジェクトにまとめます。

構造:

```text
Services
  Logger
  FileSystem
  Browser
  Workflow
  Timing
```

この `Services` が `$context.Services` に入ります。

Feature moduleは、低レベル共通関数を直接呼ぶ代わりに、必要に応じて `$context.Services` を使います。

---

## 13. `New-FoundationRunContext`

## 何をするか

ジョブ実行に必要な情報を1つの `$context` にまとめます。

処理順序:

```text
1. RunId を作る
2. Config.Common を CommonSettings として取り出す
3. Config.Jobs[JobName] を JobSettings として取り出す
4. loggerを作る
5. servicesを作る
6. pscustomobjectとしてContextを返す
```

## 入力

| 引数 | 意味 |
|---|---|
| `RootPath` | main フォルダ |
| `Config` | 読み込み済み設定全体 |
| `JobName` | 実行対象ジョブ名 |
| `JobDefinition` | ジョブ実装定義。省略可だが通常Bootstrapから渡される |
| `ConfigPath` | 使用した設定ファイルパス |
| `JobRegistryPath` | 使用したジョブ定義ファイルパス |

## 出力

ジョブ関数に渡す `$context` です。

```text
& $command -Context $context
```

Feature job側の入口関数は、この `$context` を受け取ります。

---

## 14. `Close-FoundationRunContext`

## 何をするか

ジョブ実行後の後始末をします。

処理内容:

```text
1. Context.Page.CdpSession があれば、そのsessionを閉じる
2. なければ Close-CDPConnection -Quiet を呼ぶ
3. loggerを閉じる
4. 後始末中の例外は握りつぶす
```

`Bootstrap.ps1` の `finally` から呼ばれるため、ジョブが成功しても失敗しても実行されます。

## なぜ例外を握りつぶすのか

後始末中の失敗が、本来のジョブ失敗理由を上書きしないようにするためです。

例えば、ジョブ本体で重要なエラーが発生しているのに、後始末のCDP切断エラーで例外が置き換わると、原因調査が難しくなります。

---

## 15. PowerShell文法上のポイント

## `[pscustomobject]@{ ... }`

名前付きプロパティを持つオブジェクトを作ります。

```powershell
[pscustomobject]@{
  RootPath = $RootPath
  JobName = $JobName
}
```

作られた後は、次のようにプロパティアクセスできます。

```powershell
$context.JobName
$context.JobSettings
$context.Services
```

## scriptblock

`{ ... }` はscriptblockです。  
このプロジェクトでは、関数を値として持ち運ぶために使っています。

```text
$context.Services.FileSystem.ClearDirectory
```

のように、処理をオブジェクトのプロパティとして渡せます。

## `.GetNewClosure()`

scriptblockを作った時点の変数を閉じ込めます。

例:

```text
$Logger
$writeFoundationLogCommand
```

これがないと、後からscriptblockを実行したときに、期待した変数を参照できない場合があります。

## `& $command`

`&` はcall operatorです。  
変数に入っているコマンドやscriptblockを実行します。

```powershell
& $writeFoundationLogCommand -Logger $Logger -Level Info -Message $Message
```

---

## 16. 変更時の注意

```text
- Contextのプロパティ名を変えると、全Feature moduleに影響する
- Servicesのプロパティ名を変えると、依存ポートを使うジョブに影響する
- Browser service作成時に実際のCDP接続を始めてはいけない
- FileSystem serviceは副作用を持つため、Rules系から呼ばせない
- Close-FoundationRunContextで後始末例外をthrowすると、本来のエラーを隠す可能性がある
- JobSettingsはConfig.Jobs[JobName]そのものなので、overrideで書き換えると以後のジョブ実行中設定に反映される
```

`Bootstrap.ps1` では、Composite jobなどから渡された `JobSettingsOverrides` を `$context.JobSettings` に上書きします。  
そのため、`JobSettings` は読み取り専用のコピーではなく、実行中に一時上書きされる設定オブジェクトとして扱われます。

---

## 17. このファイルの設計境界を守るテスト

`Foundation.RunContext.Tests.ps1` で確認されていること:

```text
- Contextに Services が追加される
- Logger / FileSystem / Browser / Workflow / Timing が存在する
- 各service portがscriptblockである
- Browser service portの作成だけではCDP接続を行わない
- FileSystem service portが安全なテストディレクトリで動作する
- ConfigPath と JobRegistryPath がContextに保存される
- Logger serviceはscript-scopeの既定loggerに依存せずに呼べる
```

これらのテストにより、`Context` がFeature moduleに渡す実行時契約として安定していることが確認されます。

---

## 18. 本ドキュメント内容の要点

```text
- RunContext.ps1 は $context を作るファイルである
- $context は設定だけではなく、logger、services、page状態も持つ
- JobDefinition と JobSettings は別物で、両方Contextに入る
- Servicesは共通処理をscriptblockとして束ねたものである
- Browser serviceは作成時点ではCDP接続しない
- Close-FoundationRunContextはfinallyから呼ばれる後始末である
- Contextのプロパティ名変更は影響範囲が大きい
```
