# dom/features/scan-target-sync/contract.js

## 1. このファイルを一言でいうと

ScanTargetSync が操作してよいデバイス一覧画面か、一覧の列・行・checkboxが安全に扱えるか、チェック後に「手動スキャンを開始」メニューが有効になるかを確認する契約ファイルです。

ScanTargetSync は画面上のcheckboxを変更するジョブです。誤った一覧領域や誤った列を操作すると、対象外端末を選択する可能性があります。そのため、実操作前に画面・一覧・後続操作の契約を確認します。

---

## このファイルを変更する典型ケース

- デバイス一覧画面のHTML構造、selector、見出し、navigation の構造が変わった場合
- `PowerShell_DOM対応表.md` に載っている method 名や `ContractScope` が変わった場合
- `fatal` / `warning` の分類が変わった場合
- `contractResult` の戻り値、`checks`、`details` の構造が変わった場合
- 後続の手動スキャンメニューの有効化条件が変わった場合

---

## 2. このファイルが担当する範囲

担当すること:

```text
- 画面がScanTargetSync対象のデバイス一覧か識別する
- product identity / sensor / device default / navigation を確認する
- keyword search, draggable row, 件数表示などの基本構造を確認する
- endpoint列とcheckbox列を含む一覧scopeを確認する
- チェック後に手動スキャン開始メニューが使えるか確認する
- DOM要素をPowerShellへ返せる診断情報へ変換する
```

担当しないこと:

```text
- endpoint行の一覧取得本体。これは list.js
- checkboxをクリックする実操作。これは actions.js
- CSV側のON/OFF判定。これは PowerShell側の Rules / Workflow
- CDP呼び出し。これは Foundation/DomHelper.ps1
```

---

## 3. PowerShell側 operation との対応

HelperName: `__ScanTargetSyncDomHelper`

| PowerShell operation | JavaScript method | ContractScope | 目的 |
|---|---|---|---|
| `DetectPageIdentity` | `detectDevicePageIdentity` | `scanTargetSyncDevicePageIdentity` | 操作対象ページか識別する |
| `ValidateDevicePageContract` | `validateDevicePageContract` | `scanTargetSyncDevicePage` | デバイス一覧画面の基本構造を確認する |
| `ValidateDeviceListContract` | `validateDeviceListContract` | `scanTargetSyncDeviceList` | 行・endpoint列・checkbox列・scroll container を確認する |
| `ValidatePostSelectionContract` | `validatePostSelectionContract` | `scanTargetSyncPostSelection` | 選択後に手動スキャンメニューが使える状態か確認する |

PowerShell側の定義は `main/modules/ScanTargetSync/internal/DomOperations.ps1`、横断対応は `docs/08_DOM_JavaScript/PowerShell_DOM対応表.md` を参照してください。

---

## 4. 主な契約 scope

| scope | 確認すること | 失敗時の意味 |
|---|---|---|
| `scanTargetSyncDevicePageIdentity` | 画面が対象ページらしいか | そもそも操作対象画面ではない可能性がある |
| `scanTargetSyncDevicePage` | 基本画面、検索欄、表示中行、件数表示 | 初期画面として操作できる前提が不足している |
| `scanTargetSyncDeviceList` | 操作対象scope、endpoint列、checkbox列、行構造、scroll container | 対象外端末を操作する危険がある |
| `scanTargetSyncPostSelection` | 選択後に手動スキャン開始メニューが有効化されているか | checkbox操作後に後続処理へ進めない |

`ValidateDeviceListContract` は、実際のチェック操作前の安全装置です。endpoint列やcheckbox列を誤認すると、対象外端末を操作する可能性があるため、該当要素が見つからない場合は fatal とします。

---

## 5. `validateDeviceListContract` の読み方

処理の大枠は次です。

```text
validateDeviceListContract
  ├─ resolveHeaderContract
  │    ├─ requiredHeaders を含むheaderを探す
  │    └─ checkbox header があるか確認
  ├─ resolveDeviceRowScope
  │    ├─ 操作対象scope候補を集める
  │    ├─ endpoint列とcheckbox列を持つscopeを選ぶ
  │    └─ 一意に選べるか確認
  ├─ getDeviceListTotalCount
  ├─ findScrollContainer
  ├─ rowInfos を確認する
  │    ├─ dataId があるか
  │    ├─ endpoint が読めるか
  │    ├─ checkbox候補が1件か
  │    └─ duplicate key がないか
  └─ contractResult('scanTargetSyncDeviceList', checks, details)
```

この契約で fatal になる代表例は次です。

| 条件 | なぜ fatal か |
|---|---|
| operation scope が0件または複数件 | どの一覧を操作すべきか一意に決まらない |
| endpoint列が見つからない | CSV側endpointと画面行を照合できない |
| checkbox列が見つからない | 操作対象checkboxを特定できない |
| 行ごとのcheckbox候補が1件でない | 誤ったcheckboxを操作する危険がある |
| scroll container が見つからない | 仮想スクロール前提の走査ができない |
| duplicate key がある | 表示行を一意に扱えない |

---

## 6. `validatePostSelectionContract` の読み方

処理の大枠は次です。

```text
validatePostSelectionContract
  ├─ findDeviceRowsInfo()
  ├─ selected row を表示中DOMから確認する
  ├─ getSearchManualScanStartMenuItems()
  ├─ 手動スキャン開始に相当するmenu itemを探す
  ├─ disabled / visible / clickable を確認する
  └─ contractResult('scanTargetSyncPostSelection', checks, details)
```

ここで重要なのは、選択行の確認は warning になり得る点です。仮想スクロールでは、選択済み行が表示範囲外にあると、DOM上で選択行を確認できないことがあります。そのため、表示中選択行の不足だけで即停止せず、手動スキャン開始メニューの有効化を主契約として確認します。

一方、手動スキャン開始メニューが見つからない、または有効でない場合は fatal です。checkbox操作が成功しても後続操作へ進めない状態だからです。

---

## 7. `details` に入る診断情報

契約失敗時に原因を追うため、`details` には次のような情報を入れます。

```text
- pageTexts
- viewport / searchBox / sensorNav の elementDebug
- totalCount
- header contract の結果
- operationScopeCandidates
- selected operation scope の summary
- rowsWithDataId / rowsWithEndpoint / checkboxBadRows
- duplicateKeys
- manualScanStartItems
```

PowerShellへ DOM element そのものは返しません。`elementDebug()` と `sanitizeForReturn()` により、tagName、id、className、text、aria-label、visible などの診断可能な plain object へ変換します。

---

## 8. 戻り値契約の基本

`contractResult` の基本形は次です。

```text
ContractResult
  scope        : 契約名
  ok           : fatalCount が0なら true
  fatalCount   : severity=fatal の失敗数
  warningCount : severity=warning の失敗数
  checks       : 個別check結果
  details      : 追加診断情報
```

`ok: false` は「画面状態を診断結果として返す」場合に使います。`throw` は「このまま続けると誤操作になるため即座に止める」場合に使います。

---

## 9. 変更時の注意

`ValidatePostSelectionContract` は「チェックできたか」ではなく「チェック後に手動スキャン開始へ進める状態になったか」を見る後続条件です。これを削ると、チェック操作は成功したが画面上では次操作に進めない、という状態を検出しにくくなります。

selector や見出し判定を変える場合は、`docs/08_DOM_JavaScript/DOM契約とselector診断の読み方.md`、`docs/08_DOM_JavaScript/PowerShell_DOM対応表.md`、`main/tests/js/scan-target-sync.dom.behavior.test.js` も確認してください。
