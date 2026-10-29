# modules/DeviceListExport/DeviceListExport.psm1

## 1. このファイルを一言でいうと

`DeviceListExport` モジュールを組み立てる入口ファイルである。

PowerShellでは、`.psm1` がモジュール本体として読み込まれる。
このファイルは、`internal` 配下に分割された複数の `.ps1` ファイルを同じモジュールスコープに読み込み、外部から呼べる関数として `Invoke-DeviceListExportJob` だけを公開する。

## このファイルを変更する典型ケース

- 公開関数、Job入口、内部ファイル読み込み順が変わった場合
- モジュール外へ公開する関数の範囲が変わった場合
- Runner / Workflow / Dependencies への接続方法が変わった場合


## 2. このファイルが担当する範囲

```text
- FoundationモジュールをImport-Moduleする
- DeviceListExportのinternalファイルを決められた順序でdot-sourceする
- 外部公開する関数をExport-ModuleMemberで限定する
```

## 3. このファイルが担当しない範囲

```text
- CSVエクスポートの業務手順
- DOM操作の詳細
- ダウンロード待ち処理
- 結果ログ出力の内容
```

これらはすべて `internal/*.ps1` 側に分かれている。

## 4. 読み込み順序

```text
DeviceListExport.psm1
  ├─ Import-Module modules\Foundation\Foundation.psm1
  ├─ dot-source internal\DomOperations.ps1
  ├─ dot-source internal\DomAdapter.ps1
  ├─ dot-source internal\Download.ps1
  ├─ dot-source internal\Output.ps1
  ├─ dot-source internal\Dependencies.ps1
  ├─ dot-source internal\Workflow.ps1
  ├─ dot-source internal\Runner.ps1
  └─ Export-ModuleMember Invoke-DeviceListExportJob
```

## 5. なぜ順序が重要か

PowerShellでは、関数定義は読み込まれた後に使える。
そのため、後続ファイルから使われる関数は先にdot-sourceされる必要がある。

このモジュールでは、主に次の関係がある。

```text
Runner.ps1
  ↓ uses
Workflow.ps1
  ↓ uses
Dependencies.ps1
  ↓ resolves commands in
DomAdapter.ps1 / Download.ps1 / Output.ps1
  ↓ uses
DomOperations.ps1 / Foundation
```

`Runner.ps1` は最後に読み込まれる。
これは、外部公開される `Invoke-DeviceListExportJob` が他の内部関数を呼ぶためである。

## 6. dot-sourceとは何か

PowerShellの `. $path` は dot-source と呼ばれる。
普通に `.ps1` を実行すると、そのファイル内の関数や変数は基本的に別スコープで扱われる。
しかし dot-source すると、読み込まれた関数が現在のスコープに定義される。

このファイルでは、`internal/*.ps1` の関数を `DeviceListExport` モジュールスコープに定義するために dot-source している。

## 7. Export-ModuleMemberの意味

`Export-ModuleMember` は、モジュールの外から呼べる関数を制限する。

このファイルで公開しているのは次だけである。

```text
Invoke-DeviceListExportJob
```

そのため、外部からは基本的に次のように呼ばれる。

```text
Invoke-DeviceListExportJob -Context $context
```

一方で、`Invoke-DeviceListExportWorkflow` や `Rename-DeviceListExportDownloadedCsv` などは内部関数として扱う。
テストでは `InModuleScope DeviceListExport` を使うことで内部関数を検証できるが、プロダクト実行時の公開APIではない。

## 8. 変更時の注意

### internalファイルの順序を変える場合

順序を変えると、まだ定義されていない関数を参照して失敗する可能性がある。
特に `Runner.ps1` を前に移動する意味は薄い。

### Export-ModuleMemberを増やす場合

外部公開関数を増やすと、モジュールの外部契約が増える。
外部契約が増えると、後から関数名や引数を変えにくくなる。

原則として、DeviceListExportの外部入口は `Invoke-DeviceListExportJob` のみに保つ。

### FoundationモジュールのImportを削除する場合

DeviceListExport内部では、`Register-FoundationDomBundle`、`Write-FoundationLog`、`Assert-FoundationDomHelperContract` などの共通関数を使う。
FoundationモジュールをImportしないと、これらが見つからず停止する。

## 9. 本ドキュメント内容の要点

```text
- .psm1はDeviceListExportモジュールの組み立て役である
- internalファイルはdot-sourceで同一モジュールスコープに読み込まれる
- 外部公開関数はInvoke-DeviceListExportJobだけである
- 読み込み順序には依存関係上の意味がある
```
