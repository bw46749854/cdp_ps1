# ScanTargetSync internal/Workflow.EndpointSync.ps1

## この文書の位置づけ

この文書は `main/modules/ScanTargetSync/internal/Workflow.EndpointSync.ps1` の個別ファイルドキュメントです。
UIで見えている同期対象endpointについて、チェック状態を目的状態へ揃える処理を説明します。

## このファイルを変更する典型ケース

- 処理順序、分岐、リトライ、失敗時の継続方針が変わった場合
- Policy判定結果と依存portのつなぎ方が変わった場合
- Workflowが集約する結果や後続処理への渡し方が変わった場合


## このファイルの責務

このファイルは、endpoint単位の同期実行と成功/失敗の記録を担当します。
DOM操作そのものは `EndpointAction.SetDesiredState` callbackを通します。

## 処理の流れ

```text
Invoke-ScanTargetSyncVisibleEndpointSyncBatch
  ↓
visibleSyncEndpoints を順に処理
  ↓
Invoke-ScanTargetSyncSyncForEndpoint
  ↓
SetDesiredState(endpoint, desiredChecked)
  ↓
成功なら SuccessRows / ProcessedEndpointMap に記録
失敗なら FailureRows に変換
致命的エラーなら throw
```

## 致命的エラー判定

DOM操作失敗時、`EndpointAction.TestFoundationFatalError` で致命的な自動化エラーかどうかを判定します。
致命的であれば処理を続けず、上位Workflowへ例外を送ります。

ここでの目的は、画面やCDPセッションが壊れた状態で後続endpointを操作し続ける事故を防ぐことです。

## ここに書かないこと

- DOM helper method名
- CSV行のPolicy判定
- UI全件走査の終了条件
- 結果CSVの物理出力

## 変更時に見るテスト

- `main/tests/ScanTargetSync.Workflow.Tests.ps1`
- `main/tests/ScanTargetSync.Workflow.Normal.Tests.ps1`
- `main/tests/ScanTargetSync.DomOperations.Tests.ps1`

## 更新条件

endpoint同期の成功/失敗記録、致命的エラー判定、`ProcessedEndpointMap` / `SuccessRows` の更新方針が変わった場合に更新します。
