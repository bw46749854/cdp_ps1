# modules/DeviceListExport/internal/Runner.ps1

## 1. このファイルを一言でいうと

`DeviceListExport` ジョブの入口と初期化を担当するファイルである。

`Invoke-DeviceListExportJob` は、`foundation.jobs.psd1` の `CommandName` に指定されている関数である。
つまり、`JobName DeviceListExport` を指定したときに最終的に呼ばれるプロダクト側の入口である。

## このファイルを変更する典型ケース

- Job開始時の初期化、依存解決、最終結果検査が変わった場合
- Context / Config / JobSettings の渡し方が変わった場合
- Workflow呼び出し前後のログや終了判定が変わった場合


## 2. このファイルが担当する範囲

```text
- ログに実行内容と保存先を出す
- 一時ダウンロードフォルダと最終保存フォルダを準備する
- 一時ダウンロードフォルダを空にする
- 対象ブラウザタブに接続する
- ブラウザのダウンロード先を一時フォルダに設定する
- Workflowを呼び出す
- 結果サマリーを出す
```

## 3. このファイルが担当しない範囲

```text
- 操作ボタンをクリックする
- エクスポートメニューをクリックする
- CSVダウンロード完了を判定する
- CSVファイル名を生成する
- DOM helperメソッド名を知る
```

これらは、`Workflow.ps1`、`Download.ps1`、`DomAdapter.ps1`、`DomOperations.ps1` に分かれている。

## 4. 関数呼び出しツリー

```text
Invoke-DeviceListExportJob
  ├─ Write-FoundationLog
  ├─ Initialize-DeviceListExportJob
  │   ├─ Initialize-DeviceListExportOutputDirectories
  │   │   ├─ Context.Services.FileSystem.InitializeOutputDirectory
  │   │   ├─ Context.Services.FileSystem.InitializeOutputDirectory
  │   │   └─ Context.Services.FileSystem.ClearDirectory
  │   ├─ Open-DeviceListExportBrowserSession
  │   │   ├─ New-DeviceListExportPageIdentityMatcher
  │   │   └─ Context.Services.Browser.OpenPageMatchingIdentity
  │   └─ Set-DeviceListExportDownloadDirectory
  │       └─ Context.Services.Browser.SetDownloadDirectory
  ├─ Invoke-DeviceListExportWorkflow
  ├─ Write-DeviceListExportResultSummary
  └─ return DeviceListExportResult
```

## 5. 扱うContextの値

このファイルは、主に `$Context` の次のプロパティを使う。

```text
Context.Logger
  ログ出力先。

Context.JobSettings.TempDirectory
  DeviceListExport用の一時ダウンロードフォルダ。

Context.JobSettings.DownloadDirectory
  リネーム後CSVの最終保存先。

Context.CommonSettings.DebuggerUrl
  ブラウザのCDPデバッグURL。

Context.CommonSettings.Cdp.ConnectTimeoutSeconds
  WebSocket接続のタイムアウト秒数。

Context.CommonSettings.Cdp.CommandTimeoutSeconds
  CDP命令のタイムアウト秒数。

Context.Services.FileSystem
  ディレクトリ初期化や削除の共通サービス。

Context.Services.Browser
  CDP経由でブラウザタブを開く・ダウンロード先を設定するサービス。
```

## 6. 関数ごとの説明

### Initialize-DeviceListExportOutputDirectories

DeviceListExportで使う2つのフォルダを準備する。

```text
TempDirectory
  ブラウザがCSVを最初にダウンロードする一時フォルダ。

DownloadDirectory
  リネーム後CSVを置く最終保存フォルダ。
```

処理順序は次である。

```text
1. TempDirectory が存在しなければ作る
2. DownloadDirectory が存在しなければ作る
3. TempDirectory の中身を消す
```

一時フォルダを空にする理由は、今回ダウンロードされたCSVだけを確実に判定するためである。
古いCSVが残っていると、`Download.ps1` が複数候補として検出し、どれを成果物にすべきか判断できなくなる。

