# ScanTargetSync internal/DomOperations.ps1

## この文書の位置づけ

この文書は `main/modules/ScanTargetSync/internal/DomOperations.ps1` の個別ファイルドキュメントです。
PowerShell側のDOM operation registryと、ブラウザ内JavaScript helper methodとの契約を説明します。

## このファイルを変更する典型ケース

- DOM operation の `MethodName`、`Await`、`MissingHelperBehavior` が変わった場合
- JavaScript helperとの契約、戻り値、例外扱いが変わった場合
- raw Foundation DOM helper呼び出しの境界が変わった場合


## このファイルの責務

`DomOperations.ps1` は、ScanTargetSync Feature内で raw Foundation DOM helper を呼ぶ境界です。
WorkflowやRulesから直接 `Invoke-FoundationDomHelperMethod` / `Assert-FoundationDomHelperContract` を呼ばせないため、operation名、helper名、method名、契約metadataをここに閉じ込めます。

```text
Workflow / DomAdapter
  ↓
ScanTargetSync Dom operation wrapper
  ↓
Foundation DomHelper
  ↓
window.__ScanTargetSyncDomHelper.<method>
```

## DOM helper と operation registry

このファイルのhelper名は次です。

```text
__ScanTargetSyncDomHelper
```

operation registry は `$script:ScanTargetSyncDomOperations` にあります。
PowerShell側のoperation名を、JavaScript側のmethod名とmetadataに対応づけます。

| operation | JavaScript method | 主な用途 | MissingHelperBehavior | Await | ContractScope |
|---|---|---|---|---|---|
| `DetectPageIdentity` | `detectDevicePageIdentity` | 対象ページ識別 | `ReturnContractFailure` | - | `scanTargetSyncDevicePageIdentity` |
| `ValidateDevicePageContract` | `validateDevicePageContract` | デバイス一覧画面契約確認 | `ReturnContractFailure` | - | `scanTargetSyncDevicePage` |
| `PrepareOperationContext` | `prepareOperationContext` | 操作前コンテキスト準備 | `Throw` | - | - |
| `ValidateDeviceListContract` | `validateDeviceListContract` | デバイス一覧リスト契約確認 | `ReturnContractFailure` | - | `scanTargetSyncDeviceList` |
| `FindDeviceRowsInfo` | `findDeviceRowsInfo` | 可視行情報の取得 | `Throw` | - | - |
| `SyncEndpointCheckbox` | `syncEndpointCheckbox` | endpointのチェック状態同期 | `Throw` | `true` | - |
| `ValidatePostSelectionContract` | `validatePostSelectionContract` | チェック後の検索メニュー有効化契約 | `ReturnContractFailure` | - | `scanTargetSyncPostSelection` |
| `ScrollToTop` | `scrollToTop` | 一覧先頭へスクロール | `Throw` | `true` | - |
| `ScrollDown` | `scrollDown` | 一覧を下方向へスクロール | `Throw` | `true` | - |

## `Await` の契約

`Await = $true` は、呼び出し側の一時的な都合ではなく、operationそのものの意味契約です。

現行実装では次のoperationが非同期完了待ちを必要とします。

```text
SyncEndpointCheckbox
ScrollToTop
ScrollDown
```

これらはDOM変更やスクロール完了を伴うため、JavaScript Promise の完了を待たずに次へ進むと、UI走査・チェック状態検証・後続スクロールが不安定になります。
そのため、`Await` は呼び出し側に散在させず、operation registryに置きます。

`New-ScanTargetSyncDomHelperParameters` は、呼び出し時に `-Await` が指定された場合、またはregistry側に `Await = $true` がある場合に、Foundation DomHelperへ `Await = $true` を渡します。

## `MissingHelperBehavior` の扱い

`MissingHelperBehavior` は、DOM要素が見つからない時ではなく、`window.__ScanTargetSyncDomHelper` helper自体が未登録だった時の扱いです。

ScanTargetSyncでは、一覧取得系で helper未登録を空配列として扱ってはいけません。
helper未登録と「本当に0件」を混同すると、UI全件走査の検証が壊れます。

| 用途 | 方針 |
|---|---|
| ページ識別・契約検証 | `ReturnContractFailure` として診断可能に返す |
| 業務操作・一覧取得・スクロール | 原則 `Throw` として続行不能にする |
| 後続処理で0件と区別が必要な一覧取得 | `MissingValue = @()` を使わない |

この方針は `main/ARCHITECTURE.md` の「DOM helper未登録時の統一方針」を正とします。

## parameter生成の優先順位

`New-ScanTargetSyncDomHelperParameters` は、operation registryのmetadataと呼び出し時引数を統合します。
主な優先順位は次です。

| 項目 | 優先順位 |
|---|---|
| `Description` | 呼び出し時の `-Description` があれば優先。なければregistryの `Description` |
| `MissingValue` | 呼び出し時に明示された場合はその値を優先。なければregistryの `MissingValue` |
| `Await` | 呼び出し時 `-Await` またはregistryの `Await = $true` |
| `ContractScope` | registryに定義されている場合に付与 |
| `TimeoutSeconds` | 0より大きい場合のみ付与 |

## 公開されるwrapper

| 関数 | 役割 |
|---|---|
| `Get-ScanTargetSyncDomOperationDefinition` | operation名からdefinitionを取得し、helper名とmissing helper messageを補う |
| `New-ScanTargetSyncDomHelperParameters` | Foundation DomHelperへ渡すparameterを構築する |
| `Invoke-ScanTargetSyncDomOperation` | 通常のDOM helper method呼び出しを行う |
| `Assert-ScanTargetSyncDomOperationContract` | DOM契約検証用に `Assert-FoundationDomHelperContract` を呼ぶ |

`Invoke-ScanTargetSyncDomOperation` では、contract検証用の `Description` は不要なため、parametersから削除してから呼び出します。

## JavaScript側との対応

JavaScript側の詳細は次を参照してください。

- `docs/08_DOM_JavaScript/scan-target-sync/contract.js.md`
- `docs/08_DOM_JavaScript/scan-target-sync/actions.js.md`
- `docs/08_DOM_JavaScript/scan-target-sync/index.js.md`

PowerShell側でoperationを追加する場合は、JavaScript側に対応methodが存在するか、契約テストで確認してください。

## ここに書かないこと

`DomOperations.ps1` に次を追加してはいけません。

- CSVの業務判定
- endpointが同期対象かどうかの判断
- UI走査ループの終了条件
- 結果CSVの出力処理
- Workflowの順序制御

このファイルは、DOM helper operation契約の境界であり、業務判断や処理順序の場所ではありません。

## 変更時に見るテスト

- `main/tests/ScanTargetSync.DomOperations.Tests.ps1`
- `main/tests/Dom.OperationRegistryContract.Tests.ps1`
- `main/tests/js/scan-target-sync.dom.behavior.test.js`
- `main/tests/Architecture.Tests.ps1`

## 更新条件

operation名、JavaScript method名、`Await`、`MissingHelperBehavior`、`ContractScope`、`MissingValue`、wrapperの責務が変わった場合に更新します。
DOM selectorの詳細はJavaScript側ドキュメントを更新してください。
