# ScanTargetSync internal/Workflow.UiScanState.ps1

## この文書の位置づけ

この文書は `main/modules/ScanTargetSync/internal/Workflow.UiScanState.ps1` の個別ファイルドキュメントです。
UI全件走査中に蓄積する状態と、可視行から今回処理すべきendpointを抽出する処理を説明します。

## このファイルを変更する典型ケース

- 処理順序、分岐、リトライ、失敗時の継続方針が変わった場合
- Policy判定結果と依存portのつなぎ方が変わった場合
- Workflowが集約する結果や後続処理への渡し方が変わった場合


## ScanStateの構造

`New-ScanTargetSyncUiScanState` は、UI走査用の状態を作ります。

```text
ProcessedEndpointMap     : すでに同期処理したendpoint
SeenUiEndpointSet        : UI上で一度でも見たendpoint
SeenUiEndpointDataIdMap  : endpoint → 最初に見たdata-id
UiEndpointConflictMap    : 同じendpointが別data-idで出た記録
UiBadRowMap              : endpointまたはdata-idが空のUI行
SuccessRows              : 同期成功したDOM結果
SameScrollCount          : スクロール位置が変わらなかった連続回数
LoopReachedLimit         : MaxScanLoops到達で終わったか
MaxScanLoops             : 走査上限
```

`LoopReachedLimit` は初期値を `$true` にします。
これは、正常終了条件を満たして明示的に解除されない限り、「上限到達の可能性がある」状態として扱うためです。
異常系を安全側に倒す設計です。

## 可視行の処理

`Update-ScanTargetSyncUiScanStateFromVisibleRows` は、DOM helperから返された可視行を見て、次を行います。

1. endpoint または data-id が空の行を `UiBadRowMap` に記録する。
2. endpointを `SeenUiEndpointSet` に記録する。
3. endpointとdata-idの対応を `SeenUiEndpointDataIdMap` に記録する。
4. 同じendpointが別data-idで出た場合、`UiEndpointConflictMap` に記録する。
5. まだ処理していない同期対象endpointだけを、今回処理すべきendpointとして返す。

## 重複endpoint / data-id不整合の扱い

UI上で同じendpointが複数data-idに現れる場合、DOM上の行識別が不安定です。
この状態でチェック同期を続けると、意図しない行を操作する可能性があります。
そのため、即座に成功扱いにはせず、走査後の `Workflow.Result.ps1` で失敗行へ変換します。

## ここに書かないこと

- DOM helperのmethod名
- チェックボックスをクリックする処理
- CSV側のON/OFF判定
- 結果CSVの書き出し

## 変更時に見るテスト

- `main/tests/ScanTargetSync.Workflow.Tests.ps1`
- `main/tests/ScanTargetSync.Workflow.Normal.Tests.ps1`
- `main/tests/ScanTargetSync.DomOperations.Tests.ps1`

## 更新条件

ScanStateの項目、`LoopReachedLimit` の初期方針、可視行からのendpoint抽出、UI不整合の記録方法が変わった場合に更新します。
