# modules/InstalledAppExport/internal/Runner.ps1

## 1. このファイルを一言でいうと

`InstalledAppExport` ジョブ全体の入口です。

出力フォルダの初期化、ブラウザ接続、DOM契約確認、一覧件数取得、Workflow呼び出し、最後の結果判定を担当します。

## このファイルを変更する典型ケース

- Job開始時の初期化、依存解決、最終結果検査が変わった場合
- Context / Config / JobSettings の渡し方が変わった場合
- Workflow呼び出し前後のログや終了判定が変わった場合


## 2. このファイルが担当する範囲

`Runner.ps1` は、ジョブの開始から終了までの大枠を制御します。

担当する処理は次の通りです。

```text
起動準備
  ├─ 一時ダウンロードフォルダを初期化
  ├─ 最終保存フォルダを初期化
  ├─ InstalledAppExport画面のブラウザタブへ接続
  ├─ Chromeのダウンロード先を一時フォルダに設定
  ├─ InstalledAppExport画面のDOM契約を確認
  ├─ 一覧件数を取得
  └─ 一覧位置を先頭に戻す

メイン処理
  └─ Invoke-InstalledAppExportCsvWorkflow を呼ぶ

終了処理
  ├─ 失敗一覧CSVを出力
  ├─ 結果サマリーをログに出力
  ├─ 全件処理できたか確認
  └─ 失敗がないか確認
```

## 3. このファイルが担当しない範囲

`Runner.ps1` は、次を直接担当しません。

| 担当しないこと | 担当ファイル |
|---|---|
| 一覧をスクロールしながら行を処理する | `Workflow.ps1` |
| 1行分の詳細パネル操作とCSV取得 | `RowAction.ps1` |
| DOM helper method名の対応 | `DomOperations.ps1` |
| 失敗CSVの具体的なCSV書き出し | `Output.ps1` |
| ダウンロード完了判定 | `Download.ps1` |

## 4. 主な呼び出しツリー

```text
Invoke-InstalledAppExportJob
  ├─ Initialize-InstalledAppExportJob
  │   ├─ Initialize-InstalledAppExportOutputDirectories
  │   ├─ Open-InstalledAppExportBrowserSession
  │   ├─ Set-InstalledAppExportDownloadDirectory
  │   ├─ Assert-InstalledAppExportInitialPageContract
  │   ├─ Get-InstalledAppExportInitialTotalCount
  │   └─ Reset-InstalledAppExportInitialListPosition
  │
  ├─ Invoke-InstalledAppExportCsvWorkflow
  │
  ├─ Complete-InstalledAppExportJob
  │   ├─ Export-InstalledAppExportJobResults
  │   │   └─ Export-InstalledAppExportFailureCsv
  │   ├─ Write-InstalledAppExportWorkflowSummary
  │   ├─ Assert-InstalledAppExportProcessedAllRows
  │   └─ Assert-InstalledAppExportHasNoFailures
  │
  └─ Write-FoundationLog
```

## 5. 関数ごとの説明

## Initialize-InstalledAppExportOutputDirectories

### 何をするか

一時ダウンロードフォルダと最終保存フォルダを準備します。
その後、一時ダウンロードフォルダの中身を空にします。

### なぜ必要か

InstalledAppExportジョブでは、1台ごとにCSVをダウンロードします。
一時フォルダに古いCSVが残っていると、今回のダウンロード結果なのか、前回の残骸なのか区別できません。

そのため、ジョブ開始時に一時フォルダを必ず空にします。

### 入力

```text
Context.JobSettings.TempDirectory
Context.JobSettings.DownloadDirectory
Context.Services.FileSystem
```

### 副作用

- ディレクトリを作成する
- 一時フォルダ内のファイルを削除する

### 変更時の注意

`ClearDirectory` を削除すると、`Wait-DownloadedCsv` が古いCSVを拾う可能性があります。

## Open-InstalledAppExportBrowserSession

### 何をするか

Chrome DevTools Protocolで接続可能なページの中から、InstalledAppExport画面に一致するタブを探して接続します。

### なぜ必要か

ブラウザには複数タブが開いている可能性があります。
単純に最初のタブへ接続すると、別画面を操作する危険があります。

そのため `New-InstalledAppExportPageIdentityMatcher` で作った判定関数を使い、InstalledAppExport画面かどうかを確認します。

### 入力

```text
Context.CommonSettings.DebuggerUrl
Context.CommonSettings.Cdp.ConnectTimeoutSeconds
Context.CommonSettings.Cdp.CommandTimeoutSeconds
```

### 呼び出すもの

```text
New-InstalledAppExportPageIdentityMatcher
Context.Services.Browser.OpenPageMatchingIdentity
```

### 変更時の注意

ページ識別を弱めると、誤ったタブに接続して別画面をクリックする可能性があります。

## Set-InstalledAppExportDownloadDirectory

### 何をするか

ブラウザのダウンロード先を `TempDirectory` に設定します。

### なぜ必要か

ダウンロードされたCSVを確実に監視するためです。
ユーザーの通常ダウンロードフォルダに落ちると、古いファイルや手動ダウンロードと混ざります。

### 副作用

Chromeのダウンロード先設定を変更します。

## Assert-InstalledAppExportInitialPageContract

### 何をするか

InstalledAppExport画面として必要なDOM構造が揃っているか確認します。

内部では次を実行します。

