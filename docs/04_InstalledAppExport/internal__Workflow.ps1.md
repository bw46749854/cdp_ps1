# modules/InstalledAppExport/internal/Workflow.ps1

## 1. このファイルを一言でいうと

端末一覧全体を走査し、表示された各行に対して1行分のCSV取得処理を実行するファイルです。

`Workflow.ps1` は、一覧全体の進行管理を担当します。
詳細パネルを開く、アプリタブを押す、CSVボタンを押す、といった1行分の具体的な画面操作は `RowAction.ps1` に委譲します。

## このファイルを変更する典型ケース

- 処理順序、分岐、リトライ、失敗時の継続方針が変わった場合
- Policy判定結果と依存portのつなぎ方が変わった場合
- Workflowが集約する結果や後続処理への渡し方が変わった場合


## 2. このファイルが担当する範囲

このファイルの担当は次です。

- 一覧全体を走査するための操作セットを作る
- 各行を処理する `ProcessRow` callback を作る
- 成功結果と失敗結果を集約する
- 共通基盤の `Invoke-ScrollableListWorkflow` を呼び出す
- 最終的なWorkflowResultを返す

## 3. このファイルが担当しない範囲

| 担当しないこと | 担当ファイル |
|---|---|
| InstalledAppExport画面に接続する | `Runner.ps1` |
| 詳細パネルを開いてCSVを出す | `RowAction.ps1` |
| DOM method名を決める | `DomOperations.ps1` |
| DOM操作を業務名で包む | `DomAdapter.ps1` |
| ダウンロード完了を待つ | `Download.ps1` |
| 失敗CSVを書き出す | `Output.ps1` |

## 4. このファイル内の処理の流れ

```text
Invoke-InstalledAppExportCsvWorkflow
  ├─ Resolve-InstalledAppExportWorkflowDependencies
  ├─ SuccessResults用ArrayListを作成
  ├─ FailureResults用ArrayListを作成
  ├─ New-InstalledAppExportListOperations
  │   ├─ Resolve-InstalledAppExportWorkflowDependencies
  │   ├─ New-InstalledAppExportRowProcessor
  │   │   ├─ RowAction.ExportForRow callbackを取得
  │   │   ├─ RowAction.NewFailure callbackを取得
  │   │   └─ Logger.WriteWarning callbackを取得
  │   └─ ListOperationsオブジェクトを作成
  ├─ Workflow.InvokeScrollableList callbackを取得
  ├─ InvokeScrollableListを実行
  └─ WorkflowResultを返す
```

## 5. 戻り値の形

`Invoke-InstalledAppExportCsvWorkflow` は、次のオブジェクトを返します。

```text
WorkflowResult
  ScanResult
    ProcessedCount : 処理済み行数
    ほか、ScrollableListWorkflow側の結果情報

  SuccessResults
    InstalledAppExportProcessResult[]
      DataId
      AssetName
      CsvPath

  FailureResults
    InstalledAppExportFailure[]
      DataId
      AssetName
      Reason
      Timestamp
```

`Runner.ps1` はこの戻り値を使って、失敗CSV出力、件数ログ、最終失敗判定を行います。

## 6. 関数ごとの説明

## New-InstalledAppExportRowProcessor

### 何をするか

1行分の処理を実行する `scriptblock` を作ります。

この `scriptblock` は、共通基盤の一覧走査処理から行ごとに呼ばれます。

### 入力

```text
Context        : 実行時情報
SuccessResults : 成功結果を入れるArrayList
FailureResults : 失敗結果を入れるArrayList
RowAction      : 1行処理用callback群
Logger         : 警告ログ用callback群
```

### 生成される処理

生成される `scriptblock` は、1行について次を行います。

```text
rowInfo から dataId と assetName を取り出す
  ↓
RowAction.ExportForRow を実行する
  ↓
成功したら SuccessResults に追加する
  ↓
例外が出たら
  ├─ Warningログを出す
  └─ RowAction.NewFailure で失敗結果を作り FailureResults に追加する
```

### なぜ例外をここで捕まえるのか

1台分の処理に失敗しても、残りの端末は処理したいからです。

ここで例外を捕まえずに投げると、最初に失敗した端末で一覧処理全体が止まります。
現在の設計では、失敗は `FailureResults` に記録し、最後に `Runner.ps1` でジョブ全体を失敗扱いにします。

### PowerShell文法上のポイント

#### `GetNewClosure()`

この関数が返す `scriptblock` は、`$Context`、`$SuccessResults`、`$FailureResults` など、外側の変数を後で使います。

`GetNewClosure()` により、scriptblock作成時点の変数を閉じ込めます。
これがないと、後で実行されたときに必要な変数を参照できない、または意図しない値を参照する可能性があります。

#### `& $exportForRow`

`$exportForRow` は関数名ではなく `scriptblock` です。
PowerShellでは、変数に入ったscriptblockを実行するには呼び出し演算子 `&` を使います。

