# main/config/foundation.jobs.psd1

## 1. このファイルを一言でいうと

このファイルは、ジョブ名と実装を対応付けるジョブレジストリです。

`-JobName InstalledAppExport` のように指定された名前を、次の情報に変換します。

```text
- 読み込むPowerShellモジュール
- 実行する入口関数
- 必要なDOM JavaScript feature
- DOMを使うジョブかどうか
```

このファイルは、ジョブの実行時設定を持ちません。  
フォルダ、タイムアウト、CSVファイル名、閾値などは `foundation.config.psd1` 側にあります。

---

## このファイルを変更する典型ケース

- 新しい `JobName` を追加する場合
- 既存Jobの `ModulePath` が変わった場合
- 既存Jobの `CommandName` が変わった場合
- DOMを使うJobの `DomFeaturePaths` が変わった場合
- DOM JavaScript feature の読み込み順が変わった場合
- DOMを使わないJobの `UsesDom = $false` 指定が変わった場合
- Composite Job の登録先 module / command が変わった場合


## 2. このファイルが担当する範囲

担当すること:

```text
- JobName から ModulePath を引けるようにする
- JobName から CommandName を引けるようにする
- DOMを使うジョブでは DomFeaturePaths を定義する
- DOMを使わないジョブでは UsesDom = $false を定義する
```

担当しないこと:

```text
- ダウンロード先フォルダを決める
- CSVファイル名を決める
- 日数閾値を決める
- CDPタイムアウトを決める
- ログ出力設定を決める
- 各ジョブの業務ロジックを定義する
```

---

## 3. ファイル全体の構造

このファイルは PowerShell data file です。  
拡張子は `.psd1` で、中身は hashtable 形式です。

最上位には `Jobs` キーがあります。

```text
@{
  Jobs = @{
    InstalledAppExport = @{ ... }
    ScanTargetSync = @{ ... }
    DeviceListExport = @{ ... }
    LastMonthInstallExtract = @{ ... }
    WeeklyScanTargetSync = @{ ... }
    MonthlyInstallReport = @{ ... }
  }
}
```

`Jobs` の直下のキーが、実行時に指定する `JobName` です。

例:

```powershell
powershell.exe -File main\run_job.ps1 -JobName InstalledAppExport
```

この場合、`Jobs['InstalledAppExport']` が使用されます。

---

## 4. 各キーの意味

## `ModulePath`

そのジョブのPowerShellモジュールファイルです。

例:

```text
InstalledAppExport.ModulePath = modules\InstalledAppExport\InstalledAppExport.psm1
```

起動時には、`JobRegistry.ps1` によって `main` フォルダからの絶対パスに解決されます。

```text
modules\InstalledAppExport\InstalledAppExport.psm1
  ↓
C:\...\main\modules\InstalledAppExport\InstalledAppExport.psm1
```

その後、`Bootstrap.ps1` の `Import-FoundationJobModule` がこのパスを `Import-Module` します。

## `CommandName`

そのジョブの入口関数名です。

例:

```text
InstalledAppExport.CommandName = Invoke-InstalledAppExportJob
```

`ModulePath` のモジュールを読み込んだ後、`Get-Command` でこの関数を取得し、次のように実行されます。

```text
& $command -Context $context
```

`ModulePath` に書かれたモジュールが、この `CommandName` の関数を export していない場合、起動時に失敗します。

## `DomFeaturePaths`

DOMを使うジョブで、ブラウザ側に登録するJavaScriptファイル一覧です。

例: `InstalledAppExport`

```text
contract.js
list.js
detail.js
apps.js
actions.js
index.js
```

順番に意味があります。  
`contract.js` や個別機能ファイルを先に読み、最後に `index.js` で操作群を束ねる構成です。  
順番を崩すと、JavaScript側で未定義の関数を参照する可能性があります。

## `UsesDom`

DOMを使わないジョブでは、`UsesDom = $false` を指定します。

例:

```text
LastMonthInstallExtract = @{
  ModulePath = 'modules\LastMonthInstallExtract\LastMonthInstallExtract.psm1'
  CommandName = 'Invoke-LastMonthInstallExtractJob'
  UsesDom = $false
}
```

`UsesDom = $false` のジョブには、`DomFeaturePath` や `DomFeaturePaths` を指定してはいけません。  
`JobRegistry.ps1` の検証でエラーになります。

---

## 5. 現在定義されているジョブ

| JobName | ModulePath | CommandName | DOM定義 | 役割 |
|---|---|---|---|---|
| `InstalledAppExport` | `modules\InstalledAppExport\InstalledAppExport.psm1` | `Invoke-InstalledAppExportJob` | `DomFeaturePaths` | 端末一覧から端末ごとのLastMonthInstallExtract CSVを取得する |
| `ScanTargetSync` | `modules\ScanTargetSync\ScanTargetSync.psm1` | `Invoke-ScanTargetSyncJob` | `DomFeaturePaths` | CSVと画面一覧を突き合わせ、対象端末のチェックボックスを操作する |
| `DeviceListExport` | `modules\DeviceListExport\DeviceListExport.psm1` | `Invoke-DeviceListExportJob` | `DomFeaturePaths` | デバイス一覧CSVを画面からエクスポートする |
| `LastMonthInstallExtract` | `modules\LastMonthInstallExtract\LastMonthInstallExtract.psm1` | `Invoke-LastMonthInstallExtractJob` | `UsesDom = $false` | ダウンロード済みLastMonthInstallExtract CSVを解析する |
| `WeeklyScanTargetSync` | `modules\CompositeJobs\CompositeJobs.psm1` | `Invoke-WeeklyScanTargetSyncJob` | `UsesDom = $false` | DeviceListExport後にScanTargetSyncを実行する連携ジョブ |
| `MonthlyInstallReport` | `modules\CompositeJobs\CompositeJobs.psm1` | `Invoke-MonthlyInstallReportJob` | `UsesDom = $false` | InstalledAppExport後にLastMonthInstallExtractを実行する連携ジョブ |

