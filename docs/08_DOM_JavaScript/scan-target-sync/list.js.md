# dom/features/scan-target-sync/list.js

## 1. このファイルを一言でいうと

ScanTargetSync のデバイス一覧から endpoint 行とcheckbox候補を読み取り、仮想スクロール対象を操作するファイルです。

`contract.js` が「操作してよい一覧か」を確認し、`actions.js` が「実際にcheckboxを同期する」のに対して、このファイルは表示中DOMから業務上の行情報を取り出す役割を持ちます。

---

## このファイルを変更する典型ケース

- デバイス一覧の行DOM、列DOM、checkbox構造、scroll container が変わった場合
- endpoint名の抽出ルールが変わった場合
- 行の選択状態やcheckbox状態の読み方が変わった場合
- `FindDeviceRowsInfo`, `ScrollToTop`, `ScrollDown` の戻り値が変わった場合
- `actions.js` が使う行探索 helper の意味が変わった場合

---

## 2. このファイルが担当する範囲

担当すること:

```text
- 操作対象scope内の表示中行を取得する
- endpoint列の値を読み、正規化する
- 行内のcheckbox候補を探す
- 行の選択状態とcheckbox.checkedを読む
- endpoint名で表示中行を絞り込む
- 仮想スクロールのcontainerを探す
- 一覧を先頭へ戻す / 下方向へ進める
```

担当しないこと:

```text
- 画面全体の契約判定。これは contract.js
- checkboxクリックの実操作。これは actions.js
- CSVと画面行の照合方針。これは PowerShell側 Workflow / Rules
```

---

## 3. PowerShell側 operation との対応

HelperName: `__ScanTargetSyncDomHelper`

| PowerShell operation | JavaScript method | 目的 |
|---|---|---|
| `FindDeviceRowsInfo` | `findDeviceRowsInfo` | 表示中のendpoint行情報を返す |
| `ScrollToTop` | `scrollToTop` | 一覧を先頭へ戻す |
| `ScrollDown` | `scrollDown` | 一覧を下へスクロールする |

`SyncEndpointCheckbox` は `actions.js` の method ですが、その内部でこのファイルの `findRowsByEndpoint`、`getCheckboxCandidatesFromRow`、`isRowSelected` を使います。

---

## 4. 主な method の役割

| method | 役割 |
|---|---|
| `getDraggableRows` | draggable属性を持つ一覧行候補を取得する |
| `getVisibleDraggableRows` | 表示中のdraggable行だけに絞る |
| `getHeaderRowsInfo` | header行と列見出しを診断情報として読む |
| `resolveOperationHeaderContract` | endpoint列とcheckbox列を解決する |
| `resolveDeviceRowScope` | 操作対象一覧scopeを一意に選ぶ |
| `findDeviceRows` | 現在DOM上に存在する表示中行を返す |
| `findDeviceRowsInfo` | endpoint名、選択状態、checkbox情報を含む行情報を返す |
| `findRowsByEndpoint` | endpoint名で表示中行を絞り込む |
| `findScrollContainer` | 仮想スクロール対象のcontainerを探す |
| `scrollToTop` | 一覧を先頭へ戻す |
| `scrollDown` | 一覧を下方向へ進める |

---

## 5. operation scope とは何か

この画面には、固定列やスクロール可能な表など、DOM上では複数の表に見える領域が存在する可能性があります。`resolveDeviceRowScope` は、その中から「checkbox操作に使うべき一覧領域」を選びます。

```text
候補scopeを集める
  ├─ endpoint列があるか
  ├─ checkbox列があるか
  ├─ visible行があるか
  ├─ fixed-leftか通常表か
  └─ 一意に選べるか確認
```

この選定が曖昧なまま `actions.js` がクリックすると、固定列側・通常表側・別一覧側の要素を誤って操作する可能性があります。そのため、scope は `contract.js` と `actions.js` の両方で重要です。

---

## 6. `findDeviceRowsInfo` の戻り値

PowerShell側の `Workflow.UiScan.ps1` は、この情報をCSV側データと突き合わせます。

```text
DeviceRowInfo
  endpoint               : 端末名またはendpoint名
  dataId                 : 行識別子
  selected               : 行が選択状態か
  checked                : checkbox.checked の状態
  checkboxCandidateCount : 行内checkbox候補数
  checkbox               : checkboxの診断情報
  label                  : labelの診断情報
  row                    : elementDebugによる行診断情報
```

ここで返すのは plain object です。DOM element そのものは返しません。

---

## 7. `findRowsByEndpoint` の意味

`findRowsByEndpoint(endpoint)` は、現在表示中の行だけを対象にします。仮想スクロールでまだ表示されていない行は、この method では見つかりません。

PowerShell側は次の流れで一覧全体を走査します。

```text
ScrollToTop
  ↓
FindDeviceRowsInfo
  ↓
表示中行をCSV側計画と照合
  ↓
必要なら SyncEndpointCheckbox
  ↓
ScrollDown
  ↓
次の表示範囲を読む
```

そのため、`endpoint_not_found_in_visible_rows` は「CSVに存在しない」という意味ではなく、「現在表示中DOM上にはない」という意味です。

---

## 8. scroll container の扱い

`findScrollContainer` は、画面全体ではなく一覧の仮想スクロール対象を探します。`scrollToTop` と `scrollDown` は、このcontainerの `scrollTop` を変更し、scroll event をdispatchします。

scroll container を誤ると、PowerShell側のスキャンループは同じ行を読み続けたり、一覧外の領域をスクロールしたりします。`SameScrollLimit` による停止判定もこの前提に依存します。

---

## 9. 変更時の注意

固定列と通常列が重複して存在する画面では、同じendpointが複数のDOM行に見える場合があります。`findRowsByEndpoint` の候補数チェックを弱くすると、表示上は1端末でもDOM上の別表を誤って操作する危険があります。

行情報の構造を変える場合は、`main/modules/ScanTargetSync/internal/Workflow.UiScan.ps1`、`main/modules/ScanTargetSync/internal/Workflow.EndpointSync.ps1`、`main/tests/js/scan-target-sync.dom.behavior.test.js` も確認してください。
