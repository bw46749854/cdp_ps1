# modules/InstalledAppExport/internal/RowAction.ps1

## 1. このファイルを一言でいうと

`RowAction.ps1` は、端末一覧の「1行分」について、アプリ一覧CSVを取得する業務トランザクションを担当するファイルです。

ここでいう1行分とは、1台の端末を意味します。

処理のまとまりは次です。

```text
対象行の処理開始ログを書く
  ↓
対象端末の詳細パネルを開く
  ↓
詳細パネルが対象端末を表示していることを確認する
  ↓
アプリタブを開く
  ↓
アプリ一覧が表示されていることを確認する
  ↓
詳細パネル上の端末名が対象端末名と一致することを確認する
  ↓
CSV出力ボタンを押す
  ↓
ダウンロード完了を待つ
  ↓
CSVを端末名つきで保存先へリネームする
  ↓
成功結果オブジェクトを返す
  ↓
成功・失敗に関係なく詳細パネルを閉じる
```

## このファイルを変更する典型ケース

- 対応する source file の責務が変わった場合
- 関数の入力、出力、戻り値、重要な分岐が変わった場合
- 呼び出し元または依存先との境界が変わった場合


## 2. このファイルが担当する範囲

このファイルが担当するのは、端末一覧の1行に対する一連の操作です。

具体的には次です。

- 行処理の開始ログ
- 詳細パネルを開く
- 詳細パネルの表示確認
- アプリタブを開く
- アプリ一覧の表示確認
- アプリCSVの出力操作
- ダウンロード待ち
- CSVリネーム
- 成功結果オブジェクト作成
- 最後の詳細パネルcleanup

このファイルは、単なる小さなユーティリティ集ではありません。1台分のCSV取得を「途中で画面状態を汚さず完了させる」ためのまとまりです。

## 3. このファイルが担当しない範囲

担当しないものは次です。

- 端末一覧全体を何件走査するか
- スクロールして次の表示行を探す方法
- 既に処理済みの行をスキップするかどうか
- InstalledAppExportジョブ全体の開始・終了
- 出力結果CSVの集計
- DOM selectorの詳細
- raw CDP呼び出し
- raw DOM helper呼び出し
- ダウンロード待ちの内部実装
- ファイル名として危険な文字のsanitize詳細

一覧全体の走査は `Workflow.ps1` や `ScrollableList` 側の責務です。

DOMの具体操作は `DomAdapter.ps1` と `DomOperations.ps1`、ブラウザ内JavaScriptの責務です。

ダウンロード待ちやリネームの詳細は `Download.ps1` の責務です。

## 4. このファイルが必要になる実行シナリオ

InstalledAppExportジョブは、画面上の端末一覧を読み、各端末についてアプリCSVを出力します。

一覧に次のような端末があるとします。

```text
row-1  PC-001
row-2  PC-002
row-3  PC-003
```

`RowAction.ps1` は、そのうち1件を処理します。

```text
Invoke-InstalledAppExportCsvForRow
  DataId       = row-1
  AssetName = PC-001
```

この1件の処理が成功すると、次のような結果が返ります。

```text
InstalledAppExportProcessResult
  DataId       = row-1
  AssetName = PC-001
  CsvPath      = C:\out\asset\PC-001.csv
```

失敗した場合は、上位のWorkflow側で失敗結果へ変換されます。このファイル自身は、失敗を握りつぶして成功扱いにはしません。

## 5. このファイル内の関数呼び出しツリー

主入口は `Invoke-InstalledAppExportCsvForRow` です。