副作用はファイルシステム操作である。
そのため、この関数は直接 `Remove-Item` せず、`Context.Services.FileSystem` 経由で削除する。

### Open-DeviceListExportBrowserSession

対象ブラウザタブにCDP接続する。

重要なのは、単に「最初のタブ」を選んでいないことである。

```text
New-DeviceListExportPageIdentityMatcher
  ↓
Test-DeviceListExportPageIdentity
  ↓
DetectPageIdentity DOM operation
```

この判定により、現在開いているタブがDeviceListExport対象画面かどうかを確認する。
対象画面ではないタブを操作しないための安全装置である。

### Set-DeviceListExportDownloadDirectory

ブラウザのダウンロード先を `Context.JobSettings.TempDirectory` に設定する。

これにより、エクスポートクリック後のCSVは一時フォルダへ落ちる。
`Download.ps1` はこの一時フォルダだけを監視すればよい。

### Initialize-DeviceListExportJob

DeviceListExport実行前に必要な準備をまとめる。

```text
Initialize-DeviceListExportJob
  ├─ フォルダ準備
  ├─ ブラウザ接続
  └─ ダウンロード先設定
```

この関数が完了した時点で、Workflowは「画面操作とCSV保存の手順」に集中できる。

### Invoke-DeviceListExportJob

DeviceListExportの外部公開入口である。

責務は次の通りである。

```text
1. これから何をするかログに出す
2. 一時ダウンロード先と最終保存先をログに出す
3. Initialize-DeviceListExportJob を呼ぶ
4. Invoke-DeviceListExportWorkflow を呼ぶ
5. Write-DeviceListExportResultSummary を呼ぶ
6. 完了ログを出す
7. 結果オブジェクトを返す
```

## 7. PowerShell文法上のポイント

### `$Context.Services.FileSystem.InitializeOutputDirectory.Invoke(...)`

`InitializeOutputDirectory` は通常の関数ではなく、`scriptblock` として `Context.Services.FileSystem` に入っている。
そのため、`.Invoke(...)` で実行している。

これは、テスト時に本物のファイル削除ではなく、偽物の処理に差し替えられるようにするためである。

### `| Out-Null`

フォルダ初期化やブラウザ接続の戻り値を後続処理に流さないために使っている。
PowerShellでは、関数内で出力された値が暗黙的に戻り値になる。
不要な出力が混ざると、呼び出し元が予期しない値を受け取る可能性がある。

### `[int]$commonSettings.Cdp.ConnectTimeoutSeconds`

設定ファイルから読んだ値を整数として扱うためのキャストである。
CDP接続処理では秒数として使うため、文字列のままではなく整数に寄せている。

## 8. 変更時の注意

### TempDirectoryのClearを削除しない

一時フォルダを空にしないと、前回実行分のCSVが残り、今回の成果物と区別できない。
`Wait-DeviceListExportDownloadedCsv` はCSV候補が複数あると例外にするため、古いCSVが残るだけで失敗する可能性がある。

### OpenPageMatchingIdentityを単純なOpenPageに戻さない

DeviceListExport対象ではないタブを操作する危険がある。
複数タブ環境では、PageIdentityMatcherが誤操作防止の境界になっている。

### SetDownloadDirectoryをWorkflow側に移さない

ダウンロード先設定は「ジョブ開始前の環境準備」である。
Workflowに入れると、Workflowが画面手順とブラウザ環境設定の両方を持つことになる。

## 9. 本ドキュメント内容の要点

```text
- Invoke-DeviceListExportJobがDeviceListExportの公開入口である
- RunnerはWorkflowの前提条件を整える
- 一時フォルダを空にするのは成果物誤判定を防ぐためである
- PageIdentityMatcherで対象タブを確認してから操作する
- ダウンロード先はWorkflow開始前にTempDirectoryへ設定される
```
