# dom/features/device-list-export/contract.js

## 1. このファイルを一言でいうと

DeviceListExport 画面で処理を始めてよいか、またエクスポート操作後にクリックが成立したかを確認する DOM 契約ファイルです。

## このファイルを変更する典型ケース

- 画面HTML、selector、クリックやスクロールのDOM操作が変わった場合
- PowerShell側の `DomOperations.ps1` から呼ばれるmethod名や戻り値が変わった場合
- contract failure / missing element の診断内容が変わった場合


## 2. このファイルが担当する範囲

このファイルは、画面が想定どおりの「センサー / デバイス既定グループ」画面であること、操作ボタンや一覧件数が取れること、エクスポートクリックが受理されたことを確認します。

## 3. このファイルが担当しない範囲

操作ボタンをクリックする処理は `export.js` が担当します。このファイルは、クリックしてよい状態か、クリック後の事後条件が満たされたかを判定します。

## 4. PowerShell側 operation との対応

| PowerShell operation | JavaScript method | 目的 |
|---|---|---|
| `DetectPageIdentity` | `detectDeviceListExportPageIdentity` | 対象ページらしさを判定する |
| `ValidateInitialContract` | `validateInitialContract` | 初期状態でナビゲーションが使えるか確認する |
| `ValidateExportPageContract` | `validateExportPageContract` | エクスポート画面として必要な要素が揃っているか確認する |
| `ValidateExportPostcondition` | `validateExportPostcondition` | エクスポートクリックがDOM操作として成立したか確認する |

## 5. 主な処理の流れ

```text
validateExportPageContract
  ├─ buildIdentityChecks
  │    ├─ document.readyState を確認
  │    ├─ 製品識別テキストを確認
  │    ├─ 「センサー」テキストを確認
  │    └─ 「デバイス (既定グループ)」テキストを確認
  ├─ resolveDeviceDefaultNavigation
  ├─ resolveTaskButton
  ├─ getDeviceListTotalCount
  └─ contractResult で checks をまとめる
```

## 6. 戻り値の形

契約確認メソッドは `contractResult(scope, checks, details)` を返します。

```text
ContractResult
  ok      : fatal check がすべて成功しているか
  scope   : deviceListExportInitial / deviceListExportPage など
  checks  : 個別確認項目の配列
  details : 診断用情報
```

`checks` の各要素には `name`、`ok`、`severity`、`message`、`details` が入ります。PowerShell側の `Assert-FoundationDomHelperContract` は、ここに `severity: fatal` かつ `ok: false` があるとジョブを止めます。

## 7. 重要な判定

| 判定 | fatalになる理由 |
|---|---|
| document.readyState が利用可能でない | 画面読み込み前に操作すると要素探索が不安定になる |
| 製品識別テキストがない | 別画面を操作している可能性がある |
| センサーのナビゲーションが一意でない | 誤ったメニューをクリックする危険がある |
| デバイス一覧件数が読めない | エクスポート対象一覧として認識できない |
| 操作ボタンが一意でない | エクスポート起点を誤る危険がある |

## 8. 変更時の注意

`hasProductIdentityText` や `hasSensorText` を緩くしすぎると、別画面をDeviceListExport対象画面として誤認します。逆に厳しくしすぎると、軽微な表示文言変更で自動処理が止まります。変更する場合は、fatal check の粒度を維持しつつ、`details` に候補テキストを残す必要があります。


## 戻り値契約の基本

DOM JavaScript は、PowerShell に DOM 要素そのものを返してはいけません。DOM 要素はブラウザ内の生オブジェクトであり、CDP 経由でそのまま扱うと診断しにくくなります。このプロジェクトでは、PowerShell 側へ返す値は原則として次のような plain object に変換します。

```text
成功・失敗を表す戻り値
  ok      : true / false
  reason  : 失敗理由。PowerShell 側ログに出る診断キー
  count   : 候補数。1でなければ曖昧または未検出
  summary : elementDebug() で作った人間向けの要約
  details : 追加診断情報
```

`ok: false` を返す処理と、`throw new Error(...)` する処理は意味が違います。`ok: false` は「画面状態を診断結果として返す」場合に使います。`throw` は「このまま続けると誤操作になるため、即座に止める」場合に使います。
