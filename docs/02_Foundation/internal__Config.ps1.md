# main/modules/Foundation/internal/Config.ps1

## 1. このファイルを一言でいうと

このファイルは、`foundation.config.psd1` を読み込み、最低限の構造検証を行い、パス設定を解決済みの値に変換するファイルです。

このファイルは、ジョブの実装定義を扱いません。  
`ModulePath` や `CommandName` は `JobRegistry.ps1` の責務です。

---

## このファイルを変更する典型ケース

- config / job registry / run context の読み込みや検証が変わった場合
- JobNameから実行commandへ到達する経路が変わった場合
- Foundation共通の初期化順序や公開サービスが変わった場合


## 2. このファイルが担当する範囲

担当すること:

```text
- configファイルが存在するか確認する
- Import-PowerShellDataFile で psd1 を読み込む
- Common と Jobs が存在するか確認する
- 指定JobNameの設定を取り出す
- 環境変数を展開する
- *Path / *Directory の設定値を絶対パスに変換する
```

担当しないこと:

```text
- JobNameが実装定義に存在するか確認する
- ModulePathやCommandNameを検証する
- DOM feature pathを検証する
- 設定値の業務的妥当性をすべて判定する
- CSVファイルそのものを読む
- 出力フォルダを実際に作成する
```

---

## 3. 関数呼び出しツリー

```text
Import-FoundationConfig
  ├─ Test-Path
  ├─ Import-PowerShellDataFile
  ├─ Assert-FoundationConfig
  └─ Resolve-FoundationConfigPaths
       └─ Resolve-FoundationHashtablePaths
            ├─ Resolve-FoundationHashtablePaths  ※ネストしたhashtableを再帰処理
            └─ Expand-FoundationPath

Get-FoundationJobConfig
  └─ Config.Jobs[JobName] を取得

Expand-FoundationPath
  └─ Environment.ExpandEnvironmentVariables
```

---

## 4. `Import-FoundationConfig`

## 何をするか

指定された `foundation.config.psd1` を読み込み、検証し、パス解決後の hashtable を返します。

処理順序:

```text
1. 指定パスにファイルが存在するか確認する
2. Import-PowerShellDataFile で読み込む
3. Assert-FoundationConfig で構造を確認する
4. Resolve-FoundationConfigPaths でPath/Directory系の値を解決する
5. 解決済みconfigを返す
```

## 入力

| 引数 | 意味 |
|---|---|
| `Path` | configファイルのパス |
| `RootPath` | `main` フォルダのパス |

## 出力

解決済みの `hashtable` を返します。

```text
Config
  Common
  Jobs
```

## 失敗条件

```text
- Path にファイルが存在しない
- psd1 の構文が壊れている
- Common が存在しない
- Jobs が存在しない
- Common または Jobs が hashtable ではない
```

---

## 5. `Assert-FoundationConfig`

## 何をするか

configファイルの最上位構造だけを検証します。

必須キー:

```text
Common
Jobs
```

どちらも `hashtable` である必要があります。

## なぜこの程度の検証なのか

この関数は、全ジョブの設定項目を固定リストで検証しません。  
理由は、ジョブが増えるたびに `Config.ps1` を変更しない設計にしているためです。

例えば、新しい `CustomJob` を追加しても、`Config.ps1` はそのジョブ名を知らなくてよいです。

```text
Config.ps1 が知ること:
  Common と Jobs がある

各Feature moduleが知ること:
  自分の JobSettings にどのキーが必要か
```

---

## 6. `Get-FoundationJobConfig`

## 何をするか

`Config.Jobs[$JobName]` を取得します。

例:

```text
JobName = ScanTargetSync
  ↓
Config.Jobs['ScanTargetSync']
  ↓
InputCsvPath, OutputDirectory, DaysThreshold など
```

## 入力

| 引数 | 意味 |
|---|---|
| `Config` | 読み込み済み設定全体 |
| `JobName` | 取得したいジョブ名 |

## 出力

指定ジョブの設定hashtableです。  
これは `New-FoundationRunContext` で `$context.JobSettings` に入ります。

## 失敗条件

```text
- Config に Jobs がない
- Jobs が hashtable ではない
- Jobs に JobName がない
- Jobs[JobName] が hashtable ではない
```

## 重要な意味

`foundation.config.psd1` では、Composite job の設定が空でも `@{}` として存在します。

