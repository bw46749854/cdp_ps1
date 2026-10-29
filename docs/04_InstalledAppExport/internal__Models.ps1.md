# modules/InstalledAppExport/internal/Models.ps1

## 1. このファイルを一言でいうと

InstalledAppExportジョブで使う小さなデータ構造を作るファイルです。

成功結果、失敗結果、一覧行の一意キーを作ります。

## このファイルを変更する典型ケース

- 成功、失敗、skip、summaryなどのデータ構造が変わった場合
- WorkflowやOutputへ渡すオブジェクトのプロパティが変わった場合
- テストで比較する結果モデルの意味が変わった場合


## 2. このファイルが担当する範囲

- 1台分の成功結果を作る
- 1台分の失敗結果を作る
- 一覧行を重複判定するためのキーを作る

## 3. このファイルが担当しない範囲

| 担当しないこと | 担当ファイル |
|---|---|
| 画面を操作する | `DomAdapter.ps1` / `RowAction.ps1` |
| 一覧全体を走査する | `Workflow.ps1` |
| CSVファイルを書き出す | `Output.ps1` |
| CSVダウンロードを待つ | `Download.ps1` |

## 4. 関数ごとの説明

## New-InstalledAppExportProcessResult

### 何をするか

1台分の処理成功結果を作ります。

### 入力

```text
DataId       : 画面上の行ID
AssetName : 端末名
CsvPath      : 最終保存されたCSVパス
```

### 出力

```text
InstalledAppExportProcessResult
  DataId
  AssetName
  CsvPath
```

### どこで使われるか

`RowAction.ps1` の処理完了時に作られ、`Workflow.ps1` の `SuccessResults` に追加されます。

## New-InstalledAppExportFailure

### 何をするか

1台分の処理失敗結果を作ります。

### 入力

```text
DataId       : 画面上の行ID
AssetName : 端末名
Reason       : 失敗理由
Timestamp    : 失敗時刻文字列。省略時は空文字
```

### 出力

```text
InstalledAppExportFailure
  DataId
  AssetName
  Reason
  Timestamp
```

### どこで使われるか

`Workflow.ps1` の行処理で例外を捕まえたとき、`Dependencies.ps1` 経由で呼ばれます。
作られた失敗結果は `FailureResults` に追加され、最後に `Output.ps1` でCSV化されます。

## Get-InstalledAppExportRowKey

### 何をするか

一覧行を一意に識別するキーを作ります。

### 入力

```text
Row
  dataId
  assetName
```

### 出力

```text
<dataId>|<assetName>
```

例:

```text
row-001|PC-001
```

### 空文字を返す条件

次のどちらかが空の場合、空文字を返します。

```text
dataId
assetName
```

### なぜ空文字にするのか

一覧走査では、行キーを使って重複処理を避けます。
行を識別する情報が欠けている場合、正しい重複判定ができません。
そのような行に無理にキーを作るより、空キーとして扱う方が異常を検出しやすくなります。

## 5. PowerShell文法上のポイント

### `[pscustomobject]`

`[pscustomobject]` は、名前付きプロパティを持つ軽量オブジェクトを作るために使います。
このプロジェクトでは、戻り値の形を明示する目的で多用されています。

例えば成功結果は、配列や文字列ではなく、次の名前付きプロパティを持つオブジェクトとして返します。

```text
DataId
AssetName
CsvPath
```

これにより、呼び出し元は `$result.CsvPath` のように意味のある名前で値を取り出せます。

## 6. 変更時の判断基準

- プロパティ名を変えると、`Workflow.ps1`、`Runner.ps1`、`Output.ps1` 側の参照が壊れる
- `InstalledAppExportFailure` から `Timestamp` を削ると、失敗CSVでいつ失敗したか分からなくなる
- `Get-InstalledAppExportRowKey` の形式を変えると、一覧重複判定に影響する
- `dataId` だけ、または `assetName` だけをキーにすると、誤った重複判定が起きる可能性がある

## 7. 本ドキュメント内容の要点

- `Models.ps1` はデータの形を定義する
- 成功結果と失敗結果は別の形を持つ
- 行キーは `dataId` と `assetName` の両方から作る
- このファイルに画面操作やファイル出力を書かない
