# Foundation

## この文書の位置づけ

この文書は横断ガイドです。
`Foundation` モジュールの関数一覧や個別実装の正本ではありません。

目的は、個別Jobを読む前に、`Foundation` がどの共通サービスを提供しているかを理解することです。

## この文書を変更する典型ケース

- Foundationの役割、読み順、各Jobとの関係が変わった場合
- 共通サービスとFeature moduleの責務境界の説明が変わった場合
- 詳細仕様の参照先や正本関係が変わった場合


## まず理解すること

`Foundation` は業務処理を担当しません。
業務処理は `DeviceListExport`、`InstalledAppExport`、`ScanTargetSync`、`LastMonthInstallExtract`、`CompositeJobs` が担当します。

`Foundation` が提供するのは、ジョブ実行の土台です。

```text
run_job.ps1
  ↓
Foundation
  ↓
各Job module
```

主な責務は次です。

| 領域 | 役割 |
|---|---|
| Bootstrap / RunContext | JobNameから実行Contextを作る |
| Config / JobRegistry | `foundation.config.psd1` と `foundation.jobs.psd1` を読む |
| Logging | 実行ログとセクションログを出す |
| FileSystem | 出力ディレクトリ、安全なファイル削除、パス検証 |
| CDP / Browser | Chrome DevTools Protocol 接続とページ操作 |
| DomBundle / DomHelper / DomContract | DOM helper JSの注入、呼び出し、契約検証 |
| ScrollableList | 仮想スクロール一覧を扱う共通部品 |

## 読む順番

1. `docs/02_Foundation/Foundation.psm1.md`
2. `docs/02_Foundation/internal__Bootstrap.ps1.md`
3. `docs/02_Foundation/internal__RunContext.ps1.md`
4. `docs/02_Foundation/internal__Config.ps1.md`
5. `docs/02_Foundation/internal__JobRegistry.ps1.md`
6. `docs/02_Foundation/internal__Logging.ps1.md`
7. `docs/02_Foundation/internal__FileSystem.ps1.md`
8. DOM系ジョブを読む場合だけ、`Cdp*`, `DomBundle`, `DomHelper`, `DomContract` を読む

## 誤解しやすい点

- `Foundation` に業務ルールを追加しないでください。共通基盤が個別Jobの事情を知ると、全Jobへ変更影響が広がります。
- Feature module は raw CDP や raw DOM helper を直接扱わず、`Foundation` が公開する安定した境界またはFeature内Adapterを使います。
- DOM helper未登録は「要素が見つからない」とは別の異常です。`MissingHelperBehavior` の扱いは `ARCHITECTURE.md` を正としてください。
- `ScrollableList` は共通化されていますが、各Featureの業務判断を持たせる場所ではありません。

## 詳細参照

- `main/ARCHITECTURE.md`
- `docs/02_Foundation/Foundation.psm1.md`
- `docs/02_Foundation/internal__Cdp*.ps1.md`
- `docs/02_Foundation/internal__Dom*.ps1.md`
- `docs/02_Foundation/internal__ScrollableList.ps1.md`
- `tests/Architecture.Tests.ps1`
- `tests/Dom.OperationRegistryContract.Tests.ps1`

## この文書を更新する条件

Foundationの提供サービス分類、読む順番、Feature moduleとの境界が変わった場合に更新します。
個別関数の追加・引数変更だけなら、該当する個別ファイルドキュメントを更新してください。
