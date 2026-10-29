# modules/InstalledAppExport/internal/DomOperations.ps1

## 1. このファイルを一言でいうと

InstalledAppExport用のPowerShell Operation名と、ブラウザ上のJavaScript helper method名を対応付けるファイルです。

PowerShell側は `ClickNameCell` や `ValidateListContract` というOperation名を使います。
このファイルが、それを `window.__InstalledAppExportDomHelper.clickAssetNameCell` などのJavaScript method呼び出しに変換します。

## このファイルを変更する典型ケース

- DOM operation の `MethodName`、`Await`、`MissingHelperBehavior` が変わった場合
- JavaScript helperとの契約、戻り値、例外扱いが変わった場合
- raw Foundation DOM helper呼び出しの境界が変わった場合


## 2. このファイルが担当する範囲

- InstalledAppExport用DOM helper名を定義する
- Operation名とJavaScript method名の対応表を持つ
- helper未登録時の挙動を定義する
- DOM helper呼び出し用のパラメータを組み立てる
- 即時実行、待機実行、結果受理待ち、契約検査を共通化する

## 3. このファイルが担当しない範囲

| 担当しないこと | 担当ファイル |
|---|---|
| 業務名の画面操作関数 | `DomAdapter.ps1` |
| JavaScript helper本体 | `dom/features/installed-app-export*.js` 側 |
| DOM bundle登録 | `Foundation/internal/DomBundle.ps1` |
| 一覧走査 | `Workflow.ps1` |
| 詳細パネル操作の業務手順 | `RowAction.ps1` |

## 4. 基本となる値

```text
InstalledAppExportDomHelperName
  __InstalledAppExportDomHelper

InstalledAppExportDomMissingHelperMessage
  InstalledAppExport DOM helper is not registered
```

PowerShell側は、ブラウザ上の `window.__InstalledAppExportDomHelper` に登録されたJavaScript objectを呼び出します。

## 5. Operation対応表

| Operation | JavaScript method | 用途 |
|---|---|---|
| `DetectPageIdentity` | `detectAssetPageIdentity` | InstalledAppExport画面かどうか判定 |
| `ValidatePageContract` | `validateAssetPageContract` | 画面種別契約確認 |
| `ValidateListContract` | `validateAssetListContract` | 一覧DOM契約確認 |
| `GetListTotalCount` | `getAssetListTotalCount` | 一覧件数取得 |
| `FindRowsInfo` | `findAssetRowsInfo` | 表示行情報取得 |
| `ClickNameCell` | `clickAssetNameCell` | 端末名セルクリック |
| `GetSelectedRow` | `getSelectedAssetRow` | 選択行取得 |
| `IsDetailPanelReadyFor` | `isDetailPanelReadyFor` | 詳細パネル対象一致待ち |
| `ValidateClickedRowContext` | `validateClickedRowContext` | 行クリック後の契約確認 |
| `ClickAppTab` | `clickAppTab` | アプリタブクリック |
| `ValidateAppListContract` | `validateAppListContract` | アプリ一覧契約確認 |
| `AssertAppRadioChecked` | `assertAppRadioChecked` | ラジオボタン状態確認 |
| `GetDetailName` | `getDetailAssetName` | 詳細パネル上の端末名取得 |
| `ClickAppCsvButton` | `clickAppCsvButton` | CSV出力ボタンクリック |
| `CloseDetailPanel` | `closeDetailPanel` | 詳細パネルを閉じる |
| `IsDetailPanelClosed` | `isDetailPanelClosed` | 詳細パネルが閉じたか確認 |
| `ScrollToTop` | `scrollToTop` | 一覧先頭へスクロール |
| `ScrollDown` | `scrollDown` | 一覧下方向へスクロール |

## 6. MissingHelperBehavior の意味

DOM helperが未登録だった場合の扱いをOperationごとに変えています。

| 値 | 意味 | 使う場面 |
|---|---|---|
| `Throw` | helper未登録なら例外 | 通常の必須操作 |
| `ReturnContractFailure` | 契約失敗オブジェクトを返す | 画面契約確認・識別 |
| `ReturnValue` | 指定した値を返す | 待機条件・後始末系 |

