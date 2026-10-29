# ScanTargetSync internal/Workflow.ps1

## この文書の位置づけ

この文書は `main/modules/ScanTargetSync/internal/Workflow.ps1` の個別ファイルドキュメントです。
`ScanTargetSync` の最上位Workflowとして、正常系と致命的エラー時の大枠を説明します。

## このファイルを変更する典型ケース

- 処理順序、分岐、リトライ、失敗時の継続方針が変わった場合
- Policy判定結果と依存portのつなぎ方が変わった場合
- Workflowが集約する結果や後続処理への渡し方が変わった場合


## このファイルの責務

`Invoke-ScanTargetSyncSyncWorkflow` は、Workflow全体の入口です。
依存解決、State作成、正常系の大きな順序、致命的エラー時の出力保証を制御します。

## 処理の流れ

```text
Invoke-ScanTargetSyncSyncWorkflow
  ↓
Resolve-ScanTargetSyncWorkflowDependencies
  ↓
New-ScanTargetSyncWorkflowState
  ↓
Initialize-ScanTargetSyncWorkflow
  ↓
New-ScanTargetSyncValidatedPlan
  ↓
同期対象なしなら終了CSVを出して終了
  ↓
Invoke-ScanTargetSyncScanAndSync
  ↓
Complete-ScanTargetSyncWorkflow
  ↓
Assert-ScanTargetSyncWorkflowSucceeded
```

例外発生時は、`Export-ScanTargetSyncFatalResultIfNeeded` により、可能な範囲で失敗CSVを出力してから元の例外を再送出します。

## ここに書かないこと

- CSV parse規則
- DOM helper method名
- endpoint単位の同期詳細
- 出力CSVの低レベル書き込み

## 変更時に見るテスト

- `main/tests/ScanTargetSync.Workflow.Tests.ps1`
- `main/tests/ScanTargetSync.Workflow.Normal.Tests.ps1`
- `main/tests/Architecture.Tests.ps1`

## 更新条件

Workflow全体の大きな順序、致命的エラー時の保険出力、最終成功判定が変わった場合に更新します。
