# ScanTargetSync internal/Workflow.Export.ps1

## この文書の位置づけ

この文書は `main/modules/ScanTargetSync/internal/Workflow.Export.ps1` の個別ファイルドキュメントです。
Workflow終了時にCSVデータエラーCSVとチェック処理失敗CSVを出力する順序を説明します。

## このファイルを変更する典型ケース

- 処理順序、分岐、リトライ、失敗時の継続方針が変わった場合
- Policy判定結果と依存portのつなぎ方が変わった場合
- Workflowが集約する結果や後続処理への渡し方が変わった場合


## このファイルの責務

このファイルは、出力処理の順序とState更新を担当します。
CSVの物理書き出しは `Output.ps1` の関数を呼びます。

## 関数ごとの役割

| 関数 | 役割 |
|---|---|
| `Export-ScanTargetSyncEndCsvFiles` | CSVデータエラーCSVとチェック処理失敗CSVを出力する |
| `Complete-ScanTargetSyncEndCsvExport` | 出力完了後、`State.EndCsvExportCompleted` を更新する |

## EndCsvExportCompletedの意味

異常終了時にもCSV出力を試みるため、すでに終了CSV出力済みかどうかをStateで保持します。
これにより、致命的エラー時に同じ終了CSVを二重出力することを避けます。

## 変更時に見るテスト

- `main/tests/ScanTargetSync.Output.Tests.ps1`
- `main/tests/ScanTargetSync.Workflow.Tests.ps1`

## 更新条件

終了時に出力するCSVの種類、出力順序、`EndCsvExportCompleted` の更新方針が変わった場合に更新します。