```text
Invoke-InstalledAppExportCsvForRow
│
├─ try
│  │
│  ├─ Start-InstalledAppExportCsvRow
│  │    └─ 行処理開始ログを書く
│  │
│  ├─ Open-InstalledAppExportCsvDetail
│  │  │
│  │  ├─ Open-InstalledAppExportDetailPanel
│  │  │    └─ DomAdapter経由で詳細パネルを開く
│  │  │
│  │  ├─ Assert-InstalledAppExportDetailPanel
│  │  │    └─ 詳細パネルが対象端末を表示しているか確認
│  │  │
│  │  └─ Write-FoundationLog
│  │       └─ 確認完了ログ
│  │
│  ├─ Open-InstalledAppExportCsvList
│  │  │
│  │  ├─ Open-InstalledAppExportAppTab
│  │  │    └─ アプリタブを開く
│  │  │
│  │  ├─ Assert-InstalledAppExportAppList
│  │  │    └─ アプリ一覧表示を確認
│  │  │
│  │  └─ Assert-InstalledAppExportAppRadioChecked
│  │       └─ アプリ一覧側のラジオ状態を確認
│  │
│  ├─ Assert-InstalledAppExportCsvTarget
│  │  │
│  │  ├─ Get-InstalledAppExportDetailName
│  │  │    └─ 詳細パネル上の端末名を取得
│  │  │
│  │  └─ 期待端末名と不一致なら throw
│  │
│  ├─ Invoke-InstalledAppExportAppCsvDownload
│  │  │
│  │  ├─ Context.Services.FileSystem.ClearDirectory.Invoke
│  │  │    └─ 一時ダウンロードディレクトリを空にする
│  │  │
│  │  ├─ Click-InstalledAppExportAppCsvButton
│  │  │    └─ CSV出力ボタンをクリック
│  │  │
│  │  ├─ Wait-InstalledAppExportDownloadedCsv
│  │  │    └─ CSVダウンロード完了と安定を待つ
│  │  │
│  │  └─ Rename-InstalledAppExportDownloadedCsv
│  │       └─ 端末名つきで保存先へ移動/リネーム
│  │
│  └─ Complete-InstalledAppExportCsvResult
│       └─ New-InstalledAppExportProcessResultを作る
│
└─ finally
   └─ Close-InstalledAppExportDetailPanelSafely
      │
      ├─ Close-InstalledAppExportDetailPanel
      │    └─ 詳細パネルを閉じる
      │
      ├─ Wait-InstalledAppExportDetailPanelClosed
      │    └─ 閉じたことを短時間待つ
      │
      └─ 失敗してもWarningログにしてcleanupを終える
```

## 6. このファイルの処理を業務の言葉で読む

`Invoke-InstalledAppExportCsvForRow` は、単なる「CSVをダウンロードする関数」ではありません。

この関数の本質は、「画面上の現在の対象が本当に目的の端末であることを何度も確認してからCSVを出す」ことです。

確認が多い理由は、ブラウザ自動操作が画面状態に依存するためです。

```text
一覧でPC-001をクリックしたつもり
  ↓
詳細パネルが開く
  ↓
本当にPC-001の詳細なのか確認
  ↓
アプリタブを開く
  ↓
本当にアプリ一覧が表示されているか確認
  ↓
CSVを出す直前に、詳細パネルの端末名がPC-001か再確認
```

この確認がないと、次のような事故が起きる可能性があります。

```text
PC-001のCSVとして保存したファイルの中身が、実はPC-002だった
```

そのため、このファイルではクリックよりも確認が重要です。

## 7. 扱うデータの形

### 入力: 行識別情報

`Invoke-InstalledAppExportCsvForRow` は、次の3つを受け取ります。

```text
Context      : 実行中の設定・logger・servicesを含む箱
DataId       : 画面上の行を識別するID
AssetName : 対象端末名
```

`DataId` は画面上のDOM行に紐づく識別子です。`AssetName` は人間が読む端末名です。

両方が必要です。

| 値 | 使い道 |
|---|---|
| `DataId` | DOM側でどの行を開くかを特定する |
| `AssetName` | ログ、詳細パネル一致確認、CSVファイル名に使う |

### 出力: 成功結果

成功時は `New-InstalledAppExportProcessResult` で作られた結果を返します。

```text
InstalledAppExportProcessResult
  DataId       : 処理した行ID
  AssetName : 処理した端末名
  CsvPath      : リネーム後CSVのフルパス
```

この結果は、InstalledAppExportジョブ全体の成功結果リストに追加されます。

### 中間値: `$renamedCsv`

`Invoke-InstalledAppExportAppCsvDownload` は、リネーム後のCSVファイルを表す `FileInfo` を返します。

そのため、次のように `.FullName` を使います。

```text
$RenamedCsv.FullName
```

`FullName` は、ファイルの絶対パスです。

## 8. 関数ごとの説明

