# ScanTargetSync internal/Dependencies.ps1

## この文書の位置づけ

この文書は `main/modules/ScanTargetSync/internal/Dependencies.ps1` の個別ファイルドキュメントです。
`ScanTargetSync` Workflow が使う外部依存を、テストで差し替え可能な port として組み立てる境界を説明します。

## このファイルを変更する典型ケース

- 依存port、callback名、既定実装の作り方が変わった場合
- Workflow / Runner が使う外部I/Oの差し替え境界が変わった場合
- 依存検証の粒度や必須callbackが変わった場合


## このファイルの責務

`Dependencies.ps1` は業務判断を持ちません。
責務は次に限定します。

```text
Context / 既存Dependenciesから必要なcallbackを取り出す
不足している上位portを既定実装で補う
callbackがscriptblockか検証する
処理入口ごとに必要な依存だけを粒度別に検証する
Feature-localなDOM / endpoint操作の副作用境界を作る
```

このファイルは、`Workflow*.ps1` が raw CDP、raw DOM helper、file system、時刻、ログ出力へ直接依存しないための境界です。

## port の構成

`Resolve-ScanTargetSyncWorkflowDependencies` が返す依存オブジェクトは、次の上位portを持ちます。

| port | 主なcallback | 役割 |
|---|---|---|
| `Browser` | `OpenPageMatchingIdentity` | 対象ページの識別条件に合うブラウザページを開く |
| `FileSystem` | `InitializeOutputDirectory`, `TestPathUnderDirectory`, `RemoveFileIfExists` | 出力ディレクトリ準備、パス検証、安全なファイル削除 |
| `Logger` | `WriteInfo`, `WriteWarning`, `WriteSection` | Workflowから使うログ出力境界 |
| `Timing` | `TimestampText` | 実行時刻文字列の取得。テストで固定できる |
| `Dom` | `RegisterAdapter`, `AssertPage`, `GetVisibleRows`, `ScrollDown` など | ScanTargetSync Feature内DOM操作の業務名境界 |
| `EndpointAction` | `SetDesiredState`, `TestFoundationFatalError` | endpoint単位のチェック同期と致命的自動化エラー判定 |

## callback 検証の考え方

このファイルでは、callbackが存在するかだけでなく、`scriptblock` かどうかを検証します。

| 関数 | 役割 |
|---|---|
| `Get-ScanTargetSyncDependencyProperty` | `pscustomobject` などから安全にプロパティを取り出す |
| `Get-ScanTargetSyncCallbackScriptBlock` | 指定callbackが `scriptblock` でなければ例外にする |
| `Test-ScanTargetSyncCallbackScriptBlock` | 指定callbackが `scriptblock` か真偽値で返す |
| `Assert-ScanTargetSyncCallbackGroup` | 必須callback群を一括検証する |
| `Test-ScanTargetSyncCallbackGroup` | 必須callback群が揃っているか真偽値で返す |
| `Get-ScanTargetSyncDependencyCommand` | Foundation moduleやFeature-local関数を `Get-Command` で解決し、既定portを作るための `CommandInfo` を取得する |

この検証により、テストが不完全な依存オブジェクトを渡した場合でも、Workflowの途中で曖昧に失敗せず、入口で契約違反として検出できます。

## 既定portの構築

既定portは、`Context.Services` に既に有効なcallbackがある場合はそれを優先します。
不足している場合だけ、Foundation moduleやFeature-local関数を `Get-Command` で解決し、`CommandInfo` をclosureに閉じ込めます。

| 関数 | 構築するport | 補足 |
|---|---|---|
| `New-ScanTargetSyncLoggerPort` | `Logger` | `Write-FoundationLog` / `Write-FoundationSection` をcallback化する |
| `New-ScanTargetSyncBrowserPort` | `Browser` | `Open-FoundationPage*` と download directory 設定をcallback化する |
| `New-ScanTargetSyncFileSystemPort` | `FileSystem` | 出力ディレクトリ初期化、パス検証、安全削除をcallback化する |
| `New-ScanTargetSyncTimingPort` | `Timing` | `Get-Date` をここに閉じる。Workflowは直接呼ばない |
| `New-ScanTargetSyncDomPort` | `Dom` | `DomAdapter.ps1` の業務名関数をcallback化する |
| `New-ScanTargetSyncEndpointActionCallbacks` | `EndpointAction` | checkbox変更と致命的エラー判定の副作用境界を作る |

