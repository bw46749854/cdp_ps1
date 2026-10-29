# modules/InstalledAppExport/internal/DomAdapter.ps1

## 1. このファイルを一言でいうと

InstalledAppExportジョブ内のPowerShell処理から、画面操作を業務名の関数として呼べるようにする窓口です。

`DomOperations.ps1` が「Operation名とJavaScript helper method名の対応表」を持つのに対し、`DomAdapter.ps1` は `Assert-InstalledAppExportPage` や `Open-InstalledAppExportDetailPanel` のような、処理側が読みやすい関数名を提供します。

## このファイルを変更する典型ケース

- Workflowから呼ぶ画面操作の業務名が変わった場合
- DomOperationsへ渡す引数や戻り値の形が変わった場合
- DOM操作失敗時の扱いをFeature内で変える場合


## 2. このファイルが担当する範囲

- DOM bundleを登録する
- InstalledAppExport画面であることを確認する
- 端末一覧であることを確認する
- 表示中の行情報を取得する
- 行クリックで詳細パネルを開く
- 詳細パネルが対象端末を表示していることを確認する
- アプリタブを開く
- アプリ一覧契約を確認する
- CSV出力ボタンを押す
- 詳細パネルを閉じる
- 一覧を先頭へ戻す、下へスクロールする

## 3. このファイルが担当しない範囲

| 担当しないこと | 担当ファイル |
|---|---|
| JavaScript method名の対応表 | `DomOperations.ps1` |
| ダウンロード完了待ち | `Download.ps1` |
| 1行分の業務手順全体 | `RowAction.ps1` |
| 一覧全体の走査 | `Workflow.ps1` |
| DOM helperの低レベル呼び出し | `Foundation/internal/DomHelper.ps1` |

## 4. DomAdapterとDomOperationsの違い

```text
RowAction.ps1 / Runner.ps1 / Workflow.ps1
  ↓
DomAdapter.ps1
  ↓
DomOperations.ps1
  ↓
Foundation DomHelper
  ↓
JavaScript DOM helper
```

`DomAdapter.ps1` は、呼び出し元から見た業務名を提供します。
`DomOperations.ps1` は、その業務名の裏でどのJavaScript methodを呼ぶかを定義します。

## 5. 主な関数の呼び出し関係

```text
Assert-InstalledAppExportInitialPageContract
  ├─ Register-InstalledAppExportDomAdapter
  ├─ Assert-InstalledAppExportPage
  └─ Assert-InstalledAppExportList

Workflowの一覧走査
  ├─ Get-VisibleAssetRows
  ├─ Scroll-InstalledAppExportListDown
  └─ Get-InstalledAppExportRowKey は Models.ps1

RowActionの1行処理
  ├─ Open-InstalledAppExportDetailPanel
  ├─ Assert-InstalledAppExportDetailPanel
  ├─ Open-InstalledAppExportAppTab
  ├─ Assert-InstalledAppExportAppList
  ├─ Assert-InstalledAppExportAppRadioChecked
  ├─ Get-InstalledAppExportDetailName
  ├─ Click-InstalledAppExportAppCsvButton
  └─ Close-InstalledAppExportDetailPanel / Wait-InstalledAppExportDetailPanelClosed
```

## 6. 関数ごとの説明

## Register-InstalledAppExportDomAdapter

### 何をするか

`Register-FoundationDomBundle` を呼び、InstalledAppExport用DOM JavaScriptをブラウザへ登録します。

### なぜ必要か

PowerShell側のDOM操作は、ブラウザ上のJavaScript helperを呼びます。
そのhelperが登録されていなければ、`window.__InstalledAppExportDomHelper` の各methodを呼べません。

## Assert-InstalledAppExportPage

### 何をするか

InstalledAppExport画面として必要なDOM契約を確認します。

内部では `ValidatePageContract` operationを実行します。

### 失敗条件

- InstalledAppExport画面ではない
- 必要な画面要素がない
- DOM helperが登録されていない

## Assert-InstalledAppExportList

### 何をするか

端末一覧として必要なDOM契約を確認します。

内部では `ValidateListContract` operationを実行します。

### なぜ必要か

一覧件数取得や行情報取得の前提になるためです。
一覧DOMが壊れている状態で処理を続けると、誤った行をクリックする可能性があります。

## Get-InstalledAppExportListTotalCount

### 何をするか

端末一覧の総件数を取得します。

### 呼び出し元

`Runner.ps1` の `Get-InstalledAppExportInitialTotalCount` から呼ばれます。

## Test-InstalledAppExportPageIdentity

### 何をするか

現在のブラウザタブがInstalledAppExport画面かどうかを判定します。

### 戻り値の形

```text
PageIdentityResult
  Matched : InstalledAppExport画面ならtrue
  Reason  : 判定理由
  Result  : DOM helperの生結果
```

