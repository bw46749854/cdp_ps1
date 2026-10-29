# main/modules/ScanTargetSync/ScanTargetSync.psm1

## 1. このファイルを一言でいうと

`ScanTargetSync` モジュールを組み立てるファイルです。`internal` 配下の責務別ファイルを順番にdot-sourceし、外部から呼べる入口として `Invoke-ScanTargetSyncJob` だけを公開します。

## このファイルを変更する典型ケース

- 公開関数、Job入口、内部ファイル読み込み順が変わった場合
- モジュール外へ公開する関数の範囲が変わった場合
- Runner / Workflow / Dependencies への接続方法が変わった場合


## 2. このファイルが担当する範囲

- `Foundation.psm1` の読み込み。
- `internal/*.ps1` の読み込み順序の定義。
- `Invoke-ScanTargetSyncJob` の公開。
- internal関数を外部公開しない境界作り。

## 3. このファイルが担当しない範囲

- CSV判定ロジック。
- ブラウザ操作。
- DOM helperメソッドの詳細。
- エラーCSVや失敗CSVの出力処理。

## 4. 読み込み順序の意味

このファイルでは、先に低めの部品を読み込み、最後に入口側を読み込みます。

```text
CsvInput / Rules / Output / Reconciliation
  ↓
DomOperations / DomAdapter / Dependencies
  ↓
Workflow.*
  ↓
Workflow.ps1
  ↓
Runner.ps1
```

PowerShellでは、dot-sourceされた関数は同じモジュールスコープに定義されます。そのため、後から読み込まれた `Runner.ps1` は、先に読み込まれた `Resolve-ScanTargetSyncWorkflowDependencies` や `Invoke-ScanTargetSyncSyncWorkflow` を呼び出せます。

## 5. PowerShell構文ポイント

`. $path` はdot-sourceです。通常のスクリプト実行とは違い、そのファイル内の関数定義を現在のスコープに読み込みます。

`Export-ModuleMember -Function @('Invoke-ScanTargetSyncJob')` により、モジュール外から見える関数は `Invoke-ScanTargetSyncJob` だけになります。`internal` 関数はテストやモジュール内部から使えますが、ジョブ実行入口としては公開されません。

## 6. 変更時の注意

読み込み順序を変えると、後続ファイルで参照している関数が未定義になる可能性があります。特に `Workflow.Orchestration.ps1` は多数の `Workflow.*` 関数を呼ぶため、`Workflow.Orchestration.ps1` より前に関連ファイルを読み込む必要があります。