`New-ScanTargetSyncDomPort` は、DOM helperを直接呼びません。
Feature-localな `DomAdapter.ps1` の関数をcallback化します。
raw Foundation DOM helper呼び出しは `DomOperations.ps1` に閉じ込めます。

## Page identity matcher

`New-ScanTargetSyncPageIdentityMatcher` は、`Browser.OpenPageMatchingIdentity` へ渡すmatcherを作ります。
matcherの中では `Dependencies.Dom.TestPageIdentity` を呼びます。

これにより、ページ探索は Foundation 側で行い、ScanTargetSync固有の画面識別はFeature側のDOM契約で判定できます。

## 依存検証の粒度

このファイルは、すべての依存を常に一括検証するだけではありません。
処理入口ごとに必要なcallbackだけを検証する関数を持ちます。

| 検証関数 | 検証対象 | 主な利用意図 |
|---|---|---|
| `Assert-ScanTargetSyncBrowserDependencies` | `Browser.OpenPageMatchingIdentity` | ページを開く前 |
| `Assert-ScanTargetSyncFileSystemDependencies` | 指定されたFileSystem callback | 出力準備・削除・パス検証前 |
| `Assert-ScanTargetSyncLoggerDependencies` | Logger callback群 | ログ出力前 |
| `Assert-ScanTargetSyncPageDependencies` | Browser + page系DOM callback | ページ識別・契約確認前 |
| `Assert-ScanTargetSyncPostSelectionDependencies` | `Dom.AssertPostSelectionContract` | チェック後の画面契約確認前 |
| `Assert-ScanTargetSyncUiScanDependencies` | `Dom.GetVisibleRows` | UI走査で可視行を読む前 |
| `Assert-ScanTargetSyncUiScanCursorDependencies` | `Dom.ScrollDown` | スクロールで走査位置を進める前 |
| `Assert-ScanTargetSyncEndpointActionDependencies` | endpoint action callback群 | endpoint単位のチェック同期前 |
| `Assert-ScanTargetSyncWorkflowInitializationDependencies` | 出力ディレクトリ初期化 | Workflow初期化前 |
| `Assert-ScanTargetSyncTimingDependencies` | `Timing.TimestampText` | timestamp生成前 |
| `Assert-ScanTargetSyncWorkflowDependencies` | Workflow全体 | 本番実行の全体契約確認 |

この粒度分割により、テストは対象処理に必要な依存だけを渡せます。
すべてのテストが巨大なmockを作る必要はありません。

## `Resolve-ScanTargetSyncWorkflowDependencies` の契約

`Resolve-ScanTargetSyncWorkflowDependencies` は、渡された `$Dependencies` を尊重し、不足している上位portだけを補います。

重要な点は次です。

- `$Dependencies` が `$null` の場合は空オブジェクトとして扱う。
- `Browser`, `FileSystem`, `Dom`, `EndpointAction` はport自体が無ければ既定実装を作る。
- `Logger`, `Timing` は必要callbackが揃っていなければ既定実装を作る。
- Resolve段階では不足する上位portを補うだけにし、各処理が必要とするcallback詳細は処理入口で検証する。

## ここに書かないこと

`Dependencies.ps1` に次を追加してはいけません。

- CSVの業務判定
- endpointがON対象かOFF対象かの判断
- DOM selectorやJavaScript method名の直接管理
- UI走査のループ制御
- 結果CSVの行構造
- `Invoke-FoundationDomHelperMethod` の直接呼び出し

これらはそれぞれ `CsvInput`, `Rules`, `Reconciliation`, `Workflow*.ps1`, `DomOperations`, `Output` の責務です。

## 変更時に見るテスト

- `main/tests/ScanTargetSync.Dependencies.Tests.ps1`
- `main/tests/ScanTargetSync.BrowserBoundary.Tests.ps1`
- `main/tests/ScanTargetSync.FileSystemBoundary.Tests.ps1`
- `main/tests/Architecture.Tests.ps1`

## 更新条件

この文書は、portの構成、callback名、検証粒度、既定依存の構築方針が変わった場合に更新します。
単なるテストデータの追加やログ文言の変更だけでは更新不要です。
