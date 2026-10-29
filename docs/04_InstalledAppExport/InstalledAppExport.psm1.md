# modules/InstalledAppExport/InstalledAppExport.psm1

## 1. このファイルを一言でいうと

`InstalledAppExport` モジュールをPowerShellに読み込ませるための組み立てファイルです。

`internal` 配下に分かれている複数の `.ps1` ファイルを、1つの `InstalledAppExport` モジュールとして読み込み、外部から呼び出してよい入口関数だけを公開します。

## このファイルを変更する典型ケース

- 公開関数、Job入口、内部ファイル読み込み順が変わった場合
- モジュール外へ公開する関数の範囲が変わった場合
- Runner / Workflow / Dependencies への接続方法が変わった場合


## 2. このファイルが担当する範囲

このファイルの担当は、次の3つです。

1. 共通基盤である `Foundation.psm1` を読み込む
2. `InstalledAppExport/internal/*.ps1` を決められた順番で dot-source する
3. 外部公開関数として `Invoke-InstalledAppExportJob` だけを export する

## 3. このファイルが担当しない範囲

このファイルは、端末一覧を操作しません。
CSVをダウンロードしません。
DOM helperを直接呼びません。

このファイルは、あくまで「モジュールの組み立て」です。
実処理は `internal` 配下の各ファイルにあります。

## 4. 読み込み順序

```text
InstalledAppExport.psm1
  ├─ Import-Module Foundation.psm1
  ├─ dot-source internal\Models.ps1
  ├─ dot-source internal\DomOperations.ps1
  ├─ dot-source internal\DomAdapter.ps1
  ├─ dot-source internal\Download.ps1
  ├─ dot-source internal\Output.ps1
  ├─ dot-source internal\RowAction.ps1
  ├─ dot-source internal\Dependencies.ps1
  ├─ dot-source internal\Workflow.ps1
  ├─ dot-source internal\Runner.ps1
  └─ Export-ModuleMember Invoke-InstalledAppExportJob
```

## 5. dot-sourceとは何か

PowerShellで次のように書くと、指定した `.ps1` ファイルを現在のスコープに読み込みます。

```powershell
. $path
```

これを dot-source と呼びます。

通常のスクリプト実行と違い、dot-source されたファイル内の関数は、現在のモジュールスコープに定義されます。
そのため、`Models.ps1` にある `New-InstalledAppExportFailure` を、`Workflow.ps1` や `Dependencies.ps1` から呼べます。

## 6. なぜこの順番なのか

順番には意味があります。

| 順番 | ファイル | 先に読む理由 |
|---|---|---|
| 1 | `Models.ps1` | 結果データや行キーを作る基本関数 |
| 2 | `DomOperations.ps1` | DOM operation名の対応表 |
| 3 | `DomAdapter.ps1` | DomOperationsを業務名の関数で包む |
| 4 | `Download.ps1` | RowActionから使うダウンロード待ち処理 |
| 5 | `Output.ps1` | Runnerから使う失敗CSV出力 |
| 6 | `RowAction.ps1` | 1行分のCSV取得処理 |
| 7 | `Dependencies.ps1` | Workflowが使う依存を組み立てる |
| 8 | `Workflow.ps1` | 一覧全体の走査処理 |
| 9 | `Runner.ps1` | 外部公開されるジョブ入口 |

PowerShellでは、関数定義の時点で呼び出し先関数が必ず存在している必要はありません。
ただし、このプロジェクトでは読みやすさと安全性のため、下位部品から上位入口へ向かう順で読み込んでいます。

## 7. Export-ModuleMember の意味

最後に公開されているのは次だけです。

```text
Invoke-InstalledAppExportJob
```

これは、Foundationから呼ばれるジョブ入口です。

`New-InstalledAppExportFailure` や `Invoke-InstalledAppExportCsvWorkflow` などの内部関数は、モジュール内部では使えますが、外部公開APIではありません。

## 8. 変更時の注意

### internalファイルを追加する場合

新しい `.ps1` ファイルを追加しても、この `InstalledAppExport.psm1` に dot-source しなければ読み込まれません。

### 読み込み順を変える場合

読み込み順を変えると、Pesterテストや `Get-Command` による関数取得の前提が崩れる可能性があります。
特に `Dependencies.ps1` は `RowAction.ps1` や `Models.ps1` の関数を `Get-Command` で取得します。
そのため、依存される側を後ろに回す変更は避けます。

### Export関数を増やす場合

外部公開関数を増やすと、モジュール境界が広がります。
通常、外から呼ぶべきなのは `Invoke-InstalledAppExportJob` だけです。
内部関数を公開したくなった場合は、その関数が本当に外部APIなのかを先に確認します。

## 9. 本ドキュメント内容の要点

- `InstalledAppExport.psm1` は実処理ではなく、モジュールの組み立てである
- `internal/*.ps1` は dot-source により同じモジュールスコープに読み込まれる
- 外部から呼ぶ入口は `Invoke-InstalledAppExportJob` だけである
- internalファイルの追加・削除・順序変更は、モジュール全体に影響する
