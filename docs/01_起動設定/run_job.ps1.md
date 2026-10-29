# main/run_job.ps1

## 1. このファイルを一言でいうと

このファイルは、プロダクト全体のPowerShell実行入口です。

役割は、利用者や `.bat` から渡された `JobName` を受け取り、Foundationの `Invoke-FoundationEntrypoint` に渡すことです。

このファイルは、InstalledAppExport、ScanTargetSync、LastMonthInstallExtractなどの業務処理を直接実行しません。  
どのFeature moduleを読むかも、このファイル内には書かれていません。

---

## このファイルを変更する典型ケース

- 起動引数、config path、job registry pathの扱いが変わった場合
- Foundation entrypointへの渡し方が変わった場合
- batファイルや運用手順からの呼び出し方が変わった場合


## 2. このファイルが担当する範囲

このファイルが担当すること:

```text
- コマンドライン引数を受け取る
- main フォルダの場所を特定する
- config path の省略時デフォルトを決める
- Foundation.psm1 の存在確認をする
- Foundation.psm1 を Import-Module する
- Invoke-FoundationEntrypoint を呼ぶ
```

このファイルが担当しないこと:

```text
- どのジョブ名が有効かを判定する
- InstalledAppExport などのFeature moduleを直接読み込む
- ブラウザを開く
- CSVを読む
- CSVを出力する
- DOM JavaScriptを登録する
- 業務ルールを判定する
```

このファイルは薄い入口です。  
設計上、薄い入口ファイルは無理に分割しません。

---

## 3. 実行時の流れ

```text
run_job.ps1
  ├─ param で JobName / ConfigPath / JobRegistryPath を受け取る
  ├─ $ErrorActionPreference = "Stop" を設定する
  ├─ $ScriptDirectory を決定する
  ├─ ConfigPath が空なら main\config\foundation.config.psd1 を使う
  ├─ modules\Foundation\Foundation.psm1 のパスを作る
  ├─ Foundation.psm1 が存在しなければ throw
  ├─ Import-Module Foundation.psm1
  └─ Invoke-FoundationEntrypoint を呼ぶ
       ├─ RootPath        = $ScriptDirectory
       ├─ ConfigPath      = $ConfigPath
       ├─ JobName         = $JobName
       └─ JobRegistryPath = $JobRegistryPath
```

このファイルの終点は `Invoke-FoundationEntrypoint` です。  
その先の処理は `Foundation/internal/Bootstrap.ps1` 側です。

---

## 4. 引数の意味

| 引数 | 必須 | 意味 |
|---|---:|---|
| `JobName` | 必須 | 実行するジョブ名。例: `InstalledAppExport`, `ScanTargetSync`, `LastMonthInstallExtract` |
| `ConfigPath` | 任意 | 実行時設定ファイル。空なら `main\config\foundation.config.psd1` |
| `JobRegistryPath` | 任意 | ジョブ実装定義ファイル。空なら後続処理で `main\config\foundation.jobs.psd1` |

`JobName` はこのファイルで直接関数名に変換されません。  
後続の `JobRegistry.ps1` が `foundation.jobs.psd1` を使って変換します。
root の `.bat` が実際に渡す `JobName` は `docs/01_起動設定/bat起動入口とJobName.md` を参照してください。  
現時点の `.bat` は単体Jobではなく、週次・月次の Composite Job を起動します。

---

## 5. `$ScriptDirectory` の決め方

このファイルでは、次の優先順位で `$ScriptDirectory` を決めます。

```text
1. $PSScriptRoot が空でなければ、それを使う
2. $MyInvocation.MyCommand.Path があれば、その親フォルダを使う
3. どちらも使えなければ、現在のカレントディレクトリを使う
```

通常の `powershell.exe -File main\run_job.ps1` では、`$PSScriptRoot` が `main` フォルダになります。

`$PSScriptRoot` は「実行中のスクリプトファイルが置かれているフォルダ」を表すPowerShellの自動変数です。  
これを使うことで、利用者がどのカレントディレクトリから実行しても、`main\config` や `main\modules` を安定して参照できます。