例えば `GetListTotalCount` はhelperがなければ処理できないため `Throw` です。
一方、`DetectPageIdentity` は複数タブ探索時に使うため、即例外ではなく契約失敗として扱います。

## 7. 関数ごとの説明

## Get-InstalledAppExportDomOperationDefinition

### 何をするか

Operation名から定義情報を取得します。

### 戻り値に含まれる情報

```text
MethodName
Description
MissingHelperBehavior
ContractScope
MissingValue
HelperName
MissingHelperMessage
```

### 失敗条件

未定義のOperation名を渡すと例外になります。

### なぜ必要か

Operation名のtypoを早期に検出するためです。
定義表にない名前を黙ってJavaScript側へ渡すと、エラー箇所が分かりにくくなります。

## New-InstalledAppExportDomHelperParameters

### 何をするか

FoundationのDOM helper関数へ渡すパラメータhashtableを組み立てます。

### 入力

```text
Operation
Arguments
TimeoutSeconds
Description
MissingValue
HasMissingValueOverride
Await
```

### 出力

```text
parameters
  HelperName
  MethodName
  Arguments
  MissingHelperBehavior
  MissingHelperMessage
  TimeoutSeconds
  ContractScope
  Description
  MissingValue
  Await
```

必要なキーだけを含めたhashtableを返します。

### PowerShell文法上のポイント

戻り値はhashtableです。
呼び出し側では `@parameters` と書くことで、hashtableの各キーを名前付き引数として渡します。
これを splatting と呼びます。

## Invoke-InstalledAppExportDomOperation

### 何をするか

指定Operationを即時実行します。

内部では次を行います。

```text
New-InstalledAppExportDomHelperParameters
  ↓
Descriptionを削除
  ↓
Invoke-FoundationDomHelperMethod @parameters
```

### なぜDescriptionを削除するのか

即時実行では、待機ログ用の説明文が不要だからです。
待機系の説明は `Wait-InstalledAppExportDomOperation` などで使います。

## Wait-InstalledAppExportDomOperation

### 何をするか

指定Operationが成功状態になるまで待ちます。

内部では `Wait-FoundationDomHelperMethod` を呼びます。

### 使う場面

- 詳細パネルが対象端末名を表示するまで待つ
- 詳細パネルが閉じるまで待つ

## Wait-InstalledAppExportDomOperationResult

### 何をするか

Operationの戻り値が、指定した `AcceptResult` 条件を満たすまで待ちます。

### 使う場面

`Assert-InstalledAppExportDetailPanel` で、選択行が期待する `DataId` と `AssetName` になるまで待つ場面で使われます。

### PowerShell文法上のポイント

`AcceptResult` はscriptblockです。
戻り値を受け取り、条件を満たす場合に `$true` を返します。

## Assert-InstalledAppExportDomOperationContract

### 何をするか

Operationを実行し、DOM契約として問題がないか確認します。

内部では `Assert-FoundationDomHelperContract` を呼びます。

### 使う場面

- InstalledAppExport画面契約確認
- 端末一覧契約確認
- アプリ一覧契約確認
- クリック後の対象一致契約確認

## 8. 変更時の判断基準

### JavaScript側のmethod名を変える場合

必ずこのファイルの対応表も更新します。
PowerShell側の `DomAdapter.ps1` や `RowAction.ps1` にJavaScript method名を書いてはいけません。

### Operationを追加する場合

次の項目を明確にします。

```text
Operation名
MethodName
MissingHelperBehavior
Description
ContractScopeが必要か
MissingValueが必要か
Awaitが必要か
```

### MissingHelperBehaviorを変える場合

helper未登録時にジョブを止めるべきか、契約失敗として扱うべきか、待機条件用に値を返すべきかを確認します。

特に `Throw` を `ReturnValue` に変えると、本来止めるべき不具合を見逃す可能性があります。

## 9. 本ドキュメント内容の要点

- `DomOperations.ps1` は、Operation名とJavaScript method名の対応表である
- helper名は `__InstalledAppExportDomHelper` である
- helper未登録時の扱いはOperationごとに違う
- `@parameters` はhashtableを名前付き引数として渡すsplattingである
- `DomAdapter.ps1` はこのファイルを経由してDOM helperを呼ぶ