```text
Register-InstalledAppExportDomAdapter
Assert-InstalledAppExportPage
Assert-InstalledAppExportList
```

### なぜ必要か

画面構造が変わっている場合、行クリックやCSVボタン操作を続けると、誤操作や分かりにくい例外になります。
先に契約確認をすることで、壊れた画面に対する操作を早期に止めます。

### 失敗条件

- DOM helper登録に失敗する
- InstalledAppExport画面ではない
- 端末一覧のDOM契約を満たさない

## Get-InstalledAppExportInitialTotalCount

### 何をするか

端末一覧の総件数を取得し、整数として返します。

### なぜ必要か

後続の `Invoke-ScrollableListWorkflow` は、総件数を基準に一覧全体を走査します。
また、最後に `ProcessedCount` と比較して、全件処理できたかを確認します。

### 失敗条件

一覧件数が `null` の場合、DOM契約違反として例外を投げます。

## Reset-InstalledAppExportInitialListPosition

### 何をするか

詳細パネルを安全に閉じ、一覧のスクロール位置を先頭へ戻し、短時間待機します。

### なぜ必要か

一覧の途中位置から処理を始めると、前半の行を処理しないまま終わる可能性があります。
また、前回操作の詳細パネルが開いたままだと、次の行クリックが正しく動かない可能性があります。

### 呼び出すもの

```text
Close-InstalledAppExportDetailPanelSafely
Scroll-InstalledAppExportListToTop
Context.Services.Timing.SleepMilliseconds
```

## Initialize-InstalledAppExportJob

### 何をするか

InstalledAppExportジョブ実行前の準備をまとめて実行し、一覧件数を返します。

### 処理順序

```text
Initialize-InstalledAppExportOutputDirectories
Open-InstalledAppExportBrowserSession
Set-InstalledAppExportDownloadDirectory
Assert-InstalledAppExportInitialPageContract
Get-InstalledAppExportInitialTotalCount
Reset-InstalledAppExportInitialListPosition
return totalCount
```

### 変更時の注意

順番が重要です。
DOM契約確認より前にDOM操作を増やすと、画面構造が壊れているときの失敗が分かりにくくなります。

## Export-InstalledAppExportJobResults

### 何をするか

Workflow結果に含まれる失敗行を、失敗一覧CSVとして出力します。

### 戻り値

```text
ExportResult
  FailureCsvPath : 失敗一覧CSVの予定パス
  FailureCsv     : 実際に出力されたFileInfo。失敗ゼロならnull
```

### 補足

失敗件数が0件の場合、`Export-InstalledAppExportFailureCsv` は既存の古い失敗CSVを削除し、`null` を返します。

## Write-InstalledAppExportWorkflowSummary

### 何をするか

処理件数、成功件数、失敗件数、失敗CSVの有無をログに出します。

### なぜ必要か

ジョブ実行後に、処理がどこまで進んだかを人間が確認できるようにするためです。

## Assert-InstalledAppExportProcessedAllRows

### 何をするか

一覧総件数に対して、実際の処理済み件数が不足していないか確認します。

### 失敗条件

```text
WorkflowResult.ScanResult.ProcessedCount < TotalCount
```

この場合、一覧を最後まで走査できていない可能性があります。

## Assert-InstalledAppExportHasNoFailures

### 何をするか

1件でも失敗結果があれば、ジョブ全体を失敗にします。

### なぜ必要か

途中の行処理では、個別失敗を捕まえて処理を継続します。
しかし、最終的には失敗を見逃してはいけないため、ここで明示的に例外を投げます。

## Complete-InstalledAppExportJob

### 何をするか

Workflow完了後の後処理をまとめます。

```text
失敗CSV出力
  ↓
結果サマリー出力
  ↓
全件処理確認
  ↓
失敗有無確認
```

## Invoke-InstalledAppExportJob

### 何をするか

Foundationから呼ばれるInstalledAppExportジョブの公開入口です。

### 処理順序

```text
Initialize-InstalledAppExportJob
  ↓
Write-FoundationLog 一覧件数
  ↓
Invoke-InstalledAppExportCsvWorkflow
  ↓
Complete-InstalledAppExportJob
  ↓
Write-FoundationLog 完了
```

## 6. PowerShell文法上のポイント

### `| Out-Null`

戻り値を使わない処理で、画面やパイプラインに余計な値を流さないために使います。

このファイルでは、ディレクトリ初期化やDOM契約確認など、成功すれば値を使わない処理に使われています。

### `[int]$commonSettings.Cdp.ConnectTimeoutSeconds`

設定ファイルから読んだ値を整数として扱うためにキャストしています。
設定値が文字列として入っていても、CDP接続処理には秒数として渡す必要があります。

## 7. 変更時の判断基準

- 初期化順序を変える場合は、後続処理の前提を壊さないか確認する
- 一覧件数取得を削ると、全件処理確認ができなくなる
- 個別失敗を即時throwに変えると、後続端末の処理結果が取れなくなる
- `Assert-InstalledAppExportHasNoFailures` を削ると、失敗があってもジョブ成功扱いになる

## 8. 本ドキュメント内容の要点

- `Invoke-InstalledAppExportJob` がInstalledAppExportジョブの外部公開入口である
- `Initialize-InstalledAppExportJob` は、処理開始前の前提を整える
- `Invoke-InstalledAppExportCsvWorkflow` が一覧全体の処理を担当する
- `Complete-InstalledAppExportJob` が、失敗CSV出力と最終判定を担当する