### 変更時の注意

- `catch` を削ると、1行失敗で一覧全体が止まる
- `FailureResults.Add` を削ると、失敗CSVに記録されない
- `WriteWarning` を削ると、実行ログでどの行が失敗したか追いにくくなる
- `ExportForRow` を直接関数呼び出しにすると、テスト用callback差し替えが難しくなる

## New-InstalledAppExportListOperations

### 何をするか

共通基盤 `Invoke-ScrollableListWorkflow` に渡す操作セットを作ります。

### 戻り値の形

```text
ListOperations
  Name           : 'InstalledAppExportListOperations'
  GetVisibleRows : 表示中の端末行を取得するscriptblock
  GetRowKey      : 行の一意キーを作るscriptblock
  ProcessRow     : 1行分を処理するscriptblock
  ScrollDown     : 一覧を下へスクロールするscriptblock
```

### なぜこの形にするのか

共通基盤の `Invoke-ScrollableListWorkflow` は、InstalledAppExport固有の関数名を知りません。
その代わり、次のような抽象操作を受け取ります。

```text
表示行を取る
行キーを作る
行を処理する
下へスクロールする
```

この抽象操作に、InstalledAppExport固有の実装を差し込むのが `New-InstalledAppExportListOperations` です。

### 呼び出すもの

```text
Resolve-InstalledAppExportWorkflowDependencies
New-InstalledAppExportRowProcessor
Get-InstalledAppExportCallbackScriptBlock
```

### 変更時の注意

`GetVisibleRows`、`GetRowKey`、`ProcessRow`、`ScrollDown` の名前は、共通基盤側から期待される契約です。
名前を変える場合は、`Invoke-ScrollableListWorkflow` 側の契約も確認が必要です。

## Invoke-InstalledAppExportCsvWorkflow

### 何をするか

端末一覧全体のCSV出力Workflowを実行します。

### 入力

```text
Context    : 実行時情報
TotalCount : 端末一覧の総件数
Dependencies : テスト用または本番用の依存差し替えオブジェクト
```

### 処理順序

```text
settings を Context.JobSettings から取り出す
  ↓
依存関係を解決する
  ↓
成功結果と失敗結果のArrayListを作る
  ↓
一覧走査用 operations を作る
  ↓
InvokeScrollableList callbackを取得する
  ↓
InvokeScrollableList を実行する
  ↓
ScanResult / SuccessResults / FailureResults を返す
```

### なぜ `ArrayList` を使うのか

PowerShellの通常配列に要素を追加する場合、`+=` を使うと新しい配列が作られます。
一覧処理では行ごとに結果を追加するため、可変コレクションである `System.Collections.ArrayList` を使っています。

最後に戻すときは、`@($successResults)` のように配列として返します。

### 失敗条件

- 依存関係に必要なcallbackがない
- 一覧走査中に共通基盤がDOM契約違反を検出する
- `InvokeScrollableList` が最大ループ数などの条件で失敗する

1行分の処理失敗は、ここでは基本的に `FailureResults` に変換されます。
ただし、依存解決や一覧走査そのものが壊れている場合は例外になります。

## 7. Dependenciesとの関係

`Workflow.ps1` は、直接 `Get-VisibleAssetRows` や `Invoke-InstalledAppExportCsvForRow` を呼ばない構造になっています。

代わりに、`Dependencies.ps1` が次のcallbackを提供します。

```text
ListTraversal
  GetVisibleRows
  GetRowKey
  ScrollDown

RowAction
  ExportForRow
  NewFailure

Logger
  WriteWarning

Workflow
  InvokeScrollableList
```

これにより、Workflow単体テストでは、実ブラウザや実ファイルダウンロードを使わずに挙動を検証できます。

## 8. RowActionとの関係

`Workflow.ps1` が知っているのは、次だけです。

```text
RowAction.ExportForRow(Context, DataId, AssetName)
```

その中で詳細パネルを開くのか、アプリタブを押すのか、CSVをどうリネームするのかは知りません。

この分離により、一覧全体の制御と1行分の画面操作を分けて読めます。

## 9. 変更時の判断基準

- WorkflowにDOM helper method名を直接書かない
- WorkflowにCSVダウンロード待ちの詳細を書かない
- 1行失敗時に即中断する設計へ変える場合は、失敗CSVの意味が変わる
- `Dependencies` を通さず直接関数を呼ぶと、テスト差し替えの価値が下がる

## 10. 本ドキュメント内容の要点

- `Workflow.ps1` は一覧全体の処理を担当する
- 1行分の処理は `RowAction.ExportForRow` に委譲される
- 成功と失敗は別々のコレクションに集約される
- 1行分の失敗はWorkflow内で失敗結果に変換される
- 共通基盤のスクロール処理には、InstalledAppExport固有callbackを渡して使う
