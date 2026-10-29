# ScanTargetSync internal/Workflow.UiScan.ps1

## この文書の位置づけ

この文書は `main/modules/ScanTargetSync/internal/Workflow.UiScan.ps1` の個別ファイルドキュメントです。
画面上のデバイス一覧を上から下まで走査し、見えたendpointを必要に応じて同期するWorkflow処理を説明します。

## このファイルを変更する典型ケース

- 処理順序、分岐、リトライ、失敗時の継続方針が変わった場合
- Policy判定結果と依存portのつなぎ方が変わった場合
- Workflowが集約する結果や後続処理への渡し方が変わった場合


## このファイルの責務

`Workflow.UiScan.ps1` はUI走査の順序を持ちます。
DOM helper method名は `DomOperations.ps1`、endpoint単位の同期は `Workflow.EndpointSync.ps1`、走査状態は `Workflow.UiScanState.ps1` が担当します。

## 処理の流れ

```text
Invoke-ScanTargetSyncUiScan
  ↓
Resolve / Assert dependencies
  ↓
New-ScanTargetSyncUiScanState
  ↓
for loop < MaxScanLoops
  ↓
GetVisibleRows
  ↓
Update-ScanTargetSyncUiScanStateFromVisibleRows
  ↓
Invoke-ScanTargetSyncVisibleEndpointSyncBatch
  ↓
Test-ScanTargetSyncUiScanCompleted
  ↓
Move-ScanTargetSyncUiScanCursor
```

## 終了条件

`Test-ScanTargetSyncUiScanCompleted` は、同期対象endpointがすべて処理済みかどうかを判定します。
全同期対象が処理済みになった場合、走査は正常終了できます。

`Move-ScanTargetSyncUiScanCursor` は、スクロールで次の可視行へ進めます。
スクロールしても状況が変わらない場合は、`SameScrollCount` により進捗停止を検出します。

## MaxScanLoopsの意味

`MaxScanLoops` は、仮想スクロールやDOM状態の異常で無限ループしないための上限です。
上限に達した場合は、走査後の結果検証で失敗行へ変換されます。

## ここに書かないこと

- endpointがON対象かOFF対象かのPolicy判定
- DOM helper method名やAwait契約
- 成功/失敗CSVの物理出力

## 変更時に見るテスト

- `main/tests/ScanTargetSync.Workflow.Tests.ps1`
- `main/tests/ScanTargetSync.Workflow.Normal.Tests.ps1`
- `main/tests/ScanTargetSync.DomOperations.Tests.ps1`
- `main/tests/js/scan-target-sync.dom.behavior.test.js`

## 更新条件

UI走査順序、終了条件、スクロール進捗判定、MaxScanLoopsの扱いが変わった場合に更新します。