## Close-InstalledAppExportDetailPanelSafely

### 何をするか

右側詳細パネルを閉じ、閉じたことを確認します。

この関数はcleanup専用です。失敗しても、原則としてWarningログに留めます。

### なぜ必要か

端末一覧では、1台分の処理が終わったら詳細パネルを閉じる必要があります。

詳細パネルが開いたまま次の端末処理に進むと、次の処理が前の端末の画面状態に影響される可能性があります。

### 入力

| 引数 | 意味 |
|---|---|
| `Context` | loggerとJobSettingsを使うため |

`Context.JobSettings.DetailPanelCloseWaitSeconds` を使って、閉じたことを待つ秒数を決めます。

### 出力

明示的な成功結果は返しません。

### 副作用

- 画面上の詳細パネルを閉じる
- 閉じたことを待つ
- ログを書く

### 失敗条件と扱い

| 失敗 | 扱い |
|---|---|
| `Close-InstalledAppExportDetailPanel` が `ok != true` を返す | Warningログを書いてreturn |
| close後に非表示確認できない | Warningログを書く |
| cleanup処理自体が例外を投げる | Warningログを書く |

この関数は「安全に閉じる」ための関数なので、cleanupの失敗で本来のエラーを上書きしない設計です。

### PowerShell文法上のポイント

#### 内側と外側の `try/catch`

この関数には、外側の `try/catch` と内側の `try/catch` があります。

```text
外側のtry/catch
  Close-InstalledAppExportDetailPanel 自体の失敗をWarning化する

内側のtry/catch
  close後の Wait-InstalledAppExportDetailPanelClosed 失敗をWarning化する
```

cleanupは後始末なので、ここで発生した例外を強く投げ直すと、元の失敗原因が見えにくくなります。

## Start-InstalledAppExportCsvRow

### 何をするか

1行分の処理開始をログに出します。

### 入力

| 引数 | 意味 |
|---|---|
| `Context` | loggerを使うため |
| `DataId` | 行IDをログに出すため |
| `AssetName` | 端末名をログに出すため |

### 出力

なし。

### 副作用

ログを書きます。

### 変更時の注意

この関数は業務処理を進めません。ログだけです。

ここにDOM操作やCSV処理を追加すると、関数名と責務がずれます。

## Open-InstalledAppExportCsvDetail

### 何をするか

対象端末の詳細パネルを開き、その詳細パネルが対象端末のものであることを確認します。

### 入力

| 引数 | 意味 |
|---|---|
| `Context` | loggerを使うため |
| `DataId` | 開く対象行を特定するため |
| `AssetName` | 詳細パネルが対象端末か確認するため |

### 呼び出す関数

```text
Open-InstalledAppExportDetailPanel
Assert-InstalledAppExportDetailPanel
Write-FoundationLog
```

### 副作用

- ブラウザ画面上で詳細パネルを開く
- ログを書く

### 失敗条件

- 対象行を開けない
- 詳細パネルが表示されない
- 表示された詳細パネルが期待した端末ではない

失敗した場合、この関数内では握りつぶさず、上位へ例外が伝わります。

### PowerShell文法上のポイント

```powershell
Assert-InstalledAppExportDetailPanel ... | Out-Null
```

戻り値は使いません。重要なのは、Assertが成功することです。失敗すれば例外になります。

## Open-InstalledAppExportCsvList

### 何をするか

詳細パネル内のアプリタブを開き、アプリ一覧がCSV出力可能な状態であることを確認します。

### 呼び出す関数

```text
Open-InstalledAppExportAppTab
Assert-InstalledAppExportAppList
Assert-InstalledAppExportAppRadioChecked
```

### 副作用

- ブラウザ画面上でアプリタブを開く
- 画面状態を確認する
- DOM操作結果をログに出す

### 失敗条件

- アプリタブが開けない
- アプリ一覧が表示されない
- アプリ一覧のラジオ状態が期待と違う

## Assert-InstalledAppExportCsvTarget

### 何をするか

CSV出力直前に、詳細パネル上の端末名が処理対象の `AssetName` と一致するか確認します。

### なぜ必要か

画面操作は非同期で、クリックやタブ切り替えの後に画面状態が変わることがあります。

