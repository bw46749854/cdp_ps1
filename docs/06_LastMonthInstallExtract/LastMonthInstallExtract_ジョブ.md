# LastMonthInstallExtract ジョブ

## この文書の位置づけ

この文書は横断ガイドです。
`LastMonthInstallExtract` の詳細仕様や関数一覧の正本ではありません。

目的は、ブラウザを使わないCSV処理Jobとして `LastMonthInstallExtract` を読む入口を示すことです。

## この文書を変更する典型ケース

- LastMonthInstallExtractジョブの入力、判定、出力の読み方が変わった場合
- InstalledAppExport連携時と単独実行時の説明が変わった場合
- 詳細仕様の参照先や変更時の読み順が変わった場合


## まず理解すること

`LastMonthInstallExtract` はDOM系Jobではありません。
`InstalledAppExport` などで取得されたアプリCSVを読み、必要な条件で抽出し、結果CSVと失敗CSVを出力します。

```text
対象CSVを探す
  ↓
文字コード・区切り文字を判定する
  ↓
CSVレコードに変換する
  ↓
ヘッダーと業務条件を検証する
  ↓
対象行を抽出する
  ↓
結果CSV / 失敗CSVを出す
```

## 読む順番

1. `docs/06_LastMonthInstallExtract/LastMonthInstallExtract.psm1.md`
2. `docs/06_LastMonthInstallExtract/internal__Runner.ps1.md`
3. `docs/06_LastMonthInstallExtract/internal__Workflow.ps1.md`
4. `docs/06_LastMonthInstallExtract/internal__Input.ps1.md`
5. `docs/06_LastMonthInstallExtract/internal__Encoding.ps1.md`
6. `docs/06_LastMonthInstallExtract/internal__DelimitedText.ps1.md`
7. `docs/06_LastMonthInstallExtract/internal__Rules.ps1.md`
8. `docs/06_LastMonthInstallExtract/internal__Models.ps1.md`
9. `docs/06_LastMonthInstallExtract/internal__Output.ps1.md`
10. `docs/06_LastMonthInstallExtract/internal__Dependencies.ps1.md`

## 誤解しやすい点

- `LastMonthInstallExtract` はブラウザを操作しません。`DomAdapter` や `DomOperations` はありません。
- 文字コード、区切り文字、CSV列、日付判定はそれぞれ変更理由が異なります。Workflowへ直接詰め込まないでください。
- `InstalledAppExport → LastMonthInstallExtract` 連携時も、`LastMonthInstallExtract` は `InstalledAppExport` の内部処理を知りません。受け取ったディレクトリ内のCSVを処理します。
- 単独実行とComposite Job経由実行では、入力ディレクトリの決まり方が異なる場合があります。

## 変更内容別の参照先

| 変更内容 | 参照先 |
|---|---|
| 入力ファイル探索 | `Input`, `Dependencies` |
| 文字コード推定 | `Encoding` |
| 区切り文字・CSV解析 | `DelimitedText` |
| 抽出条件・日付判定 | `Rules` |
| 出力レコード構造 | `Models`, `Output` |
| `InstalledAppExport → LastMonthInstallExtract` 連携 | `CompositeJobs` |

## 詳細参照

- `docs/06_LastMonthInstallExtract/*.md`
- `docs/07_CompositeJobs/CompositeJobs_ジョブ連携.md`
- `tests/LastMonthInstallExtract.*.Tests.ps1`

## この文書を更新する条件

`LastMonthInstallExtract` の処理順序、責務境界、変更内容別の参照先が変わった場合に更新します。
CSV列や関数単位の詳細は個別ファイルドキュメントを更新してください。