---

## 6. PowerShell文法上のポイント

## `param(...)`

ファイル先頭の `param(...)` は、この `.ps1` ファイルが受け取る引数を定義します。

```powershell
param(
    [Parameter(Mandatory)][string]$JobName,
    [string]$ConfigPath = "",
    [string]$JobRegistryPath = ""
)
```

`[Parameter(Mandatory)]` が付いた `$JobName` は必須です。  
`ConfigPath` と `JobRegistryPath` は省略できます。

## `$ErrorActionPreference = "Stop"`

PowerShellでは、コマンドによってはエラーが発生しても処理が継続することがあります。  
この設定を `Stop` にすることで、エラー時に例外として止まりやすくしています。

この入口で `Stop` にしておくと、設定ファイルが見つからない、モジュールが読めない、などの起動失敗を曖昧に継続しません。

## バッククォートによる改行

最後の呼び出しでは、バッククォートを使って1つのコマンドを複数行に分けています。

```powershell
Invoke-FoundationEntrypoint `
    -RootPath $ScriptDirectory `
    -ConfigPath $ConfigPath `
    -JobName $JobName `
    -JobRegistryPath $JobRegistryPath
```

これは読みやすさのための改行です。  
1つの `Invoke-FoundationEntrypoint` 呼び出しとして実行されます。

---

## 7. このファイルで発生する可能性がある失敗

| 場所 | 失敗条件 | エラーの意味 |
|---|---|---|
| 引数受け取り | `JobName` を渡していない | 何のジョブを実行するか分からない |
| Foundation module存在確認 | `modules\Foundation\Foundation.psm1` が存在しない | 共通基盤が壊れている、または配置が違う |
| Import-Module | Foundation module内の読み込みに失敗 | internalファイル欠落、構文エラー、依存関数欠落など |
| Invoke-FoundationEntrypoint | 設定、ジョブ定義、Feature module側で失敗 | 入口より先の問題 |

このファイルで検出できるのは、主にFoundationに入る前の配置不備です。

---

## 8. このファイルを変更するときの判断基準

## 変更してよい例

```text
- ConfigPath のデフォルトファイル名を変更する
- Foundation.psm1 の配置ルールを変更する
- 引数を追加して Bootstrap に渡す
```

ただし、引数を追加する場合は `Invoke-FoundationEntrypoint` 側にも対応が必要です。

## 変更してはいけない方向

```text
- JobNameごとの if/switch を run_job.ps1 に書く
- Invoke-InstalledAppExportJob などのFeature jobを直接呼ぶ
- modules\InstalledAppExport\InstalledAppExport.psm1 をここでImport-Moduleする
- DOMやCSV処理をここに書く
- 設定ファイルの中身をここで詳しく検証する
```

このファイルがFeature jobを知り始めると、`run_job.ps1` が汎用入口ではなくなります。  
現在の設計では、ジョブ追加時に `run_job.ps1` を変更しないことが重要です。

---

## 9. このファイルの設計境界を守るテスト

`Foundation.Entrypoint.Tests.ps1` では、`run_job.ps1` が汎用入口であることを確認しています。

確認されている観点:

```text
- JobName を必須引数として持つ
- JobRegistryPath を受け取れる
- run_job.ps1 に Invoke-InstalledAppExportJob などの個別ジョブ名が直接書かれていない
- run_job.ps1 に modules\InstalledAppExport などの個別モジュールパスが直接書かれていない
```

このテストがあるため、`run_job.ps1` に個別ジョブ分岐を足す変更は設計違反として検出されます。

---

## 10. 本ドキュメント内容の要点

```text
- run_job.ps1 は薄い入口である
- JobName を受け取り、Foundationに渡すだけである
- どのジョブがどのモジュールにあるかは foundation.jobs.psd1 が決める
- 実行時設定は foundation.config.psd1 が決める
- run_job.ps1 にFeature module固有の処理を書いてはいけない
```
