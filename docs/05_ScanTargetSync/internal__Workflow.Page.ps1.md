# ScanTargetSync internal/Workflow.Page.ps1

## この文書の位置づけ

この文書は `main/modules/ScanTargetSync/internal/Workflow.Page.ps1` の個別ファイルドキュメントです。
ブラウザ上で正しいScanTargetSync対象ページを開き、操作開始前の画面契約を確認する処理を説明します。

## このファイルを変更する典型ケース

- 処理順序、分岐、リトライ、失敗時の継続方針が変わった場合
- Policy判定結果と依存portのつなぎ方が変わった場合
- Workflowが集約する結果や後続処理への渡し方が変わった場合


## このファイルの責務

`Workflow.Page.ps1` は、ページ選択と初期画面検証の順序を管理します。
DOM helperのmethod名は `DomOperations.ps1`、業務名DOM関数は `DomAdapter.ps1` が担当します。

## 主な流れ

```text
Open-ScanTargetSyncPageAndValidate
  ↓
Resolve / Assert page dependencies
  ↓
OpenPageMatchingIdentity(PageIdentityMatcher)
  ↓
RegisterAdapter
  ↓
AssertPage
  ↓
AssertDeviceList
  ↓
PrepareOperationScope
  ↓
Get device total count
  ↓
CSV件数とUI一覧件数の前提を確認
```

`Confirm-ScanTargetSyncPostSelectionContract` は、チェック状態変更後に画面契約が保たれているかを確認します。

## ここに書かないこと

- endpoint単位の同期処理
- UI全件走査ループ
- CSVのPolicy判定
- DOM helper method名

## 変更時に見るテスト

- `main/tests/ScanTargetSync.BrowserBoundary.Tests.ps1`
- `main/tests/ScanTargetSync.Workflow.Tests.ps1`
- `main/tests/ScanTargetSync.DomOperations.Tests.ps1`

## 更新条件

ページ選択条件、初期画面契約、post-selection契約、CSV件数とUI件数の前提確認が変わった場合に更新します。
