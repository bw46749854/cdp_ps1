# CompositeJobs ジョブ連携

## この文書の位置づけ

この文書は横断ガイドです。
`CompositeJobs` の詳細仕様や関数一覧の正本ではありません。

目的は、個別Jobを再実装せずに連携する薄い層として `CompositeJobs` を読むことです。

## まず理解すること

`CompositeJobs` はFeature moduleではありません。
既存Jobを順番に呼び、前段Jobの成果物を後段Jobへ渡すための連携層です。

```text
WeeklyScanTargetSync
  ↓
DeviceListExport
  ↓
ScanTargetSync

MonthlyInstallReport
  ↓
InstalledAppExport
  ↓
LastMonthInstallExtract
```

Composite Job は、子JobのDOM操作、CSV解析、業務判定を持ちません。

## 読む順番

1. `docs/07_CompositeJobs/CompositeJobs.psm1.md`
2. `docs/03_DeviceListExport/DeviceListExportの流れ.md`
3. `docs/05_ScanTargetSync/ScanTargetSync_PolicyとWorkflowの分離.md`
4. `docs/04_InstalledAppExport/InstalledAppExport_業務トランザクション.md`
5. `docs/06_LastMonthInstallExtract/LastMonthInstallExtract_ジョブ.md`

## 誤解しやすい点

- Composite Job は子Jobの中身をコピーしません。`Invoke-CompositeChildJob` が依存port `Foundation.InvokeJob` を呼び、その既定実装が `Invoke-FoundationEntrypoint` で既存Jobを実行します。
- 成果物確認は、ファイル名や存在確認に限定します。CSVの中身を読んで判断しません。
- 親Contextの `ConfigPath` と `JobRegistryPath` は子Jobへ伝播します。親子で別の設定を読むと同じ連携Jobの意味が壊れます。
- `MonthlyInstallReport` は実行ごとのtimestampディレクトリを作り、過去実行分CSVの混入を防ぎます。

## 変更内容別の参照先

| 変更内容 | 参照先 |
|---|---|
| 子Jobの呼び出し順序 | `CompositeJobs.psm1` |
| DeviceListExport結果をScanTargetSyncへ渡す方法 | `CompositeJobs.psm1`, DeviceListExport / ScanTargetSync docs |
| InstalledAppExport結果をLastMonthInstallExtractへ渡す方法 | `CompositeJobs.psm1`, InstalledAppExport / LastMonthInstallExtract docs |
| config / job registry path の扱い | `CompositeJobs.psm1`, Foundation Config / JobRegistry docs |

## 詳細参照

- `docs/07_CompositeJobs/CompositeJobs.psm1.md`
- `main/ARCHITECTURE.md` の Composite Job 境界
- `tests/CompositeJobs.*.Tests.ps1`

## この文書を更新する条件

Composite Jobの責務境界、連携Jobの種類、子Jobへの設定伝播、読む順番が変わった場合に更新します。
子Job内部の仕様変更は、各Featureの個別ドキュメントを更新してください。
