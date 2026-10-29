# dom/features/installed-app-export/index.js

## 1. このファイルを一言でいうと

InstalledAppExport 用の JavaScript helper `window.__InstalledAppExportDomHelper` を作る入口です。

## このファイルを変更する典型ケース

- 画面HTML、selector、クリックやスクロールのDOM操作が変わった場合
- PowerShell側の `DomOperations.ps1` から呼ばれるmethod名や戻り値が変わった場合
- contract failure / missing element の診断内容が変わった場合


## 2. このファイルが担当する範囲

`contract.js`、`list.js`、`detail.js`、`apps.js`、`actions.js` が登録した part object を合成し、PowerShell側から呼べる1つの helper にします。

## 3. このファイルが担当しない範囲

このファイルは、端末一覧の探索、詳細パネル操作、アプリタブ操作、CSVボタンクリックを実装しません。それらは各 part ファイルが担当します。

## 4. 組み立ての流れ

```text
createInstalledAppExportDomHelper(window, document)
  ├─ helperのversionとselectorを定義
  ├─ window.__InstalledAppExportDomHelperParts を取得
  ├─ Object.assign で part を合成
  └─ window.__InstalledAppExportDomHelper として公開
```

## 5. PowerShell側との関係

`modules/InstalledAppExport/internal/DomOperations.ps1` の `$script:InstalledAppExportDomHelperName` は `__InstalledAppExportDomHelper` です。この名前が変わると、PowerShell側の全InstalledAppExport DOM operationが helper 未登録として失敗します。

## 6. 変更時の注意

合成される part のメソッド名は、PowerShell側の `MethodName` と一致している必要があります。たとえば `getAssetListTotalCount` を改名するなら、PowerShell側の `GetListTotalCount` operation 定義も同時に変更が必要です。
