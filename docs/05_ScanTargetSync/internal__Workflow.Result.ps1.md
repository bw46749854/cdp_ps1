# ScanTargetSync internal/Workflow.Result.ps1

## この文書の位置づけ

この文書は `main/modules/ScanTargetSync/internal/Workflow.Result.ps1` の個別ファイルドキュメントです。
UI走査とチェック同期の結果を検証し、異常を失敗行へ変換するWorkflow結果処理を説明します。

## このファイルを変更する典型ケース

- 処理順序、分岐、リトライ、失敗時の継続方針が変わった場合
- Policy判定結果と依存portのつなぎ方が変わった場合
- Workflowが集約する結果や後続処理への渡し方が変わった場合


## 重要な位置づけ

`Workflow.Result.ps1` は、Policy層ではなくWorkflow上の結果検証・失敗行追加・サマリ出力を担当します。
Policy層ではなく、Workflowの結果集約・結果検証・失敗行追加・サマリ出力を担当します。

Policy判定そのものは `Rules.ps1` / `Reconciliation.ps1` に置きます。

## ここで検出する失敗

| 関数 | 検出内容 |
|---|---|
| `Add-ScanTargetSyncScanLoopLimitFailure` | 最大走査ループ数に到達した |
| `Add-ScanTargetSyncUiBadRowFailures` | endpointまたはdata-idが空のUI行があった |
| `Add-ScanTargetSyncUiEndpointConflictFailures` | 同じendpointが複数data-idで出た |
| `Add-ScanTargetSyncUiSeenCountMismatchFailure` | UIで確認できたendpoint件数とUI一覧件数が一致しない |
| `Add-ScanTargetSyncCsvMissingInUiFailures` | CSVにあるendpointがUI一覧で見つからない |
| `Add-ScanTargetSyncUiExtraEndpointFailures` | UI一覧に存在するendpointがCSVに存在しない |
| `Add-ScanTargetSyncUnprocessedSyncFailures` | 同期対象なのに処理できなかった |
| `Add-ScanTargetSyncProcessedCountMismatchFailure` | 処理済み件数と同期対象件数が一致しない |
| `Add-ScanTargetSyncSuccessValidationFailures` | 成功扱い件数や整合後状態が不自然 |

## 結果検証の流れ

```text
Add-ScanTargetSyncUiScanValidationFailures
  ↓
UI走査の異常をFailureRowsへ追加
  ↓
Get-ScanTargetSyncSuccessBreakdown
  ↓
成功結果をON/OFF/変更済み/変更不要へ分類
  ↓
Add-ScanTargetSyncSuccessValidationFailures
  ↓
Write-ScanTargetSyncProcessingSummary
```

## SuccessBreakdownの意味

`Get-ScanTargetSyncSuccessBreakdown` は、DOM操作成功行を次の観点で分類します。

```text
OnSuccessRows
OffSuccessRows
MisalignedSuccessRows
ChangedRows
AlreadyAlignedRows
```

この分類は、人間向けの処理サマリと、成功扱いの内部整合確認に使います。

## ここに書かないこと

- CSVセルのparse規則
- ON/OFF対象の業務判定
- DOM helper method名
- 出力CSVの物理書き込み

## 変更時に見るテスト

- `main/tests/ScanTargetSync.Workflow.Tests.ps1`
- `main/tests/ScanTargetSync.Workflow.Normal.Tests.ps1`
- `main/tests/ScanTargetSync.Output.Tests.ps1`

## 更新条件

UI走査後検証、成功行分類、失敗行追加条件、処理サマリ内容が変わった場合に更新します。
