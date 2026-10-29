# PowerShell DOM operation と JavaScript method の対応表

## 1. この表の位置づけ

この表は、PowerShell側の `DomOperations.ps1` に定義された operation が、どの JavaScript helper method を呼ぶかを示します。

DOM JavaScript を読むときは、まずこの表で次を確認します。

```text
PowerShell operation
  ↓
HelperName
  ↓
JavaScript method
  ↓
実装ファイル
  ↓
ContractScope / MissingHelperBehavior / Await
```

`ContractScope`、`fatal` / `warning`、selector 診断の読み方は `docs/08_DOM_JavaScript/DOM契約とselector診断の読み方.md` を参照してください。

---

## 2. DeviceListExport

HelperName: `__DeviceListExportDomHelper`

| PowerShell operation | JavaScript method | JavaScriptファイル | ContractScope | MissingHelperBehavior | Await |
|---|---|---|---|---|---|
| `DetectPageIdentity` | `detectDeviceListExportPageIdentity` | `device-list-export/contract.js` | `deviceListExportPageIdentity` | `ReturnContractFailure` | なし |
| `ValidateInitialContract` | `validateInitialContract` | `device-list-export/contract.js` | `deviceListExportInitial` | `ReturnContractFailure` | なし |
| `ValidateExportPageContract` | `validateExportPageContract` | `device-list-export/contract.js` | `deviceListExportPage` | `ReturnContractFailure` | なし |
| `ClickTaskButton` | `clickTaskButton` | `device-list-export/export.js` | - | `Throw` | `Await = $true` |
| `IsTaskMenuReady` | `isTaskMenuReady` | `device-list-export/export.js` | - | `ReturnValue` | なし |
| `ClickExportMenuItem` | `clickExportMenuItem` | `device-list-export/export.js` | - | `Throw` | `Await = $true` |
| `ValidateExportPostcondition` | `validateExportPostcondition` | `device-list-export/contract.js` | `deviceListExportPostcondition` | `ReturnContractFailure` | なし |

`IsTaskMenuReady` は待機predicateです。helper未登録時は `ReturnValue` で `$false` を返し、待機中の一時状態として扱います。クリック系 operation は helper未登録なら続行不能なので `Throw` です。

---

## 3. InstalledAppExport

HelperName: `__InstalledAppExportDomHelper`

| PowerShell operation | JavaScript method | JavaScriptファイル | ContractScope | MissingHelperBehavior | Await |
|---|---|---|---|---|---|
| `DetectPageIdentity` | `detectAssetPageIdentity` | `installed-app-export/contract.js` | `assetPageIdentity` | `ReturnContractFailure` | なし |
| `ValidatePageContract` | `validateAssetPageContract` | `installed-app-export/contract.js` | `assetPage` | `ReturnContractFailure` | なし |
| `ValidateListContract` | `validateAssetListContract` | `installed-app-export/list.js` | `assetList` | `ReturnContractFailure` | なし |
| `GetListTotalCount` | `getAssetListTotalCount` | `installed-app-export/list.js` | - | `Throw` | なし |
| `FindRowsInfo` | `findAssetRowsInfo` | `installed-app-export/list.js` | - | `Throw` | なし |
| `ClickNameCell` | `clickAssetNameCell` | `installed-app-export/list.js` | - | `Throw` | なし |
| `GetSelectedRow` | `getSelectedAssetRow` | `installed-app-export/list.js` | - | `ReturnValue` | なし |
| `IsDetailPanelReadyFor` | `isDetailPanelReadyFor` | `installed-app-export/detail.js` | - | `ReturnValue` | なし |
| `ValidateClickedRowContext` | `validateClickedRowContext` | `installed-app-export/detail.js` | `clickedRowContext` | `ReturnContractFailure` | なし |
| `ClickAppTab` | `clickAppTab` | `installed-app-export/apps.js` | - | `Throw` | なし |
| `ValidateAppListContract` | `validateAppListContract` | `installed-app-export/apps.js` | `appList` | `ReturnContractFailure` | なし |
| `AssertAppRadioChecked` | `assertAppRadioChecked` | `installed-app-export/apps.js` | - | `Throw` | なし |
| `GetDetailName` | `getDetailAssetName` | `installed-app-export/detail.js` | - | `Throw` | なし |
| `ClickAppCsvButton` | `clickAppCsvButton` | `installed-app-export/apps.js` | - | `Throw` | なし |
| `CloseDetailPanel` | `closeDetailPanel` | `installed-app-export/actions.js` | - | `ReturnValue` | なし |
| `IsDetailPanelClosed` | `isDetailPanelClosed` | `installed-app-export/actions.js` | - | `ReturnValue` | なし |
| `ScrollToTop` | `scrollToTop` | `installed-app-export/list.js` | - | `Throw` | なし |
| `ScrollDown` | `scrollDown` | `installed-app-export/list.js` | - | `Throw` | なし |

InstalledAppExport は一覧、詳細パネル、アプリタブ、CSVボタンまでDOM操作範囲が広いため、operation の実装ファイルが複数に分かれています。`RowAction.ps1` はこれらを直接知るのではなく、`DomAdapter.ps1` の業務名関数経由で呼びます。

---

## 4. ScanTargetSync

HelperName: `__ScanTargetSyncDomHelper`

| PowerShell operation | JavaScript method | JavaScriptファイル | ContractScope | MissingHelperBehavior | Await |
|---|---|---|---|---|---|
| `DetectPageIdentity` | `detectDevicePageIdentity` | `scan-target-sync/contract.js` | `scanTargetSyncDevicePageIdentity` | `ReturnContractFailure` | なし |
| `ValidateDevicePageContract` | `validateDevicePageContract` | `scan-target-sync/contract.js` | `scanTargetSyncDevicePage` | `ReturnContractFailure` | なし |
| `PrepareOperationContext` | `prepareOperationContext` | `scan-target-sync/actions.js` | - | `Throw` | なし |
| `ValidateDeviceListContract` | `validateDeviceListContract` | `scan-target-sync/contract.js` | `scanTargetSyncDeviceList` | `ReturnContractFailure` | なし |
| `FindDeviceRowsInfo` | `findDeviceRowsInfo` | `scan-target-sync/list.js` | - | `Throw` | なし |
| `SyncEndpointCheckbox` | `syncEndpointCheckbox` | `scan-target-sync/actions.js` | - | `Throw` | `Await = $true` |
| `ValidatePostSelectionContract` | `validatePostSelectionContract` | `scan-target-sync/contract.js` | `scanTargetSyncPostSelection` | `ReturnContractFailure` | なし |
| `ScrollToTop` | `scrollToTop` | `scan-target-sync/list.js` | - | `Throw` | `Await = $true` |
| `ScrollDown` | `scrollDown` | `scan-target-sync/list.js` | - | `Throw` | `Await = $true` |

ScanTargetSync はCSV側のON/OFF計画とUI側のcheckbox状態を同期します。`SyncEndpointCheckbox` は実操作であり、クリック後の再取得と選択状態検証まで行うため `Await = $true` です。

---

## 5. この表を変更する条件

次が変わった場合に更新します。

```text
- `DomOperations.ps1` の operation 名が増減した
- `MethodName` が変わった
- `HelperName` が変わった
- `ContractScope` が変わった
- `MissingHelperBehavior` が変わった
- `Await = $true` の有無が変わった
- JavaScript method の実装ファイルが変わった
```

この表は source の代替ではありません。最終的な実行事実は `main/modules/*/internal/DomOperations.ps1` と `main/dom/features/**/*.js` で確認します。
