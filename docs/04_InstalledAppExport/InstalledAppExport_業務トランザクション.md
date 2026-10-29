# InstalledAppExport 業務トランザクション

## この文書の位置づけ

この文書は横断ガイドです。
`InstalledAppExport` の詳細仕様や関数一覧の正本ではありません。

目的は、`InstalledAppExport` の中心である「1台分のアプリCSV取得」を業務トランザクションとして読むことです。

## この文書を変更する典型ケース

- InstalledAppExportの1台分処理を業務トランザクションとして読む境界が変わった場合
- RowAction、Download、Workflowの責務関係の説明が変わった場合
- 後始末、失敗継続、成果物出力の読み方が変わった場合


## まず理解すること

`InstalledAppExport` は、端末一覧を走査し、対象行ごとに詳細パネルを開き、アプリ一覧CSVをダウンロードします。
中心は `RowAction.ps1` です。

`RowAction.ps1` は大きく見えても、次の一連の業務単位を表すため、単純な行数だけで分割対象にしません。

```text
対象行を開く
  ↓
詳細パネルを確認する
  ↓
アプリタブを開く
  ↓
CSVを出す
  ↓
ダウンロードを待つ
  ↓
ファイル名を整える
  ↓
詳細パネルを閉じる
```

## 読む順番

1. `docs/04_InstalledAppExport/InstalledAppExport.psm1.md`
2. `docs/04_InstalledAppExport/internal__Runner.ps1.md`
3. `docs/04_InstalledAppExport/internal__Workflow.ps1.md`
4. `docs/04_InstalledAppExport/internal__RowAction.ps1.md`
5. `docs/04_InstalledAppExport/internal__DomAdapter.ps1.md`
6. `docs/04_InstalledAppExport/internal__DomOperations.ps1.md`
7. `docs/04_InstalledAppExport/internal__Download.ps1.md`
8. `docs/04_InstalledAppExport/internal__Models.ps1.md`
9. `docs/04_InstalledAppExport/internal__Output.ps1.md`
10. `docs/08_DOM_JavaScript/installed-app-export/*.md`

## 誤解しやすい点

- `RowAction.ps1` は「大きいから悪い」のではありません。業務トランザクションとして一体で読む方が安全な範囲です。
- ただし、DOM selector、raw CDP、raw file I/O、CSV形式の細部を `RowAction.ps1` に増やしてはいけません。
- DOM操作は `DomAdapter.ps1` の業務名関数を通し、低レベルoperation契約は `DomOperations.ps1` に閉じます。
- `InstalledAppExport` と `LastMonthInstallExtract` は連携しますが、`InstalledAppExport` は `LastMonthInstallExtract` のCSV解析ルールを知りません。

## 変更内容別の参照先

| 変更内容 | 参照先 |
|---|---|
| 一覧走査や対象行の探し方 | `Workflow`, `DomAdapter`, DOM JavaScript |
| 1台分のダウンロード手順 | `RowAction`, `Download` |
| DOM契約やoperation | `DomOperations`, `docs/08_DOM_JavaScript/installed-app-export` |
| 出力行・結果構造 | `Models`, `Output` |
| `InstalledAppExport → LastMonthInstallExtract` 連携 | `docs/07_CompositeJobs/CompositeJobs_ジョブ連携.md` |

## 詳細参照

- `docs/04_InstalledAppExport/*.md`
- `docs/08_DOM_JavaScript/installed-app-export/*.md`
- `main/ARCHITECTURE.md` の `SRP-EXCEPTION-08`
- `tests/InstalledAppExport.*.Tests.ps1`

## この文書を更新する条件

`InstalledAppExport` の業務トランザクション境界、読む順番、変更内容別の参照先が変わった場合に更新します。
`RowAction.ps1` 内の個別関数詳細は、個別ファイルドキュメントを更新してください。