```text
WeeklyScanTargetSync = @{}
```

空でも存在することが重要です。  
キー自体がないと、`Get-FoundationJobConfig` で失敗します。

---

## 7. `Expand-FoundationPath`

## 何をするか

文字列内の環境変数を展開します。

例:

```text
%USERPROFILE%\Downloads\input.csv
  ↓
C:\Users\<user>\Downloads\input.csv
```

空文字または空白だけの文字列は、そのまま返します。

## なぜ必要か

利用者のホームディレクトリなど、環境によって異なるパスを設定ファイルに書けるようにするためです。

---

## 8. `Resolve-FoundationConfigPaths`

## 何をするか

config全体のパス設定を、絶対パスに変換します。

この関数では、まず `RootPath` を解決し、その親を `projectRoot` として使います。

```text
RootPath    = ...\main
projectRoot = ...\
```

そのため、次の相対パス:

```text
weekly\Downloads
```

は、`main` の下ではなく、プロジェクトルートの下に解決されます。

```text
<project-root>\weekly\Downloads
```

## 対象セクション

```text
Common
Jobs.<各JobName>
```

`Common` と各ジョブ設定の中を走査します。

---

## 9. `Resolve-FoundationHashtablePaths`

## 何をするか

hashtableの中を再帰的に見て、キー名が次の条件に一致する値をパスとして処理します。

```text
キー名が *Path で終わる
キー名が *Directory で終わる
```

例:

```text
InputCsvPath
OutputDirectory
TempDirectory
DownloadDirectory
TargetDirectory
RunRootDirectory
```

処理ルール:

```text
1. 値がhashtableなら再帰的に処理する
2. キー名が *Path または *Directory なら環境変数を展開する
3. 絶対パスならそのまま使う
4. 相対パスなら BaseDirectory と Join-Path する
```

## 副作用

この関数は、hashtableをその場で書き換えます。

```text
変更前:
  OutputDirectory = weekly\Downloads

変更後:
  OutputDirectory = <project-root>\weekly\Downloads
```

戻り値を新しく作るのではなく、渡された `$Table` の中身を変更します。

---

## 10. PowerShell文法上のポイント

## `Import-PowerShellDataFile`

`.psd1` を安全に読み込むためのcmdletです。  
読み込み結果はhashtableです。

## `$Config.Jobs.ContainsKey($JobName)`

hashtableに指定キーが存在するかを調べます。

```text
Config.Jobs.ContainsKey('InstalledAppExport')
```

がtrueなら、`Config.Jobs['InstalledAppExport']` を取得できます。

## 再帰処理

`Resolve-FoundationHashtablePaths` は、自分自身を呼びます。

```text
hashtableの中にhashtableがある
  ↓
同じ関数で内側も処理する
```

これにより、`Common.Logging.Directory` のようなネストした値も処理できます。

---

## 11. 変更時の注意

```text
- パス解決対象はキー名で決まる
- Path / Directory で終わるキー名を増やすと、自動的に絶対パス化される
- Path / Directory で終わらないパス設定は、自動解決されない
- Resolve-FoundationHashtablePaths は入力hashtableを書き換える
- Common / Jobs 以外の最上位セクションを追加しても、現在はパス解決対象にならない
```

例えば、次のような設定を追加しても、自動でパス解決されません。

```text
Reports = @{
  OutputDirectory = 'reports'
}
```

理由は、`Resolve-FoundationConfigPaths` が `Common` と `Jobs` だけを走査しているためです。

---

## 12. このファイルの設計境界を守るテスト

`Foundation.Config.Tests.ps1` で確認されていること:

```text
- Common と Jobs が必須
- Common と Jobs はhashtableである
- 固定ジョブセットは要求しない
- 任意のJobNameの設定を取得できる
- 存在しないJobNameはエラー
- Job設定がhashtableでなければエラー
```

このテストにより、`Config.ps1` が特定ジョブ名に依存しない設計が守られます。

---

## 13. 本ドキュメント内容の要点

```text
- Config.ps1 は foundation.config.psd1 の読み込みとパス解決を担当する
- Common と Jobs が必須である
- JobSettings は Config.Jobs[JobName] から取得される
- *Path / *Directory のキーは環境変数展開と絶対パス化の対象である
- Config.ps1 は ModulePath / CommandName を扱わない
- Config.ps1 は特定のジョブ名に依存しない
```
