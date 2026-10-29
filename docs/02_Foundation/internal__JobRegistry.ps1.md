# main/modules/Foundation/internal/JobRegistry.ps1

## 1. このファイルを一言でいうと

このファイルは、`foundation.jobs.psd1` を読み込み、`JobName` からジョブの実装定義を取得するファイルです。

実装定義とは、次のような情報です。

```text
ModulePath
CommandName
DomFeaturePath または DomFeaturePaths
UsesDom
```

このファイルは、ダウンロード先フォルダや日数閾値などの実行時設定を扱いません。  
それは `Config.ps1` の責務です。

---

## このファイルを変更する典型ケース

- config / job registry / run context の読み込みや検証が変わった場合
- JobNameから実行commandへ到達する経路が変わった場合
- Foundation共通の初期化順序や公開サービスが変わった場合


## 2. このファイルが担当する範囲

担当すること:

```text
- デフォルトの foundation.jobs.psd1 パスを作る
- foundation.jobs.psd1 を読み込む
- Jobs 構造を検証する
- 各ジョブ定義の必須キーを検証する
- DOMを使う/使わない契約を検証する
- ModulePath と DomFeaturePath(s) を絶対パス化する
- 指定JobNameのJobDefinitionを取り出す
- 指定ジョブの実体ファイルが存在するか確認する
```

担当しないこと:

```text
- config/foundation.config.psd1 を読む
- JobSettings を取得する
- Feature moduleをImport-Moduleする
- CommandNameの関数をGet-Commandする
- DOM JavaScriptを実際にブラウザへ登録する
- ジョブを実行する
```

---

## 3. 関数呼び出しツリー

```text
Import-FoundationJobRegistry
  ├─ Test-Path
  ├─ Import-PowerShellDataFile
  ├─ Assert-FoundationJobRegistry
  │    └─ Assert-FoundationJobDefinition
  │         ├─ Assert-FoundationJobDefinitionStringValue
  │         └─ Assert-FoundationJobDefinitionDomFeaturePathContract
  │              └─ Test-FoundationJobDefinitionUsesDom
  ├─ Resolve-FoundationJobRegistryPaths
  │    └─ Resolve-FoundationJobDefinitionPaths
  │         ├─ Resolve-FoundationJobRegistryPath
  │         └─ Resolve-FoundationJobDefinitionDomFeaturePaths
  └─ Assert-FoundationJobDefinitionFiles  ※ValidateAllFiles指定時のみ

Get-FoundationJobDefinition
  └─ Registry.Jobs[JobName] を取得

Assert-FoundationJobDefinitionFiles
  ├─ Assert-FoundationSingleJobDefinitionFiles
  │    └─ Get-FoundationJobDefinitionFilePaths
  └─ Registry全体または単一Definitionを検証
```

---

## 4. `Get-FoundationDefaultJobRegistryPath`

## 何をするか

`RootPath` から標準のジョブ定義ファイルパスを作ります。

```text
RootPath = <project>\main
  ↓
<project>\main\config\foundation.jobs.psd1
```

`run_job.ps1` から `JobRegistryPath` が渡されなかった場合、`Bootstrap.ps1` がこの関数を使います。

---

## 5. `Import-FoundationJobRegistry`

## 何をするか

`foundation.jobs.psd1` を読み込み、検証し、パス解決したレジストリを返します。

処理順序:

```text
1. ファイル存在確認
2. Import-PowerShellDataFile で読み込み
3. Assert-FoundationJobRegistry で構造検証
4. Resolve-FoundationJobRegistryPaths でパス解決
5. ValidateAllFiles が指定されていれば全ファイル存在確認
6. レジストリhashtableを返す
```

## 入力

| 引数 | 意味 |
|---|---|
| `Path` | foundation.jobs.psd1 のパス |
| `RootPath` | main フォルダのパス |
| `ValidateAllFiles` | 全ジョブのModulePath/DOMファイル存在を検証するか |

## 出力

パス解決済みの registry hashtable です。

