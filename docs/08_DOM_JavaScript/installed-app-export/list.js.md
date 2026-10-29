# dom/features/installed-app-export/list.js

## 1. このファイルを一言でいうと

端末一覧の列、行、選択状態、スクロール位置を扱うファイルです。

端末一覧は固定列側 grid と通常 grid が分かれているため、1行の情報を読むには両方のDOMを対応付ける必要があります。そのため `list.js` は単なる一覧取得ではなく、固定列・通常列・scroll container の整合確認を担当します。

---

## このファイルを変更する典型ケース

- 端末一覧のgrid構造、header構造、行DOM、data-id の扱いが変わった場合
- 端末名列の見出しやselectorが変わった場合
- 固定列側gridと通常gridの対応付けが変わった場合
- scroll container や仮想スクロールの動きが変わった場合
- `FindRowsInfo`, `ClickNameCell`, `GetSelectedRow` の戻り値構造が変わった場合

---

## 2. このファイルが担当する範囲

担当すること:

```text
- 端末名列を特定する
- fixed grid / main grid の行を対応付ける
- 表示中の端末行情報を返す
- dataId と assetName で対象行を解決する
- 端末名セルをクリックする
- クリック後に選択行を確認する
- 一覧の総件数を読む
- scroll container を探す
- 一覧を先頭へ戻す / 下方向へ進める
```

担当しないこと:

```text
- InstalledAppExport画面そのものの識別。これは contract.js
- 詳細パネル内の対象一致確認。これは detail.js
- アプリタブとCSVボタン。これは apps.js
- ダウンロード待ちやファイルリネーム。これは PowerShell側 Download / RowAction
```

---

## 3. PowerShell側 operation との対応

HelperName: `__InstalledAppExportDomHelper`

| PowerShell operation | JavaScript method | 目的 |
|---|---|---|
| `ValidateListContract` | `validateAssetListContract` | 一覧として必要な列・行構造があるか確認する |
| `GetListTotalCount` | `getAssetListTotalCount` | 画面上の総件数を読む |
| `FindRowsInfo` | `findAssetRowsInfo` | 現在表示されている行情報を返す |
| `ClickNameCell` | `clickAssetNameCell` | 指定行の端末名セルをクリックする |
| `GetSelectedRow` | `getSelectedAssetRow` | クリック後に選択行が対象になったか確認する |
| `ScrollToTop` | `scrollToTop` | 一覧を先頭へ戻す |
| `ScrollDown` | `scrollDown` | 一覧を下へスクロールする |

---

## 4. 主な method の役割

| method | 役割 |
|---|---|
| `resolveAssetNameColumn` | headerから端末名列を特定する |
| `validateAssetListContract` | 一覧操作に必要な列・scope・行・scroll container を確認する |
| `getAssetListTotalCount` | 画面上の件数表示を読む |
| `resolveAssetRowScope` | 操作対象のgrid scopeを選ぶ |
| `findAssetRows` | 表示中の端末行を返す |
| `findAssetRowsInfo` | dataId, assetName, selected, row診断情報を返す |
| `resolveAssetRow` | dataId と assetName で対象行を一意に解決する |
| `clickAssetNameCell` | 対象行の端末名セルをクリックする |
| `getSelectedAssetRow` | 現在選択されている端末行を返す |
| `findScrollContainer` | 一覧の仮想スクロール対象を探す |
| `scrollToTop` | 一覧を先頭へ戻す |
| `scrollDown` | 一覧を下方向へ進める |

---

## 5. fixed grid と main grid

端末一覧では、固定列側と通常列側が別DOMとして存在することがあります。

```text
fixed grid
  └─ 行の選択状態や固定列側セル

main grid
  └─ 端末名などの通常列セル
```

表示上は1行でも、DOM上は複数の行断片に分かれて見えます。そのため、`data-id` や端末名を使って、業務上の「1台分の行」として扱える形に変換します。

---

## 6. `validateAssetListContract` の読み方

処理の大枠は次です。

```text
validateAssetListContract
  ├─ resolveAssetNameColumn
  ├─ resolveAssetRowScope
  ├─ getAssetListTotalCount
  ├─ findScrollContainer
  ├─ 表示中行があるか確認
  ├─ dataId / assetName が読めるか確認
  ├─ selected row の候補を確認
  └─ contractResult('assetList', checks, details)
```

この契約で fatal になる代表例は次です。

| 条件 | なぜ fatal か |
|---|---|
| 端末名列が特定できない | 詳細パネルを開く対象セルが決まらない |
| 操作対象scopeが一意に決まらない | fixed / main / 別gridを誤認する危険がある |
| 表示中行がない | 一覧走査を開始できない |
| dataId や assetName が読めない | 行の一意性を保てない |
| scroll container が見つからない | 一覧全体の走査ができない |

---

## 7. `findAssetRowsInfo` の戻り値

```text
AssetRowInfo
  dataId       : 画面上の行識別子
  assetName : 端末名
  index        : 表示中一覧内での位置
  selected     : 現在選択されているか
  row          : elementDebugによる診断情報
```

PowerShell側の `ScrollableListWorkflow` は、この行情報を使って「処理済み行か」「新しく見えた行か」を判断します。

---

## 8. `clickAssetNameCell` の安全条件

`clickAssetNameCell(dataId, assetName)` は、詳細パネルを開く実操作です。安全のため、次の確認を行います。

```text
- dataId に一致する行がある
- assetName も一致している
- 端末名セルが見つかる
- セルが表示対象である
- 必要なら scrollRowIntoView する
- clickResolvedAssetNameCell でクリックする
```

`dataId` だけ、または `assetName` だけで対象行を決めると、再描画や重複名の影響を受けやすくなります。両方を使う構造を維持してください。

---

## 9. 変更時の注意

`resolveAssetNameColumn` の判断を弱くすると、別列のセルを端末名として扱う可能性があります。`clickAssetNameCell` は詳細パネルを開く実操作なので、`dataId` と `assetName` の両方で対象行を確認する構造を維持してください。

戻り値構造を変更する場合は、`main/modules/InstalledAppExport/internal/Workflow.ps1`、`main/modules/InstalledAppExport/internal/RowAction.ps1`、`main/tests/js/installed-app-export.dom.behavior.test.js` も確認してください。
