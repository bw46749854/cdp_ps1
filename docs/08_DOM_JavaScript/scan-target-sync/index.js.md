# dom/features/scan-target-sync/index.js

## 1. このファイルを一言でいうと

ScanTargetSync 用の JavaScript helper `window.__ScanTargetSyncDomHelper` を作る入口です。

## このファイルを変更する典型ケース

- 画面HTML、selector、クリックやスクロールのDOM操作が変わった場合
- PowerShell側の `DomOperations.ps1` から呼ばれるmethod名や戻り値が変わった場合
- contract failure / missing element の診断内容が変わった場合


## 2. このファイルが担当する範囲

`contract.js`、`list.js`、`actions.js` が登録した part object を合成し、PowerShell側から呼び出せる helper として公開します。

## 3. このファイルが担当しない範囲

CSVの読み込み、対象判定、照合はPowerShell側の `CsvInput.ps1`、`Rules.ps1`、`Reconciliation.ps1` が担当します。このJavaScript helperは、すでに対象と決まった endpoint を画面上で探し、チェック状態を同期することだけを担当します。

## 4. 組み立ての流れ

```text
createScanTargetSyncDomHelper(window, document)
  ├─ domHelper object を作る
  ├─ window.__ScanTargetSyncDomHelperParts を読む
  ├─ Object.assign で part を合成
  └─ window.__ScanTargetSyncDomHelper として公開
```

## 5. 変更時の注意

`_operationContext` は `actions.js` 側で使われる状態です。これは「どの一覧領域を操作対象にするか」を保持するためのものです。index側で初期化方法を変えると、`prepareOperationContext` と `syncEndpointCheckbox` の前提が壊れます。
