# modules/InstalledAppExport/internal/Dependencies.ps1

## 1. このファイルを一言でいうと

`InstalledAppExport` の `Workflow.ps1` が使う外部依存を、callback群として組み立てるファイルです。

ここでいう外部依存とは、画面から行を取得する処理、1行分を処理する処理、警告ログ、共通スクロールWorkflowなどです。

## このファイルを変更する典型ケース

- 依存port、callback名、既定実装の作り方が変わった場合
- Workflow / Runner が使う外部I/Oの差し替え境界が変わった場合
- 依存検証の粒度や必須callbackが変わった場合


## 2. なぜこのファイルが必要か

`Workflow.ps1` が直接次の関数を呼ぶと、Workflowの単体テストが難しくなります。

```text
Get-VisibleAssetRows
Scroll-InstalledAppExportListDown
Invoke-InstalledAppExportCsvForRow
Write-FoundationLog
Invoke-ScrollableListWorkflow
```

これらはDOM、ファイル、ログ、共通基盤に関わります。
そこで `Dependencies.ps1` が、本番では実関数を呼ぶscriptblockを作り、テストでは差し替え用のfake scriptblockを受け取れるようにしています。

## 3. このファイルが作る依存オブジェクト

最終的に `Resolve-InstalledAppExportWorkflowDependencies` は次の形を返します。

```text
InstalledAppExportWorkflowDependencies
  ListTraversal
    GetVisibleRows : 表示中の端末行を取得する
    GetRowKey      : 行の一意キーを作る
    ScrollDown     : 一覧を下へスクロールする

  RowAction
    ExportForRow   : 1行分のCSV取得を実行する
    NewFailure     : 失敗結果を作る

  Logger
    WriteWarning   : Warningログを出す

  Workflow
    InvokeScrollableList : 共通スクロールWorkflowを呼ぶ
```

## 4. 関数呼び出しツリー

```text
Resolve-InstalledAppExportWorkflowDependencies
  ├─ Get-InstalledAppExportDependencyProperty
  ├─ New-InstalledAppExportListTraversalCallbacks
  │   ├─ Get-Command Get-VisibleAssetRows
  │   ├─ Get-Command Get-InstalledAppExportRowKey
  │   └─ Get-Command Scroll-InstalledAppExportListDown
  ├─ New-InstalledAppExportRowActionCallbacks
  │   ├─ Get-Command Invoke-InstalledAppExportCsvForRow
  │   ├─ Get-Command New-InstalledAppExportFailure
  │   └─ Get-InstalledAppExportTimestampTextCallback
  ├─ New-InstalledAppExportLoggerPort
  │   └─ Write-FoundationLog
  ├─ New-InstalledAppExportWorkflowPort
  │   └─ Invoke-ScrollableListWorkflow
  └─ Assert-InstalledAppExportWorkflowDependencies
      └─ Get-InstalledAppExportCallbackScriptBlock
```

## 5. 関数ごとの説明

## Get-InstalledAppExportDependencyProperty

### 何をするか

任意のオブジェクトから、指定したプロパティ名の値を安全に取得します。

### なぜ必要か

PowerShellの `[pscustomobject]` は、存在しないプロパティを直接参照すると意図しない挙動になることがあります。
この関数は、プロパティがない場合に `$null` を返します。

### 入力

```text
Object : 調べる対象
Name   : 取得したいプロパティ名
```

### 出力

プロパティがあればその値、なければ `$null`。

## Get-InstalledAppExportCallbackScriptBlock

### 何をするか

callbackオブジェクトから指定名の値を取り出し、それが `[scriptblock]` であることを確認します。

### なぜ必要か

`Workflow.ps1` は callbackを `& $callback` の形で実行します。
値がscriptblockでなければ実行できません。

この関数で早めに検査することで、実行途中の分かりにくいエラーを防ぎます。

### 失敗条件

指定したプロパティがない、またはscriptblockではない場合、例外を投げます。

## Get-InstalledAppExportTimestampTextCallback

### 何をするか

失敗結果に入れるタイムスタンプ文字列を作るcallbackを取得します。

### 優先順位

```text
Context.Services.Timing.TimestampText がscriptblockならそれを使う
  ↓
なければ Get-Date を yyyy-MM-dd HH:mm:ss 形式にするdefault callbackを使う
```

### なぜ必要か

テストでは現在時刻が変わると検証しにくいため、時刻取得を差し替えられるようにしています。

## New-InstalledAppExportLoggerPort

### 何をするか

Warningログ用のPortを作ります。

### 優先順位

```text
Context.Services.Logger.WriteWarning があればそれを使う
  ↓
なければ Context.Logger と Write-FoundationLog を使うdefault portを作る
```

### 戻り値

```text
LoggerPort
  WriteWarning : scriptblock
```

### 変更時の注意

Workflowは `WriteWarning` だけを期待しています。
ここに通常ログ、エラーログなどを増やす場合は、Workflow側が本当に必要としているか確認します。

## New-InstalledAppExportWorkflowPort

### 何をするか

共通基盤のスクロールWorkflowを呼ぶPortを作ります。

### 優先順位

```text
Context.Services.Workflow.InvokeScrollableList があればそれを使う
  ↓
なければ Invoke-ScrollableListWorkflow を呼ぶdefault portを作る
```

### 戻り値

```text
WorkflowPort
  InvokeScrollableList : scriptblock
```

