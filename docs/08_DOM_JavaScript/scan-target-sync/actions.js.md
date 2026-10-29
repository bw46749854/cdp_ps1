# dom/features/scan-target-sync/actions.js

## 1. このファイルを一言でいうと

ScanTargetSync の実操作、つまり対象endpointのcheckbox状態をON/OFFへ同期するファイルです。

`SyncEndpointCheckbox` は、ScanTargetSync DOM helper の中で最も誤操作リスクが高い入口です。対象endpoint行を一意に見つけ、checkbox候補も一意に確認し、必要な場合だけクリックし、クリック後に再取得して期待状態に一致したかを検証します。

---

## このファイルを変更する典型ケース

- checkboxやlabelのDOM構造が変わった場合
- endpoint候補、checkbox候補、disabled状態の判定が変わった場合
- `prepareOperationContext` の保持対象scopeが変わった場合
- `syncEndpointCheckbox` の戻り値や `reason` が変わった場合
- PowerShell側の `SyncEndpointCheckbox` operation の `Await` や呼び出し方が変わった場合

---

## 2. このファイルが担当する範囲

担当すること:

```text
- 操作対象scopeを準備して保持する
- endpoint行を表示中DOMから探す
- 候補0件・複数件を失敗扱いにする
- 行内checkbox候補を一意に確認する
- checkboxまたはlabelがdisabledでないことを確認する
- 実効選択状態を読む
- 必要な場合だけ label.click() する
- クリック後に行とcheckboxを再取得して検証する
```

担当しないこと:

```text
- 画面全体の契約確認。これは contract.js
- 一覧行の基本抽出。これは list.js
- CSVからdesiredCheckedを決める処理。これは PowerShell側 Rules / Workflow
```

---

## 3. PowerShell側 operation との対応

HelperName: `__ScanTargetSyncDomHelper`

| PowerShell operation | JavaScript method | MissingHelperBehavior | Await | 目的 |
|---|---|---|---|---|
| `PrepareOperationContext` | `prepareOperationContext` | `Throw` | なし | 操作対象一覧scopeを確定して保持する |
| `SyncEndpointCheckbox` | `syncEndpointCheckbox` | `Throw` | `Await = $true` | 指定endpointのcheckbox状態を期待値へ合わせる |

`SyncEndpointCheckbox` は実際にクリックを行うため、helper未登録時は続行不能です。また、クリック後のDOM反映を待つ必要があるため、PowerShell側の operation registry では `Await = $true` です。

---

## 4. 主な処理の流れ

```text
prepareOperationContext
  ├─ resolveDeviceRowScope
  ├─ 操作対象scopeが一意か確認
  ├─ setPreparedOperationContext
  └─ context要約を返す

syncEndpointCheckbox(endpoint, desiredChecked)
  ├─ endpoint を正規化
  ├─ prepared context が有効か確認
  ├─ endpoint一致行を探す
  ├─ 候補0件・複数件を失敗扱い
  ├─ 行内checkbox候補が1件か確認
  ├─ disabled でないか確認
  ├─ 現在の実効選択状態を判定
  ├─ 必要なら label.click()
  ├─ 再度行とcheckboxを取得
  └─ 実効選択状態が desiredChecked と一致するか確認
```

---

## 5. `prepareOperationContext` の意味

`prepareOperationContext` は、後続の `syncEndpointCheckbox` が操作する一覧scopeを固定します。

この準備を行う理由は、画面内に似た一覧や固定列が複数存在する場合に、毎回違うscopeを解決して誤操作することを避けるためです。

ただし、DOM再描画で保持済みscopeが切断されることがあります。その場合、`syncEndpointCheckbox` は `operation_context_not_prepared_or_disconnected` を返して安全に失敗します。

---

## 6. 実効選択状態とは何か

この画面では、`input.checked` だけでなく、行側の選択classが実際の選択状態を表すことがあります。そのためこのファイルでは、次のOR条件で選択状態を判定しています。

```text
beforeEffectiveChecked = wasSelected || wasChecked
afterEffectiveChecked  = selectedNow || checkedNow
```

`input.checked` だけを見ると、UI上は選択済みなのに未選択と誤判定する可能性があります。逆に行classだけを見ると、checkboxの実状態とずれる可能性があります。そのため、クリック前後で両方を確認します。

---

## 7. なぜ `label.click()` を使うのか

この画面では、checkbox input そのものではなく label 側のクリックで行選択状態が更新される設計になっている可能性があります。そのため、単純に `checkbox.click()` へ置き換えてはいけません。

クリック後は、同じDOM参照を信じず、対象行とcheckbox候補を再取得します。これにより、クリック後のDOM更新、再描画、選択状態反映の失敗を検出できます。

---

## 8. 戻り値の形

```text
SyncEndpointCheckboxResult
  ok                     : 同期できたか
  endpoint               : 対象endpoint
  desiredChecked         : 期待するcheckbox状態
  checked                : 最終的な実効選択状態
  changed                : クリックにより変更したか
  alreadyAligned         : クリック前から期待状態だったか
  reason                 : ok=false の理由
  before / after         : 操作前後の行診断情報
  context                : 操作対象scopeの要約
```

PowerShell側は `ok`、`reason`、`changed`、`alreadyAligned`、`checked` を見て、成功・失敗・既に一致済みを分類します。

---

## 9. 失敗理由 `reason`

| reason | 意味 |
|---|---|
| `operation_context_not_prepared_or_disconnected` | `prepareOperationContext` が未実行、またはDOM再描画でscopeが切断された |
| `endpoint_not_found_in_visible_rows` | 現在表示中の行に対象endpointがない |
| `duplicate_endpoint_in_visible_rows` | 同じendpoint候補が複数ある |
| `checkbox_candidate_count_not_one` | クリック前の行内checkbox候補が一意でない |
| `checkbox_disabled` | checkboxまたはlabelが無効状態 |
| `endpoint_candidate_count_not_one_after_click` | クリック後に対象endpoint行を一意に再確認できない |
| `checkbox_candidate_count_not_one_after_click` | クリック後にcheckbox候補を一意に再確認できない |
| `selection_state_not_aligned_after_click` | クリック後の選択状態が期待値と一致しない |

`endpoint_not_found_in_visible_rows` は、一覧全体に存在しないという意味ではありません。現在の仮想スクロール表示範囲に存在しない、という意味です。

---

## 10. 変更時の注意

`label.click()` を `checkbox.click()` に単純変更しないでください。また、クリック後に再取得して検証する構造を削ると、DOM更新失敗を成功扱いしてしまいます。

`reason` の文字列を変更する場合は、PowerShell側の失敗分類、ログ、JS test、`docs/08_DOM_JavaScript/PowerShell_DOM対応表.md` を同時に確認してください。
