# main/modules/ScanTargetSync/internal/DomAdapter.ps1

## 1. このファイルを一言でいうと

Workflowから見える業務名の画面操作関数を提供するファイルです。実際のDOM helper呼び出しは `DomOperations.ps1` に委譲します。

## このファイルを変更する典型ケース

- Workflowから呼ぶ画面操作の業務名が変わった場合
- DomOperationsへ渡す引数や戻り値の形が変わった場合
- DOM操作失敗時の扱いをFeature内で変える場合


## 2. 主な関数と意味

| 関数 | 業務上の意味 |
|---|---|
| `Register-ScanTargetSyncDomAdapter` | DOM JavaScript bundleをブラウザへ登録する |
| `Assert-ScanTargetSyncPage` | デバイス一覧ページとして成立しているか確認する |
| `Prepare-ScanTargetSyncOperationScope` | チェック操作可能な画面状態か確認する |
| `Assert-ScanTargetSyncDeviceList` | デバイス一覧リストの契約を確認する |
| `Get-ScanTargetSyncDeviceTotalCount` | 契約結果からUI一覧件数を取り出す |
| `Test-ScanTargetSyncPageIdentity` | 対象タブがScanTargetSync対象ページか判定する |
| `Get-VisibleScanTargetSyncRows` | 現在見えている行情報を取得する |
| `Set-ScanTargetSyncDesiredState` | endpointのチェック状態を目的状態へ同期する |
| `Assert-ScanTargetSyncPostSelectionContract` | チェック後の手動スキャン開始メニュー有効化を確認する |
| `Scroll-ScanTargetSyncListToTop` | 一覧を先頭へ戻す |
| `Scroll-ScanTargetSyncListDown` | 一覧を下へスクロールする |

## 3. Adapterの役割

Workflow側は `SyncEndpointCheckbox` や `findDeviceRowsInfo` というJavaScriptメソッド名を知りません。Workflowは `Set-ScanTargetSyncDesiredState` や `Get-VisibleScanTargetSyncRows` という業務名で呼びます。

この分離により、JavaScript側メソッド名の変更がWorkflowまで波及しにくくなります。

## 4. 変更時の注意

このファイルに業務判定を入れてはいけません。ON/OFF判定は `Rules.ps1`、CSV/UI整合検証はWorkflow側の責務です。`DomAdapter.ps1` は画面操作名の窓口に留めてください。
