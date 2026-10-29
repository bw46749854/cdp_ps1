# DOM契約と selector 診断の読み方

## 1. この文書を一言でいうと

この文書は、DOM JavaScript の `contractResult`、`fatal` / `warning`、`ContractScope`、selector 診断を読むための横断ガイドです。

PowerShell側の `DomOperations.ps1` は、JavaScript helper を method 名で呼びます。JavaScript側は、画面DOMが期待どおりかを契約結果として返します。この境界を誤解すると、DOM変更時に「0件」と「helper未登録」や、「画面が違う」と「候補が一時的に見えていない」を混同します。

---

## 2. `contractResult` の基本形

`contract.js` は、画面DOMが期待どおりかを `contractResult(scope, checks, details)` で返します。

| 項目 | 意味 |
|---|---|
| `scope` | どの契約を確認したか。PowerShell側の `ContractScope` と対応する |
| `ok` | fatal failure が0件なら `true` |
| `fatalCount` | 続行できない契約違反数 |
| `warningCount` | 注意すべきだが即停止しない件数 |
| `checks` | 個別確認結果の配列 |
| `details` | 診断用の補足情報 |

`ok` は「すべて完全に問題なし」ではなく、「fatal が0件で、続行可能」という意味です。warning がある場合でも `ok: true` になることがあります。

---

## 3. `fatal` と `warning` の違い

| severity | 意味 | PowerShell側の扱い |
|---|---|---|
| `fatal` | このまま操作すると誤操作・誤取得の可能性がある | contract failure として扱い、Workflow の続行可否に影響する |
| `warning` | 注意すべきだが、仮想スクロールや画面状態により即異常とは限らない | 診断情報として残す。単独では停止理由にしない |

例として、ScanTargetSync の `validatePostSelectionContract` では、表示中DOM上で選択行を確認できない場合を warning にします。仮想スクロールでは、選択済み行が表示範囲外にあるだけでDOM上には存在しないことがあるためです。一方、手動スキャンメニューが見つからない、または有効化されていない状態は fatal です。

---

## 4. `ContractScope` の対応

PowerShell側の `DomOperations.ps1` は、契約確認 operation に `ContractScope` を持ちます。JavaScript側の `contractResult(scope, ...)` とこの値が一致することで、どの契約が失敗したかを安定して読めます。

| Feature | PowerShell operation | JavaScript method | ContractScope |
|---|---|---|---|
| DeviceListExport | `DetectPageIdentity` | `detectDeviceListExportPageIdentity` | `deviceListExportPageIdentity` |
| DeviceListExport | `ValidateInitialContract` | `validateInitialContract` | `deviceListExportInitial` |
| DeviceListExport | `ValidateExportPageContract` | `validateExportPageContract` | `deviceListExportPage` |
| DeviceListExport | `ValidateExportPostcondition` | `validateExportPostcondition` | `deviceListExportPostcondition` |
| InstalledAppExport | `DetectPageIdentity` | `detectAssetPageIdentity` | `assetPageIdentity` |
| InstalledAppExport | `ValidatePageContract` | `validateAssetPageContract` | `assetPage` |
| InstalledAppExport | `ValidateListContract` | `validateAssetListContract` | `assetList` |
| InstalledAppExport | `ValidateClickedRowContext` | `validateClickedRowContext` | `clickedRowContext` |
| InstalledAppExport | `ValidateAppListContract` | `validateAppListContract` | `appList` |
| ScanTargetSync | `DetectPageIdentity` | `detectDevicePageIdentity` | `scanTargetSyncDevicePageIdentity` |
| ScanTargetSync | `ValidateDevicePageContract` | `validateDevicePageContract` | `scanTargetSyncDevicePage` |
| ScanTargetSync | `ValidateDeviceListContract` | `validateDeviceListContract` | `scanTargetSyncDeviceList` |
| ScanTargetSync | `ValidatePostSelectionContract` | `validatePostSelectionContract` | `scanTargetSyncPostSelection` |

この表の詳細な operation 対応は `docs/08_DOM_JavaScript/PowerShell_DOM対応表.md` を正とします。

---

## 5. selector 変更時の影響

selector は PowerShell 側には出さず、DOM JavaScript 側に閉じ込めます。selector を変えると、次に影響します。

```text
- contract.js の契約判定
- list.js の行探索
- actions.js / export.js / apps.js のクリック対象
- docs/08_DOM_JavaScript/PowerShell_DOM対応表.md の method 対応
- tests/js/*.test.js
- *.DomOperations.Tests.ps1
```

selector を変更するときに重要なのは、「見つかるか」だけではありません。候補が複数になっていないか、見えている要素だけに絞れているか、disabled 要素をクリック対象にしていないか、PowerShellへ返す診断情報が残っているかを確認します。

---

## 6. `MissingHelperBehavior` との関係

JavaScript helper が未登録の場合、PowerShell側の `DomOperations.ps1` は operation ごとの `MissingHelperBehavior` に従います。

| Behavior | 意味 |
|---|---|
| `ReturnContractFailure` | helper未登録を contract failure として返す |
| `ReturnValue` | 指定された既定値を返す |
| `Throw` | 例外として扱う |

`MissingHelperBehavior` は、DOM要素が見つからない時の扱いではありません。  
`window.__XxxDomHelper` helper 自体が未登録だった時の扱いです。

たとえば一覧取得系で helper 未登録時に空配列を返すと、「本当に0件」と「bundle注入に失敗した」を混同します。そのため、一覧取得や業務操作は原則 `Throw` です。

---

## 7. PowerShellへ返してよい値

DOM JavaScript は、PowerShell に DOM element そのものを返してはいけません。PowerShell 側へ返す値は、CDP経由で扱いやすい plain object にします。

```text
ok      : 成功・続行可能か
reason  : 失敗理由を表す安定した文字列
count   : 候補数
summary : elementDebug() などで作った人間向け要約
details : 追加診断情報
```

`elementDebug()` や `sanitizeForReturn()` は、失敗時に「何が候補として見えていたか」を読むための診断情報です。ここを削ると、PowerShell側ログに contract failure は出ても、原因調査が困難になります。

---

## 8. 関連ドキュメント

| 文書 | 役割 |
|---|---|
| `docs/00_最初に読む/12_DOM_JavaScriptの読み方.md` | DOM JavaScript 全体の読み順 |
| `docs/08_DOM_JavaScript/PowerShell_DOM対応表.md` | PowerShell operation と JavaScript method の対応 |
| `docs/08_DOM_JavaScript/scan-target-sync/contract.js.md` | ScanTargetSync の画面契約 |
| `docs/08_DOM_JavaScript/installed-app-export/contract.js.md` | InstalledAppExport の画面契約と共通診断 helper |
| `docs/09_テスト仕様/04_DOM_JavaScriptテスト.md` | JS test の読み方 |

---

## 9. この文書を更新する条件

`contractResult` の形、fatal / warning の分類方針、`MissingHelperBehavior` の意味、PowerShell operation と contract scope の対応が変わった場合に更新します。