```text
Registry
  Jobs
    InstalledAppExport
      ModulePath      = 絶対パス
      CommandName     = Invoke-InstalledAppExportJob
      DomFeaturePaths = 絶対パス配列
```

---

## 6. `Assert-FoundationJobRegistry`

## 何をするか

レジストリ全体の構造を検証します。

検証内容:

```text
- Jobs キーがある
- Jobs は hashtable である
- Jobs が空ではない
- 各 Jobs[JobName] が有効な定義である
```

各ジョブの詳細検証は `Assert-FoundationJobDefinition` に委譲します。

---

## 7. `Assert-FoundationJobDefinition`

## 何をするか

1つのジョブ定義を検証します。

必須:

```text
ModulePath
CommandName
```

DOMを使うジョブでは、次のどちらかが必要です。

```text
DomFeaturePath
DomFeaturePaths
```

DOMを使わないジョブでは、次を指定します。

```text
UsesDom = $false
```

## `CommandName` の検証

`CommandName` はPowerShellコマンド名として妥当な文字列である必要があります。

許可される形:

```text
Invoke-InstalledAppExportJob
Invoke-ScanTargetSyncJob
```

不正な例:

```text
123Job
Invoke Job
Invoke;Remove-Item
```

ここで不正な文字列を拒否することで、後続の `Get-Command` に危険または無効な名前を渡さないようにしています。

---

## 8. DOM契約の検証

DOM関連の判定は、次の関数で行います。

```text
Test-FoundationJobDefinitionUsesDom
Assert-FoundationJobDefinitionDomFeaturePathContract
```

## `UsesDom` がない場合

`UsesDom` が省略されている場合、DOMを使うジョブとして扱います。

```text
UsesDom なし
  ↓
DOMを使う
  ↓
DomFeaturePath または DomFeaturePaths が必要
```

## `UsesDom = $false` の場合

DOMを使わないジョブです。

```text
UsesDom = $false
  ↓
DomFeaturePath / DomFeaturePaths は指定してはいけない
```

LastMonthInstallExtractやCompositeJobsはこの形です。

## `DomFeaturePath` と `DomFeaturePaths`

単一ファイルなら `DomFeaturePath`、複数ファイルなら `DomFeaturePaths` です。  
両方同時には指定できません。

現在の主要DOMジョブでは、複数ファイルを順番に読み込むため `DomFeaturePaths` を使っています。

---

## 9. パス解決

## `Resolve-FoundationJobRegistryPath`

相対パスを `RootPath` 基準の絶対パスに変換します。

```text
modules\InstalledAppExport\InstalledAppExport.psm1
  ↓
<project>\main\modules\InstalledAppExport\InstalledAppExport.psm1
```

絶対パスが指定されていれば、そのまま返します。  
環境変数も `Expand-FoundationPath` によって展開されます。

## `Resolve-FoundationJobDefinitionPaths`

1つのジョブ定義内のパスを解決します。

```text
ModulePath      → 絶対パス化
DomFeaturePath  → 絶対パス化
DomFeaturePaths → 各要素を絶対パス化
```

`UsesDom = $false` の場合、DOM path は処理しません。

## 副作用

この関数群は、渡された hashtable の中身を書き換えます。

```text
変更前:
  ModulePath = modules\LastMonthInstallExtract\LastMonthInstallExtract.psm1

変更後:
  ModulePath = <project>\main\modules\LastMonthInstallExtract\LastMonthInstallExtract.psm1
```

---

## 10. ファイル存在確認

## 通常のImportでは全ジョブを検証しない

`Import-FoundationJobRegistry` は、通常は未使用ジョブのファイル存在までは要求しません。

理由は、今回実行しないジョブのファイル不備で、別ジョブの実行を止めないためです。

例:

```text
InstalledAppExportを実行したい
LastMonthInstallExtractのModulePathが壊れている
  ↓
通常importではLastMonthInstallExtractのファイル存在までは見ない
  ↓
InstalledAppExportのJobDefinitionだけ後で検証する
```