### なぜ必要か

複数タブが開いている場合に、誤ったタブを操作しないためです。

### 補足

`DetectPageIdentity` の結果に `fatalCount` があれば、理由文に含めます。
これにより、単なる不一致なのか、DOM契約上の致命的問題なのかを追いやすくしています。

## Get-VisibleAssetRows

### 何をするか

現在画面に表示されている端末行情報を配列として取得します。

### 戻り値の想定

```text
rowInfo[]
  dataId
  assetName
```

### 呼び出し元

`Dependencies.ps1` の `New-InstalledAppExportListTraversalCallbacks` 経由で、共通基盤の一覧走査から呼ばれます。

## Open-InstalledAppExportDetailPanel

### 何をするか

指定した `DataId` と `AssetName` の行をクリックし、右側詳細パネルを開きます。

### 入力

```text
DataId       : 行ID
AssetName : 端末名
```

### 変更時の注意

`AssetName` だけでクリック対象を決めると、同名や似た名前の行で誤操作する可能性があります。
`DataId` と `AssetName` を両方渡している点が重要です。

## Assert-InstalledAppExportDetailPanel

### 何をするか

行クリック後、詳細パネルが本当に対象端末を表示しているか確認します。

### 処理順序

```text
GetSelectedRow が期待DataId / AssetNameになるまで待つ
  ↓
IsDetailPanelReadyFor が true になるまで待つ
  ↓
ValidateClickedRowContext で契約確認する
```

### なぜ複数段階で確認するのか

画面クリック後、DOM更新には時間がかかります。
すぐに契約確認だけをすると、まだ更新中の状態を誤って失敗扱いする可能性があります。
そのため、選択行一致、詳細パネル準備完了、最終契約確認の順で待ちます。

### PowerShell文法上のポイント

`$selectedRowMatches` はscriptblockです。
その中で外側の `$expectedDataId` と `$expectedAssetName` を使うため、`.GetNewClosure()` を付けています。

## Open-InstalledAppExportAppTab

### 何をするか

詳細パネル内のアプリタブをクリックします。

## Assert-InstalledAppExportAppList

### 何をするか

アプリ一覧のDOM契約を確認します。

### なぜ必要か

CSVボタンを押す前に、アプリ一覧が正しく表示されていることを保証するためです。

## Assert-InstalledAppExportAppRadioChecked

### 何をするか

アプリ一覧側で必要なラジオボタン選択状態を確認します。

### 注意

この関数名は `Assert` ですが、内部的には `Invoke-InstalledAppExportDomOperation` を呼びます。
JavaScript helper側で条件を満たさなければ例外または契約失敗になります。

## Get-InstalledAppExportDetailName

### 何をするか

詳細パネル上に表示されている端末名を取得します。

### 呼び出し元

`RowAction.ps1` の対象確認で使われます。

## Click-InstalledAppExportAppCsvButton

### 何をするか

アプリ一覧CSVを出力するボタンをクリックします。

### 注意

この関数はクリックするだけです。
ダウンロード完了待ちは `Download.ps1` の担当です。

## Close-InstalledAppExportDetailPanel

### 何をするか

右側詳細パネルを閉じます。

### MissingValueの扱い

helper未登録時の戻り値として、warning扱いの契約失敗オブジェクトを用意しています。
詳細パネルを閉じる処理は後始末で呼ばれるため、致命的に落とすよりも、呼び出し側で安全に扱える結果にしています。

## Wait-InstalledAppExportDetailPanelClosed

### 何をするか

詳細パネルが閉じた状態になるまで短時間待ちます。

### なぜ必要か

閉じるクリック直後に次の行を処理すると、前のパネルがまだ残っている可能性があります。
次の行処理へ画面状態を持ち越さないために確認します。

## Scroll-InstalledAppExportListToTop

### 何をするか

端末一覧のスクロール位置を先頭へ戻します。

## Scroll-InstalledAppExportListDown

### 何をするか

端末一覧を下方向へスクロールします。

### 呼び出し元

共通基盤の `Invoke-ScrollableListWorkflow` が、`Dependencies.ps1` 経由で呼びます。

## 7. 変更時の判断基準

- このファイルにJavaScript method名を直接増やす前に、`DomOperations.ps1` のoperation定義を確認する
- `Assert` 系関数を削ると、画面構造変更に気づくのが遅くなる
- クリック後の待機を短絡すると、非同期DOM更新中の不安定な失敗が増える
- ダウンロード待ちをこのファイルへ入れない

## 8. 本ドキュメント内容の要点

- `DomAdapter.ps1` は、画面操作を業務名の関数として提供する
- 実際のJavaScript method名は `DomOperations.ps1` に閉じ込められている
- Runner、Workflow、RowActionは、このファイル経由で画面操作を行う
- 詳細パネル操作では、クリック後の対象一致確認が重要である
