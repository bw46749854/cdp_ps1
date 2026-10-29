# ScanTargetSync internal/Workflow.CsvPlan.ps1

## この文書の位置づけ

この文書は `main/modules/ScanTargetSync/internal/Workflow.CsvPlan.ps1` の個別ファイルドキュメントです。
CSV入力からUI同期Planを作るWorkflow前段の処理順序を説明します。

## このファイルを変更する典型ケース

- 処理順序、分岐、リトライ、失敗時の継続方針が変わった場合
- Policy判定結果と依存portのつなぎ方が変わった場合
- Workflowが集約する結果や後続処理への渡し方が変わった場合


## このファイルの責務

`Workflow.CsvPlan.ps1` は、CSVを読み、Policy判定を呼び、UI同期用Planを組み立てます。
Policyそのものは `Rules.ps1` / `Reconciliation.ps1` に置き、このファイルは順序と停止判断を管理します。

## 関数ごとの役割

| 関数 | 役割 |
|---|---|
| `Write-ScanTargetSyncWorkflowStartLog` | 入力CSV、出力先、ルール説明などの開始ログを出す |
| `Import-ScanTargetSyncCsvPlan` | 入力CSVを読み、CSV契約を検証し、Policy抽出を行う |
| `Resolve-ScanTargetSyncSyncPlan` | endpoint重複を反映し、SyncRowsを作る |
| `Assert-ScanTargetSyncCsvPlanOrStop` | 同期対象がない場合やCSVエラーのみの場合の停止判断を行う |
| `Write-ScanTargetSyncCsvSummary` | CSV総数、ON/OFF対象、CSVエラー件数をログ出力する |
| `New-ScanTargetSyncSyncIndex` | UI走査中に高速参照するendpoint indexを作る |

## Planの概念構造

```text
Plan
  CsvRows
  OnRows
  OffRows
  CsvErrorRows
  SyncRows
```

`SyncRows` は、UI同期する必要があるendpoint単位の指示です。
`CsvErrorRows` は、UIへ進む前にCSVデータエラーとして出力対象になります。

## SyncIndexの意味

`New-ScanTargetSyncSyncIndex` は、UI走査中にendpointを高速に照合するための索引を作ります。
概念上、次を持ちます。

```text
SyncEndpointSet
SyncRowByEndpoint
```

UIで見つかったendpointが同期対象かどうか、また同期対象の詳細が何かを、毎回配列検索しないための構造です。

## ここに書かないこと

- 日付文字列の細かいparse規則
- ON/OFF判定式そのもの
- DOM操作
- UI全件走査のループ
- 結果CSVの物理出力

## 変更時に見るテスト

- `main/tests/ScanTargetSync.Workflow.Tests.ps1`
- `main/tests/ScanTargetSync.Workflow.Normal.Tests.ps1`
- `main/tests/ScanTargetSync.Rules.Tests.ps1`
- `main/tests/ScanTargetSync.Reconciliation.Tests.ps1`

## 更新条件

CSV読み込みからPlan作成までの順序、Plan構造、SyncIndex構造、CSVエラー時の停止判断が変わった場合に更新します。