## 指定ジョブのファイルは検証する

`Bootstrap.ps1` の `Initialize-FoundationRuntime` は、指定JobNameの定義を取得した後、次を呼びます。

```text
Assert-FoundationJobDefinitionFiles -JobName $JobName -Definition $jobDefinition
```

これにより、実行対象ジョブの `ModulePath` や `DomFeaturePaths` のファイルが存在するか確認します。

---

## 11. `Get-FoundationJobDefinition`

## 何をするか

`Registry.Jobs[$JobName]` を取得します。

例:

```text
JobName = InstalledAppExport
  ↓
Registry.Jobs['InstalledAppExport']
  ↓
@{
  ModulePath = <absolute path>
  CommandName = Invoke-InstalledAppExportJob
  DomFeaturePaths = <absolute path array>
}
```

この戻り値が `$context.JobDefinition` になります。

## 失敗条件

```text
- Registry に Jobs がない
- Jobs に指定JobNameがない
```

---

## 12. PowerShell文法上のポイント

## `[switch]$ValidateAllFiles`

`[switch]` は、指定されたかどうかを表すPowerShellの引数型です。

```powershell
Import-FoundationJobRegistry -ValidateAllFiles
```

のように指定するとtrueになります。  
指定しなければfalseです。

## `[CmdletBinding(DefaultParameterSetName='Registry')]`

`Assert-FoundationJobDefinitionFiles` は、2種類の呼び出し方を持ちます。

```text
1. Registry全体を検証する
2. 1つのJobNameとDefinitionだけを検証する
```

ParameterSetにより、どちらの使い方かをPowerShellに区別させています。

## `New-Object System.Collections.Generic.List[string]`

可変長の文字列リストを作っています。  
DOM feature pathの数はジョブによって異なるため、リストに追加して最後に配列化しています。

---

## 13. 変更時の注意

```text
- UsesDomの既定値は「DOMを使う」である
- DOMを使わないジョブを追加する場合は UsesDom = $false が必要
- DomFeaturePath と DomFeaturePaths は同時指定できない
- DomFeaturePaths は文字列配列でなければならない
- Path解決はhashtableを直接書き換える
- CommandNameの許可文字ルールを変えると、起動できる関数名の範囲が変わる
- ValidateAllFilesの挙動を変えると、未使用ジョブの欠損で起動が止まる可能性がある
```

特に、通常import時に全ジョブのファイル存在を要求するように変更すると、1つの未使用ジョブの壊れで全ジョブが実行不能になります。  
現在は、実行対象ジョブだけを後で検証する設計です。

---

## 14. このファイルの設計境界を守るテスト

`Foundation.JobRegistry.Tests.ps1` で確認されていること:

```text
- 相対ModulePathがRootPath基準の絶対パスに変換される
- DomFeaturePathが絶対パス化される
- DomFeaturePathsの順序が維持される
- Registry全体は1つのhashtableとして返る
- Jobsがない、空、hashtableでない場合はエラー
- ModulePath / CommandName が空ならエラー
- 存在しないJobNameを取得するとエラー
- 未使用ジョブのファイル欠損では通常importを止めない
- 指定ジョブのファイル欠損は検出する
```

`Foundation.JobRegistry.UsesDom.Tests.ps1` で確認されていること:

```text
- UsesDom = $false のジョブはDOM pathなしで許可される
- UsesDom = $false にDOM pathを指定するとエラー
- UsesDom省略はDOMジョブとして扱われる
```

---

## 15. 本ドキュメント内容の要点

```text
- JobRegistry.ps1 は foundation.jobs.psd1 を扱う
- JobDefinition は Registry.Jobs[JobName] である
- JobDefinitionには ModulePath / CommandName / DOM path が入る
- UsesDom省略時はDOMを使うジョブとして扱う
- UsesDom = $false のジョブにDOM pathを書いてはいけない
- 通常importでは未使用ジョブのファイル欠損までは検証しない
- 実行対象ジョブのファイル存在はBootstrap側で検証される
```
