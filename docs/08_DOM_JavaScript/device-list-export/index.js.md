# dom/features/device-list-export/index.js

## 1. このファイルを一言でいうと

DeviceListExport 用の JavaScript helper `window.__DeviceListExportDomHelper` を作る入口です。

## このファイルを変更する典型ケース

- 画面HTML、selector、クリックやスクロールのDOM操作が変わった場合
- PowerShell側の `DomOperations.ps1` から呼ばれるmethod名や戻り値が変わった場合
- contract failure / missing element の診断内容が変わった場合


## 2. このファイルが担当する範囲

このファイルは、`contract.js`、`navigation.js`、`export.js` が登録した part object を1つの `domHelper` object に合成します。PowerShell側は最終的にこの `domHelper` object のメソッドを CDP 経由で呼び出します。

## 3. このファイルが担当しない範囲

このファイル自体は、DOM検索やクリックを実行しません。画面要素の探し方は `navigation.js` と `export.js`、契約確認は `contract.js` が担当します。

## 4. 組み立ての流れ

```text
createDeviceListExportDomHelper(window, document)
  ├─ version / selectors / _lastExportClickResult を持つ domHelper を作る
  ├─ window.__DeviceListExportDomHelperParts を読む
  ├─ 各 part を Object.assign で domHelper へ合成する
  └─ window.__DeviceListExportDomHelper として公開する
```

## 5. PowerShell側との関係

`modules/DeviceListExport/internal/DomOperations.ps1` は helper名として `__DeviceListExportDomHelper` を指定しています。つまり、このファイルが実行されていない場合、PowerShell側の DOM operation は helper未登録として失敗します。

## 6. JavaScript文法上のポイント

### IIFE

ファイル全体は即時実行関数で囲まれています。ブラウザでは `window.__DeviceListExportDomHelper` に登録し、Node.js のテスト環境では `module.exports` で factory を公開できるようにしています。

### Object.assign

複数ファイルで定義された part を1つの object に合成します。後から同名メソッドを登録すると上書きされるため、メソッド名の重複は避ける必要があります。

## 7. 変更時の注意

`version` は診断用です。機能分岐に使ってはいけません。`window.__DeviceListExportDomHelperParts` の合成順は DOM bundle の登録順に依存するため、`foundation.jobs.psd1` の `DomFeaturePaths` を変更するとこのファイルの合成結果も変わります。
