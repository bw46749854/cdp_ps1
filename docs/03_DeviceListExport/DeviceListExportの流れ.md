# DeviceListExportの流れ

## この文書の位置づけ

この文書は横断ガイドです。
`DeviceListExport` の詳細仕様や関数一覧の正本ではありません。

目的は、DOM系Jobの入門として `DeviceListExport` の処理の通し方を理解することです。

## この文書を変更する典型ケース

- DeviceListExportの処理順序、読み順、責務境界の説明が変わった場合
- DeviceListExportをDOM系Jobの入口として読むための導線が変わった場合
- 個別ファイルドキュメントへの参照先が変わった場合


## まず理解すること

`DeviceListExport` は、管理画面からエージェント一覧CSVをエクスポートし、ダウンロード結果を整理するJobです。
`InstalledAppExport` や `ScanTargetSync` より流れが短いため、DOM系Jobの基本構造を読む入口に向いています。

```text
Runner
  ↓
Workflow
  ↓
Dependencies
  ↓
DomAdapter
  ↓
DomOperations
  ↓
DOM helper JavaScript
  ↓
Download / Output
```

## 読む順番

1. `docs/03_DeviceListExport/DeviceListExport.psm1.md`
2. `docs/03_DeviceListExport/internal__Runner.ps1.md`
3. `docs/03_DeviceListExport/internal__Workflow.ps1.md`
4. `docs/03_DeviceListExport/internal__Dependencies.ps1.md`
5. `docs/03_DeviceListExport/internal__DomAdapter.ps1.md`
6. `docs/03_DeviceListExport/internal__DomOperations.ps1.md`
7. `docs/03_DeviceListExport/internal__Download.ps1.md`
8. `docs/03_DeviceListExport/internal__Output.ps1.md`
9. `docs/08_DOM_JavaScript/device-list-export/*.md`

## 誤解しやすい点

- `Workflow.ps1` は「どの順番で実行するか」を持ちます。DOM selectorやCDP詳細は持ちません。
- `DomAdapter.ps1` はWorkflowから見た業務名の関数を提供します。
- `DomOperations.ps1` はDOM helper method名、`Await`、`MissingHelperBehavior` などのoperation契約を持ちます。
- Download処理はブラウザ操作とは別の副作用境界です。Workflowへ直接ファイル移動の詳細を増やさないでください。

## 変更内容別の参照先

| 変更内容 | 参照先 |
|---|---|
| エクスポート画面のボタンやDOM契約 | `DomAdapter`, `DomOperations`, `docs/08_DOM_JavaScript/device-list-export` |
| ダウンロード待ちやファイル名調整 | `Download`, `Output` |
| 実行順序 | `Workflow` |
| 依存差し替えやテスト容易性 | `Dependencies` |

## 詳細参照

- `docs/03_DeviceListExport/*.md`
- `docs/08_DOM_JavaScript/device-list-export/*.md`
- `tests/DeviceListExport.*.Tests.ps1`
- `tests/js/device-list-export*.test.js`

## この文書を更新する条件

`DeviceListExport` の処理順序、責務境界、読む順番、変更内容別の参照先が変わった場合に更新します。
関数単位の詳細変更は個別ファイルドキュメントへ反映してください。