CSV出力直前に端末名を再確認することで、誤った端末のCSVを保存する事故を防ぎます。

### 入力

| 引数 | 意味 |
|---|---|
| `Context` | 現在は直接使っていないが、RowAction内の関数シグネチャを揃えるために受け取っている |
| `AssetName` | 期待する端末名 |

### 出力

なし。

### 失敗条件

`Get-InstalledAppExportDetailName` で取得した端末名が `AssetName` と一致しない場合、`throw` します。

エラーメッセージには期待値と実際値が入ります。

```text
expected=PC-001 actual=PC-002
```

### 変更時の注意

この関数を削除すると、誤端末CSV保存の防御が1つ消えます。

単に「すでに `Assert-InstalledAppExportDetailPanel` しているから不要」と判断しないでください。`Assert-InstalledAppExportDetailPanel` は詳細パネルを開いた直後の確認です。この関数はCSV出力直前の再確認です。

## Invoke-InstalledAppExportAppCsvDownload

### 何をするか

CSV出力ボタンを押し、ダウンロードされたCSVを保存先へリネームします。

### 処理の順序

```text
JobSettingsを取得
  ↓
CSV出力開始ログを書く
  ↓
一時ダウンロードディレクトリを空にする
  ↓
CSV出力ボタンをクリック
  ↓
CSVダウンロード完了と安定を待つ
  ↓
AssetNameを使って保存先へリネーム
  ↓
リネーム後パスをログに出す
  ↓
リネーム後のFileInfoを返す
```

### 入力

| 引数 | 意味 |
|---|---|
| `Context` | JobSettings、logger、FileSystem serviceを使うため |
| `AssetName` | リネーム後ファイル名に使うため |

### 使用する設定

```text
Context.JobSettings.TempDirectory
Context.JobSettings.DownloadFilePrefix
Context.JobSettings.DownloadTimeoutSeconds
Context.JobSettings.DownloadStableSeconds
Context.JobSettings.DownloadDirectory
```

### 副作用

- 一時ディレクトリを空にする
- 画面上のCSV出力ボタンをクリックする
- ダウンロードファイルを待つ
- ファイルを保存先へリネーム/移動する
- ログを書く

### 失敗条件

- 一時ディレクトリを安全に空にできない
- CSV出力ボタンをクリックできない
- タイムアウト内にCSVがダウンロードされない
- ダウンロード中ファイルが安定しない
- リネーム先に移動できない

### PowerShell文法上のポイント

```powershell
$Context.Services.FileSystem.ClearDirectory.Invoke(...)
```

`ClearDirectory` はscriptblockです。`.Invoke(...)` により、その処理を実行しています。

この設計により、テストでは本物のディレクトリ削除ではなく、ダミーのscriptblockへ差し替えられます。

## Complete-InstalledAppExportCsvResult

### 何をするか

成功結果オブジェクトを作ります。

### 入力

| 引数 | 意味 |
|---|---|
| `DataId` | 処理した行ID |
| `AssetName` | 処理した端末名 |
| `RenamedCsv` | リネーム後CSVファイル |

### 出力

`New-InstalledAppExportProcessResult` が作る結果オブジェクトです。

```text
DataId
AssetName
CsvPath
```

### 変更時の注意

この関数は、結果の形を `Models.ps1` に委譲しています。

ここで独自の `[pscustomobject]` を直接作り始めると、結果オブジェクトの形が複数箇所に分散します。

## Invoke-InstalledAppExportCsvForRow

### 何をするか

1台分のCSV取得処理を最初から最後まで実行します。

このファイルの主関数です。

### 入力

| 引数 | 意味 |
|---|---|
| `Context` | 設定、logger、servicesを使うため |
| `DataId` | 処理する画面行ID |
| `AssetName` | 処理する端末名 |

### 出力

成功時は `InstalledAppExportProcessResult` を返します。

### 副作用

- ブラウザ画面を操作する
- CSVをダウンロードする
- ファイルをリネームする
- ログを書く
- 最後に詳細パネルを閉じる

### 失敗条件

途中のどこかで失敗すると、この関数は失敗します。

ただし、失敗しても `finally` により `Close-InstalledAppExportDetailPanelSafely` は実行されます。

### PowerShell文法上のポイント

