# ScanTargetSync internal/Workflow.State.ps1

## この文書の位置づけ

この文書は `main/modules/ScanTargetSync/internal/Workflow.State.ps1` の個別ファイルドキュメントです。
ScanTargetSync Workflow全体で共有する実行状態と、失敗行へのtimestamp補完を説明します。

## このファイルを変更する典型ケース

- 処理順序、分岐、リトライ、失敗時の継続方針が変わった場合
- Policy判定結果と依存portのつなぎ方が変わった場合
- Workflowが集約する結果や後続処理への渡し方が変わった場合


## Stateの構造

```text
FailureRows           : チェック処理失敗CSVに出す行
CsvErrorRowsForExport : CSVデータエラーCSVに出す行
EndCsvExportCompleted : 終了CSV出力済みか
Timing                : TimestampText callbackを含むport
```

## 関数ごとの役割

| 関数 | 役割 |
|---|---|
| `New-ScanTargetSyncWorkflowState` | Workflow開始時に空の状態を作る |
| `Get-ScanTargetSyncWorkflowTimestampText` | Timing portからtimestamp文字列を得る |
| `Add-ScanTargetSyncFailureRow` | FailureRowへtimestampを補完してStateへ追加する |

## Timing portを持つ理由

失敗行のtimestampはテストで固定したい値です。
Workflow内で直接 `Get-Date` を呼ぶとテストが不安定になるため、`Timing.TimestampText` callbackを通します。

## 変更時に見るテスト

- `main/tests/ScanTargetSync.Workflow.Tests.ps1`
- `main/tests/ScanTargetSync.Dependencies.Tests.ps1`
- `main/tests/Architecture.Tests.ps1`

## 更新条件

State構造、timestamp補完、失敗行追加方針が変わった場合に更新します。