Composite jobは、親ジョブ自身ではDOMを直接使いません。  
子ジョブを順番に呼び出すだけなので、`UsesDom = $false` です。

root の `.bat` は、現時点では単体Jobではなく Composite Job を呼びます。

| 起動ファイル | JobName |
|---|---|
| `週次作業_スキャン対象整合.bat` | `WeeklyScanTargetSync` |
| `月次作業_インストールレポート.bat` | `MonthlyInstallReport` |

詳細は `docs/01_起動設定/bat起動入口とJobName.md` を参照してください。

---

## 6. 実行時にこのファイルが使われる流れ

```text
Invoke-FoundationEntrypoint
  └─ Initialize-FoundationRuntime
       ├─ Get-FoundationDefaultJobRegistryPath
       │    └─ main\config\foundation.jobs.psd1
       ├─ Import-FoundationJobRegistry
       │    ├─ Import-PowerShellDataFile
       │    ├─ Assert-FoundationJobRegistry
       │    └─ Resolve-FoundationJobRegistryPaths
       ├─ Get-FoundationJobDefinition
       │    └─ Jobs[$JobName] を取得
       └─ New-FoundationRunContext
            └─ Context.JobDefinition に格納
```

起動後は、`$context.JobDefinition` から `ModulePath` と `CommandName` が使われます。

---

## 7. PowerShell文法上のポイント

## `.psd1`

`.psd1` は PowerShell data file です。  
通常の `.ps1` と違い、主にデータ定義に使います。

このファイルは `Import-PowerShellDataFile` で読み込まれます。  
読み込み結果は hashtable です。

## `@{ ... }`

`@{ ... }` は hashtable です。  
キーと値の対応表を作ります。

```powershell
@{
  ModulePath = 'modules\InstalledAppExport\InstalledAppExport.psm1'
  CommandName = 'Invoke-InstalledAppExportJob'
}
```

これは次のような辞書です。

```text
ModulePath  → modules\InstalledAppExport\InstalledAppExport.psm1
CommandName → Invoke-InstalledAppExportJob
```

## `@( ... )`

`@( ... )` は配列です。  
`DomFeaturePaths` では、複数のJavaScriptファイルを順序付きで並べるために使っています。

---

## 8. 変更時の注意

## 新しいジョブを追加する場合

最低限、次を追加します。

```text
Jobs.<NewJob>.ModulePath
Jobs.<NewJob>.CommandName
```

DOMを使うジョブなら、次も必要です。

```text
Jobs.<NewJob>.DomFeaturePaths
```

DOMを使わないジョブなら、次を指定します。

```text
Jobs.<NewJob>.UsesDom = $false
```

同時に、`foundation.config.psd1` の `Jobs.<NewJob>` に実行時設定を追加する必要があります。

## `CommandName` を変更する場合

`CommandName` を変更しただけでは不十分です。  
該当Feature moduleの `.psm1` が、その関数を `Export-ModuleMember` している必要があります。

```text
変更前:
  CommandName = Invoke-InstalledAppExportJob

変更後:
  CommandName = Invoke-NewInstalledAppExportJob

必要:
  modules\InstalledAppExport\InstalledAppExport.psm1 が Invoke-NewInstalledAppExportJob を export していること
```

## `DomFeaturePaths` の順番を変更する場合

JavaScript側の依存関係が壊れる可能性があります。  
特に `index.js` を先頭に移動すると、index側が参照する関数がまだ定義されていない状態になる可能性があります。

`DomFeaturePaths` の順序は実行契約です。  
通常は `contract.js` や個別機能ファイルを先に読み、最後に `index.js` を読みます。  
`index.js` は、それまでに登録された part object を合成して `window.__XxxDomHelper` を公開するため、先に読むと helper 登録に失敗します。

---

## 9. このファイルの設計境界を守るテスト

`Foundation.JobRegistry.Tests.ps1` では、次の契約が確認されています。

```text
- ModulePath と DomFeaturePath が相対パスから絶対パスに解決される
- DomFeaturePaths の順番が維持される
- Jobs が空ならエラー
- ModulePath が空ならエラー
- CommandName が空ならエラー
- CommandName がPowerShellコマンド名として不正ならエラー
- 通常import時は、未使用ジョブのファイル存在までは要求しない
- 指定ジョブのファイル検証時には、ModulePathやDOMファイルの存在を確認する
```

`Foundation.JobRegistry.UsesDom.Tests.ps1` では、次の契約が確認されています。

```text
- UsesDom = $false のジョブは DOM feature path なしで許可される
- UsesDom = $false に DOM feature path を指定するとエラー
- UsesDom を省略したジョブは、DOMを使うジョブとして扱われる
```

---

## 10. 本ドキュメント内容の要点

```text
- foundation.jobs.psd1 はジョブの実装定義である
- ModulePath / CommandName / DomFeaturePaths はこのファイルに書く
- DownloadDirectory や DaysThreshold などの実行時設定はここには書かない
- JobName は Jobs のキーである
- JobDefinition は Jobs[JobName] の値である
- DOMを使わないジョブは UsesDom = $false にする
- DomFeaturePaths は順序付きの契約である
```

## sample設定との関係

初期導入時は `main/config/foundation.jobs.sample.psd1` をコピーして `foundation.jobs.psd1` を作ります。
sample側の読み方は `docs/01_起動設定/config__foundation.jobs.sample.psd1.md` を参照してください。
