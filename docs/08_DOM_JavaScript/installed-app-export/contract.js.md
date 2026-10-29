# dom/features/installed-app-export/contract.js

## 1. このファイルを一言でいうと

InstalledAppExport 画面が自動操作してよい画面かを確認し、InstalledAppExport feature 全体で使う DOM 診断 helper を提供する契約ファイルです。

InstalledAppExportジョブは一覧行をクリックして右側詳細パネルを開き、そこからアプリCSVを出力します。別画面や不完全な画面でこの操作を実行すると、単なる失敗ではなく誤クリックになります。そのため、実操作の前に契約確認で「この画面を触ってよいか」を判定します。

---

## このファイルを変更する典型ケース

- InstalledAppExport画面の識別に使うテキスト、selector、画面構造が変わった場合
- `detectAssetPageIdentity` / `validateAssetPageContract` の戻り値が変わった場合
- `contractResult`, `elementDebug`, `sanitizeForReturn`, `clickElement` などの共通 helper が変わった場合
- PowerShell側の `ContractScope` と JavaScript側の scope 名が変わった場合
- contract failure / missing element の診断内容が変わった場合

---

## 2. このファイルが担当する範囲

担当すること:

```text
- InstalledAppExport対象画面か識別する
- document.readyState を確認する
- InstalledAppExport画面らしいテキストを確認する
- 一覧操作に必要な基本DOMが存在するか確認する
- 契約結果を contractResult として構造化する
- DOM element を elementDebug で診断情報に変換する
- DOM element や循環参照を sanitizeForReturn で安全化する
- clickElement で可視・disabled判定付きクリックを共通化する
```

担当しないこと:

```text
- 端末一覧の列・行・scroll container の詳細確認。これは list.js
- 詳細パネルの対象一致確認。これは detail.js
- アプリタブとCSVボタンの確認。これは apps.js
- 詳細パネルを閉じる操作。これは actions.js
```

---

## 3. PowerShell側 operation との対応

HelperName: `__InstalledAppExportDomHelper`

| PowerShell operation | JavaScript method | ContractScope | 目的 |
|---|---|---|---|
| `DetectPageIdentity` | `detectAssetPageIdentity` | `assetPageIdentity` | InstalledAppExport対象画面か識別する |
| `ValidatePageContract` | `validateAssetPageContract` | `assetPage` | 初期画面として必要な要素があるか確認する |

PowerShell側の定義は `main/modules/InstalledAppExport/internal/DomOperations.ps1`、横断対応は `docs/08_DOM_JavaScript/PowerShell_DOM対応表.md` を参照してください。

---

## 4. 共通 helper の役割

| helper | 役割 |
|---|---|
| `norm` | DOM text を比較しやすい形へ正規化する |
| `isVisible` | 要素が表示対象か判定する |
| `isDisabled` | disabled / aria-disabled / class 等から無効状態を判定する |
| `elementDebug` | tagName, id, className, text, visible などの診断情報を作る |
| `sanitizeForReturn` | DOM element、配列、object、循環参照をPowerShellへ返せる形にする |
| `makeCheck` | 契約checkの1件を作る |
| `contractResult` | scope, ok, fatalCount, warningCount, checks, details をまとめる |
| `throwContractIfFatal` | fatal failure があれば例外として止める |
| `clickElement` | visible / disabled を確認してからclickする |

`installed-app-export/list.js` や `installed-app-export/apps.js` は、これらの helper が存在する前提で実装されています。`contract.js` の読み込み順を後ろへ動かすと、後続ファイルが helper を参照できなくなります。

---

## 5. `detectAssetPageIdentity` の読み方

`detectAssetPageIdentity` は、対象ページらしさを構造化して返します。

主な観点は次です。

```text
- document.readyState
- InstalledAppExport画面らしいテキスト
- grid / header / viewport などの候補
- 画面識別に使った要素の elementDebug
```

この method は、ページ識別のための軽い契約です。helper未登録時は PowerShell側で `ReturnContractFailure` として扱われます。

---

## 6. `validateAssetPageContract` の読み方

処理の大枠は次です。

```text
validateAssetPageContract
  ├─ detectAssetPageIdentity 相当の識別情報を作る
  ├─ document.readyState を確認
  ├─ InstalledAppExport画面らしいテキストを確認
  ├─ 一覧領域・ヘッダー候補を確認
  └─ contractResult('assetPage', checks, details)
```

この契約は、端末一覧の詳細構造までは確定しません。詳細な列・行・scroll container の確認は `installed-app-export/list.js` の `validateAssetListContract` が担当します。

---

## 7. 戻り値契約の基本

DOM JavaScript は、PowerShell に DOM 要素そのものを返してはいけません。DOM 要素はブラウザ内の生オブジェクトであり、CDP 経由でそのまま扱うと診断しにくくなります。このプロジェクトでは、PowerShell 側へ返す値は原則として plain object に変換します。

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

## 8. 変更時の注意

`elementDebug` や `sanitizeForReturn` は、エラー時ログの品質に直結します。ここを削ると、PowerShell側で「DOM契約違反」と出ても、どの候補が見えていたのか分からなくなります。

共通 helper を変更する場合は、InstalledAppExportだけでなく `tests/js/dom.contract.sanitize.test.js`、`tests/js/installed-app-export.dom.behavior.test.js`、`docs/08_DOM_JavaScript/DOM契約とselector診断の読み方.md` も確認してください。