### なぜ必要か

一覧走査は共通基盤の責務です。
InstalledAppExport側は、表示行取得や行処理などのcallbackを渡します。

## New-InstalledAppExportModuleBoundScriptBlock

### 何をするか

scriptblockをInstalledAppExportモジュールのスコープに束縛します。

### なぜ必要か

`OpenPageMatchingIdentity` や `Invoke-ScrollableListWorkflow` は、Foundationモジュール側でcallbackを実行します。
そのままだと、InstalledAppExportモジュール内のprivate関数名を解決できない場合があります。

この関数により、callback内で `Test-InstalledAppExportPageIdentity` などのInstalledAppExport内部関数を解決できるようにします。

### PowerShell文法上のポイント

`$ExecutionContext.SessionState.Module.NewBoundScriptBlock()` は、モジュールスコープに結び付いたscriptblockを作ります。
PowerShell 5.1でモジュール境界をまたぐcallbackを扱うための重要な処理です。

## New-InstalledAppExportPageIdentityMatcher

### 何をするか

ブラウザタブがInstalledAppExport画面かどうかを判定するcallbackを作ります。

### 戻り値

```text
param($PageTarget, $Session)
  Test-InstalledAppExportPageIdentity -Context $Context を実行するscriptblock
```

### なぜ必要か

ブラウザに複数タブがあるとき、誤った画面へ接続しないためです。

### 変更時の注意

このcallbackでは `PageTarget` や `Session` は受け取っていますが、実際の判定は現在の `Context` を使って行います。
ページ識別ロジックを変更する場合は、`Test-InstalledAppExportPageIdentity` 側も確認します。

## New-InstalledAppExportListTraversalCallbacks

### 何をするか

一覧走査に必要な3つのcallbackを作ります。

```text
GetVisibleRows : Get-VisibleAssetRows を呼ぶ
GetRowKey      : Get-InstalledAppExportRowKey を呼ぶ
ScrollDown     : Scroll-InstalledAppExportListDown を呼ぶ
```

### なぜ `Get-Command` を使うのか

callback作成時に、呼び出し先関数の `CommandInfo` を取得して閉じ込めています。
これにより、callback実行時にどの関数を呼ぶかが安定します。

## New-InstalledAppExportRowActionCallbacks

### 何をするか

1行分の処理に必要なcallbackを作ります。

```text
ExportForRow : Invoke-InstalledAppExportCsvForRow を呼ぶ
NewFailure   : New-InstalledAppExportFailure を呼ぶ
```

`NewFailure` では、タイムスタンプcallbackを使って失敗時刻を入れます。

### なぜ必要か

Workflowは、1行処理の中身を知らないようにするためです。
Workflowから見えるのは、`ExportForRow` と `NewFailure` だけです。

## Assert-InstalledAppExportWorkflowDependencies

### 何をするか

依存オブジェクトに必要なcallbackがすべて揃っているか検査します。

検査対象は次です。

```text
ListTraversal.GetVisibleRows
ListTraversal.GetRowKey
ListTraversal.ScrollDown
RowAction.ExportForRow
RowAction.NewFailure
Logger.WriteWarning
Workflow.InvokeScrollableList
```

### なぜ必要か

不足したcallbackがあると、一覧処理の途中で分かりにくいエラーになります。
先に契約違反として止めるための検査です。

## Resolve-InstalledAppExportWorkflowDependencies

### 何をするか

本番用またはテスト用の依存オブジェクトを解決し、不足しているものをdefault実装で補います。

### 処理順序

```text
Dependenciesがnullなら空オブジェクトにする
  ↓
ListTraversalがなければNew-InstalledAppExportListTraversalCallbacks
  ↓
RowActionがなければNew-InstalledAppExportRowActionCallbacks
  ↓
LoggerがなければNew-InstalledAppExportLoggerPort
  ↓
WorkflowがなければNew-InstalledAppExportWorkflowPort
  ↓
全部をまとめたresolvedオブジェクトを作る
  ↓
Assert-InstalledAppExportWorkflowDependenciesで検査する
  ↓
return resolved
```

## 6. テスト差し替えの考え方

単体テストでは、実ブラウザや実CSVダウンロードを使いたくありません。
そのため、次のようなfake dependencyを渡せます。

```text
Dependencies
  ListTraversal.GetVisibleRows : 固定の行配列を返す
  RowAction.ExportForRow       : 成功または失敗を模擬する
  Logger.WriteWarning          : ログ文字列を配列に保存する
  Workflow.InvokeScrollableList: 共通Workflow呼び出しを模擬する
```

これにより、Workflowの分岐や結果分類だけを検証できます。

## 7. 変更時の判断基準

- Workflowから直接DOM関数を呼ばせない
- 依存の名前を変える場合は、Workflow側の取得名も合わせる
- `Assert-InstalledAppExportWorkflowDependencies` の検査を弱めない
- テスト用に差し替える必要がある副作用は、このファイルでPort化する
- ただの値計算まで過剰にPort化しない

## 8. 本ドキュメント内容の要点

- `Dependencies.ps1` は、Workflowの外部依存をscriptblockとして束ねる
- 本番時は実関数を呼ぶcallbackを作る
- テスト時はfake callbackを注入できる
- `Resolve-InstalledAppExportWorkflowDependencies` が依存解決の中心である
- callback契約の検査は、実行途中の不明瞭な失敗を防ぐためにある
