# dom/features/installed-app-export/apps.js

## 1. このファイルを一言でいうと

端末詳細パネル内で、アプリタブを開き、アプリ一覧とCSV出力ボタンを扱うファイルです。

InstalledAppExportジョブでは、一覧行をクリックした後、右側詳細パネルのアプリタブへ移動し、該当端末のアプリCSVを出力します。このファイルは、その詳細パネル内のDOM操作と契約確認を担当します。

---

## このファイルを変更する典型ケース

- 詳細パネル内のタブ構造が変わった場合
- アプリタブのactive判定が変わった場合
- アプリ一覧grid、header、radio button、CSV出力エリアが変わった場合
- CSVボタンの探索条件やクリック条件が変わった場合
- `ValidateAppListContract`, `AssertAppRadioChecked`, `ClickAppCsvButton` の戻り値が変わった場合

---

## 2. このファイルが担当する範囲

担当すること:

```text
- 詳細パネル内のアプリタブを特定する
- アプリタブがactiveか判定する
- アプリタブをクリックする
- アプリ一覧のcontent scopeを特定する
- アプリ一覧gridとheaderを確認する
- アプリ対象radio buttonの状態を確認する
- CSV出力エリアとCSVボタンを解決する
- CSVボタンをクリックする
```

担当しないこと:

```text
- 端末一覧行のクリック。これは list.js
- 詳細パネルが対象端末名と一致するかの確認。これは detail.js
- クリック後のダウンロード待ち。これは PowerShell側 Download.ps1
- CSVファイル名のリネーム。これは PowerShell側 RowAction / Download
```

---

## 3. PowerShell側 operation との対応

HelperName: `__InstalledAppExportDomHelper`

| PowerShell operation | JavaScript method | ContractScope | 目的 |
|---|---|---|---|
| `ClickAppTab` | `clickAppTab` | - | 詳細パネル内のアプリタブを開く |
| `ValidateAppListContract` | `validateAppListContract` | `appList` | アプリ一覧として必要な要素があるか確認する |
| `AssertAppRadioChecked` | `assertAppRadioChecked` | - | アプリ対象のラジオ選択状態を確認する |
| `ClickAppCsvButton` | `clickAppCsvButton` | - | アプリCSVボタンをクリックする |

`validateAppTabContract` は PowerShell側から直接呼ばれる operation ではありません。`clickAppTab` と `validateAppListContract` の内部で使われる内部契約です。

---

## 4. 主な method の役割

| method | 役割 |
|---|---|
| `resolveAppTab` | 詳細パネル内のアプリタブ候補を集める |
| `validateAppTabContract` | アプリタブが一意か、表示・有効・active条件を満たすか確認する |
| `clickAppTab` | アプリタブをクリックする |
| `resolveAppContentScope` | アプリ一覧のcontent scopeを特定する |
| `getAppHeaders` | アプリ一覧のheaderを読む |
| `resolveAppRadio` | アプリ対象radio buttonを解決する |
| `resolveAppCsvAreas` | CSV出力エリア候補を集める |
| `resolveAppCsvButtons` | CSV出力ボタン候補を集める |
| `validateAppListContract` | アプリ一覧として必要なDOM契約を確認する |
| `assertAppRadioChecked` | radio button が期待どおり選択済みか確認する |
| `clickAppCsvButton` | CSVボタンをクリックする |

---

## 5. タブ契約の読み方

`validateAppTabContract(requireActive)` は、呼び出し場面によって active 条件の扱いが変わります。

| 呼び出し場面 | requireActive | activeでない場合 |
|---|---:|---|
| `clickAppTab` の前 | `false` | warning。クリック前は未activeを許容する |
| `validateAppListContract` の中 | `true` | fatal。クリック後はactiveである必要がある |

`validateAppTabContract(false)` はクリック前の確認であり、未activeを許容します。  
`validateAppListContract()` はクリック後の確認であり、LastMonthInstallExtract tab が active であることを fatal 条件として確認します。

---

## 6. `validateAppListContract` の読み方

処理の大枠は次です。

```text
validateAppListContract
  ├─ validateAppTabContract(true)
  ├─ resolveAppContentScope
  ├─ app grid を確認する
  ├─ requiredAppHeaders を確認する
  ├─ resolveAppRadio
  ├─ resolveAppCsvAreas
  ├─ resolveAppCsvButtons
  └─ contractResult('appList', checks, details)
```

この契約で fatal になる代表例は次です。

| 条件 | なぜ fatal か |
|---|---|
| LastMonthInstallExtract tab がactiveでない | 一覧やCSVボタンが別tabのものかもしれない |
| content scope が解決できない | アプリ一覧の範囲を限定できない |
| required header が不足している | アプリ一覧として期待する表ではない |
| radio button が一意でない | 出力対象を誤認する可能性がある |
| CSV出力エリアが一意でない | どのCSVボタンを押すべきか曖昧 |
| CSVボタン候補が一意でない | 誤クリックの危険がある |
| CSVボタンがdisabled | クリックしても出力できない |

---

## 7. CSVボタン探索の考え方

CSVボタン探索は、画面全体ではなくLastMonthInstallExtract tab のcontent scope内に限定します。これは、詳細パネル内に似たボタンや別tabのボタンが増えた場合でも、誤クリックを避けるためです。

```text
app content scope
  └─ CSV出力エリア
       └─ CSVボタン候補
            ├─ visible
            ├─ not disabled
            └─ 候補数が1件
```

テキストだけに依存して画面全体からボタンを探す変更は避けてください。

---

## 8. 戻り値で重要なもの

```text
CsvButtonClickResult
  ok      : クリックできたか
  action  : click-app-csv-button など
  button  : elementDebugによるボタン診断
  area    : CSVエリアの診断情報
```

PowerShell側は、クリック結果そのものよりも、その後の `Download.ps1` でダウンロードCSVが出現することを待ちます。ただし、クリック段階でDOM契約違反があればここで止めます。

---

## 9. 変更時の注意

CSVボタン探索をテキストだけに依存させると、画面内に似たボタンが増えた場合に誤クリックします。現在のように、アプリタブのcontent scope内に限定し、候補数を確認する構造を維持してください。

戻り値や契約scopeを変更する場合は、`main/modules/InstalledAppExport/internal/RowAction.ps1`、`main/modules/InstalledAppExport/internal/DomAdapter.ps1`、`main/tests/js/installed-app-export.dom.behavior.test.js` も確認してください。
