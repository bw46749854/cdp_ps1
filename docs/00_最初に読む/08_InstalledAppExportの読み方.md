# InstalledAppExportの読み方

## 1. InstalledAppExportジョブを一言でいうと

`InstalledAppExport` ジョブは、ExampleAsset画面の端末一覧から各端末を1台ずつ開き、その端末に紐づくアプリ一覧CSVをダウンロードするジョブです。

このジョブは、単に「CSVを1つ出す」処理ではありません。
一覧に表示される複数端末を、スクロールしながら、重複処理を避けて、1台ずつ処理します。

## 2. InstalledAppExportジョブの大きな流れ

```text
Invoke-InstalledAppExportJob
  ↓
Initialize-InstalledAppExportJob
  ├─ 出力フォルダを初期化する
  ├─ InstalledAppExport画面のブラウザタブに接続する
  ├─ Chromeのダウンロード先を一時フォルダに設定する
  ├─ InstalledAppExport画面として正しいことを確認する
  ├─ 端末一覧として正しいことを確認する
  ├─ 一覧件数を取得する
  └─ 一覧のスクロール位置を先頭に戻す
  ↓
Invoke-InstalledAppExportCsvWorkflow
  ├─ 一覧をスクロールしながら表示行を取得する
  ├─ 行ごとに dataId と assetName を取り出す
  ├─ 未処理の行だけ処理する
  ├─ 各行について RowAction を呼ぶ
  ├─ 成功結果を SuccessResults に追加する
  └─ 失敗結果を FailureResults に追加する
  ↓
Complete-InstalledAppExportJob
  ├─ 失敗一覧CSVを出力する
  ├─ 件数サマリーをログに出す
  ├─ 一覧件数分を処理できたか確認する
  └─ 失敗が1件でもあればジョブ失敗にする
```

## 3. 「一覧全体」と「1行分」を分けて読む

`InstalledAppExport` の読解で最も重要なのは、次の境界です。

| 領域 | 主なファイル | 役割 |
|---|---|---|
| ジョブ全体の入口 | `Runner.ps1` | 初期化、Workflow呼び出し、終了判定 |
| 一覧全体の走査 | `Workflow.ps1` | 表示行の取得、重複排除、行処理の実行 |
| 1行分の業務処理 | `RowAction.ps1` | 詳細パネルを開き、アプリCSVを取得する |
| 画面操作名 | `DomAdapter.ps1` | Workflow/RowActionから見える業務名の関数 |
| DOM helper対応表 | `DomOperations.ps1` | PowerShellのOperation名をJavaScript method名に変換 |
| ダウンロード待ち | `Download.ps1` | `.crdownload` 等を見てCSV完了を判定する |
| 結果モデル | `Models.ps1` | 成功・失敗・行キーのデータ形を作る |
| 失敗CSV出力 | `Output.ps1` | 失敗行をCSVに出す。失敗ゼロなら古いCSVを消す |

`Workflow.ps1` は、CSVボタンを直接押しません。
CSVボタンを押すのは `RowAction.ps1` の担当です。

逆に、`RowAction.ps1` は一覧全体をスクロールしません。
一覧全体のスクロールは `Workflow.ps1` と共通基盤の `Invoke-ScrollableListWorkflow` の担当です。

## 4. このジョブで出てくる重要なデータ

### 表示行情報

DOM側から取得される1行情報は、主に次の形です。

```text
rowInfo
  dataId       : 画面上の行を識別するID
  assetName : 端末名
```

この2つが空だと、同じ行かどうかを安定して判断できません。
そのため `Get-InstalledAppExportRowKey` は、どちらかが空なら空文字を返します。

### 成功結果

```text
InstalledAppExportProcessResult
  DataId       : 処理した行ID
  AssetName : 処理した端末名
  CsvPath      : 最終保存先CSVのパス
```

### 失敗結果

```text
InstalledAppExportFailure
  DataId       : 失敗した行ID
  AssetName : 失敗した端末名
  Reason       : 失敗理由
  Timestamp    : 失敗時刻の文字列
```

## 5. 失敗をどう扱うか

`InstalledAppExport` ジョブでは、1行分の処理に失敗しても、すぐに一覧全体を止めません。

`Workflow.ps1` の行処理では、1行分の例外を捕まえて、失敗結果として `FailureResults` に追加します。
これにより、途中の1台で失敗しても、残りの端末処理を続けられます。

ただし、最後に `Runner.ps1` の `Assert-InstalledAppExportHasNoFailures` が失敗件数を確認します。
失敗が1件でもあれば、ジョブ全体としては失敗にします。

つまり、挙動は次のようになります。

```text
途中の1台が失敗
  ↓
その場では一覧処理を継続
  ↓
失敗一覧CSVに記録
  ↓
最後にジョブ全体を失敗扱いにする
```

この設計により、1台目で止まって後続端末の状況が分からない、という状態を避けています。

## 6. InstalledAppExportで混ぜてはいけないもの

次のように責務を混ぜると、読みにくくなり、テストもしにくくなります。

| やってはいけない変更 | なぜ危険か |
|---|---|
| `Workflow.ps1` にDOM helper method名を直接書く | JavaScript側の名前変更がWorkflowに漏れる |
| `Runner.ps1` に1行分の詳細パネル操作を書く | 初期化と行処理が混ざる |
| `RowAction.ps1` に一覧スクロール処理を書く | 1行処理と一覧全体処理が混ざる |
| `Download.ps1` に画面クリックを書く | ファイル完了判定と画面操作が混ざる |
| `Output.ps1` にDOM操作を書く | 出力形式とブラウザ操作が混ざる |
| `DomOperations.ps1` に業務判断を書く | DOM method対応表がビジネスロジックを持ってしまう |

## 7. 本ドキュメント内容の要点

- `Runner.ps1` は、InstalledAppExportジョブ全体の入口である
- `Workflow.ps1` は、一覧全体の走査を担当する
- `RowAction.ps1` は、1行分のアプリCSV取得を担当する
- `Dependencies.ps1` は、Workflowから実装詳細を隠すためにある
- `DomAdapter.ps1` は、画面操作を業務名で呼べるようにする
- `DomOperations.ps1` は、PowerShell Operation名とJavaScript method名の対応表である
- `Download.ps1` は、CSVダウンロード完了を安全に待つ
- `Output.ps1` は、失敗一覧CSVの出力だけを担当する