#### `try/finally`

```text
try
  1台分の処理本体

finally
  詳細パネルcleanup
```

`finally` は成功しても失敗しても実行されます。

この関数では、CSV取得の途中で失敗しても、右側詳細パネルを閉じる必要があります。

この `finally` を削除すると、次の端末処理に前の詳細パネル状態が残る可能性があります。

## 9. このファイルが大きめでも残す理由

`RowAction.ps1` は、複数ステップを持つため、一見するとさらに細かく分割したくなります。

しかし、このファイルは「1台分のCSV取得」という1つの業務トランザクションです。

このまとまりを分解しすぎると、次の問題が起きます。

```text
どこで詳細パネルを開いたのか分からない
どこで端末名を確認したのか分からない
どこでCSVを押したのか分からない
失敗時にどこで閉じるのか分からない
```

このファイルでは、1台分の流れを上から順に読めることが重要です。

したがって、行処理の順序が見える現在のまとまりには価値があります。

## 10. このファイルを変更するときの判断基準

### 変更してよい可能性があるもの

- ログ文言の改善
- エラーメッセージに診断情報を追加する
- CSV出力前の確認を追加する
- cleanup時のWarning内容を改善する

### 慎重に扱うべきもの

| 箇所 | 理由 |
|---|---|
| `Assert-InstalledAppExportCsvTarget` | 誤端末CSV保存を防ぐ直前確認だから |
| `Invoke-InstalledAppExportAppCsvDownload` のClearDirectory | 前回ダウンロードファイルを誤検知しないため |
| `Wait-InstalledAppExportDownloadedCsv` | ダウンロード完了前にリネームしないため |
| `Rename-InstalledAppExportDownloadedCsv` | 後続のLastMonthInstallExtract処理が端末名つきファイルを前提にするため |
| `finally` | 失敗時にも詳細パネルを閉じるため |

### やってはいけない変更

- DOM selectorをこのファイルに直接書く
- `Invoke-InstalledAppExportDomOperation` や `Wait-InstalledAppExportDomOperation` をこのファイルから直接呼ぶ
- raw CDP関数をこのファイルから呼ぶ
- `Get-ChildItem`, `Move-Item`, `Remove-Item` などのraw file I/Oをこのファイルに直接書く
- `Start-Sleep` をこのファイルに直接書く
- CSVファイルの内部形式をこのファイルで解析する

このファイルは、業務トランザクションの順序を持ちますが、低レベル実装の置き場所ではありません。

## 11. 関連するテスト観点

このファイルに関係するテスト観点は次です。

| 観点 | 内容 |
|---|---|
| cleanup | 詳細パネルclose後に `Wait-InstalledAppExportDetailPanelClosed` を呼ぶこと |
| Adapter境界 | `RowAction.ps1` がDomOperationsを直接呼ばないこと |
| 行処理順序 | OpenDetail → AssertDetail → OpenAppTab → AssertAppList → AssertRadio → GetDetailName → ClearTemp → ClickCsv → WaitDownload → RenameCsv → Cleanup の順序 |
| 結果形 | `DataId`, `AssetName`, `CsvPath` が返ること |
| Architecture | `RowAction.ps1` は業務トランザクションとして例外的にまとまりを持てるが、低レベル実装は持たないこと |

このファイルを変更した場合、失敗する可能性が高いのは次の種類のテストです。

```text
InstalledAppExport.Workflow.Rows.Tests.ps1
InstalledAppExport.BrowserBoundary.Tests.ps1
InstalledAppExport.Download.Tests.ps1
Architecture.Tests.ps1
```

## 12. 本ドキュメント内容の要点

このファイルを読んだ後は、次を説明できる状態になっているべきです。

```text
RowAction.ps1 が1台分のCSV取得を担当していること
Invoke-InstalledAppExportCsvForRow の処理順序
詳細パネル確認が複数回ある理由
CSV出力前に端末名を再確認する理由
一時ダウンロードディレクトリを空にする理由
finally で詳細パネルを閉じる理由
cleanup失敗をWarningに留める理由
RowAction.ps1にDOM selectorやraw CDPを書いてはいけない理由
大きめのファイルでも、業務トランザクションとしてまとまっているなら残す価値があること
```
