# ScanTargetSyncの読み方

## 1. この機能を一言でいうと

`ScanTargetSync` は、Vendor系のデバイス一覧CSVを読み、CSV上の各endpointについて「手動スキャン対象チェックボックスをONにすべきか、OFFにすべきか」を判定し、ブラウザ上の一覧画面と整合させるジョブです。

ただし、このジョブは手動スキャンそのものを開始しません。最後まで実行しても、画面上のチェック状態を揃えるだけです。

## 2. なぜファイル数が多いのか

この機能は、一見すると「CSVを読んでチェックするだけ」に見えます。しかし安全に自動操作するには、以下を分ける必要があります。

| 関心 | ファイル |
|---|---|
| CSV読み込み | `CsvInputFile.ps1` |
| CSV列・日付の解釈 | `CsvInput.ps1` |
| ON/OFF業務判定 | `Rules.ps1` |
| CSV内重複とON/OFF対象行の整形 | `Reconciliation.ps1` |
| 全体の処理順序 | `Workflow.Orchestration.ps1` |
| 画面を開いて契約確認する | `Workflow.Page.ps1` |
| UI一覧を上から下まで走査する | `Workflow.UiScan.ps1` |
| 走査中の状態を保持する | `Workflow.UiScanState.ps1` |
| endpoint単位でチェックボックスを同期する | `Workflow.EndpointSync.ps1` |
| 失敗条件をまとめて判定する | `Workflow.Result.ps1` |
| エラーCSV・失敗CSVを出す | `Workflow.Export.ps1`, `Output.ps1` |
| DOM helperを呼ぶ | `DomAdapter.ps1`, `DomOperations.ps1` |
| テスト差し替え可能な依存を束ねる | `Dependencies.ps1` |

この分割は、SOLID原則を形だけ適用した結果ではありません。誤操作防止のため、「CSVが信用できない状態ではブラウザに接続しない」「UI件数とCSV件数が違う状態ではチェック操作を開始しない」「致命的CDPエラーなら即停止する」という境界を明確にするためです。

## 3. 全体の処理ツリー

```text
Invoke-ScanTargetSyncJob
  ├─ Initialize-ScanTargetSyncJob
  │   ├─ Resolve-ScanTargetSyncWorkflowDependencies
  │   └─ InitializeOutputDirectory
  │
  └─ Invoke-ScanTargetSyncSyncWorkflow
      ├─ Resolve-ScanTargetSyncWorkflowDependencies
      ├─ New-ScanTargetSyncWorkflowState
      ├─ Initialize-ScanTargetSyncWorkflow
      │   ├─ InitializeOutputDirectory
      │   └─ Write-ScanTargetSyncWorkflowStartLog
      │
      ├─ New-ScanTargetSyncValidatedPlan
      │   ├─ Import-ScanTargetSyncCsvPlan
      │   │   ├─ Import-ScanTargetSyncInputCsv
      │   │   ├─ Assert-ScanTargetSyncInputCsvContract
      │   │   ├─ Get-ScanTargetSyncTargetExtraction
      │   │   └─ Get-ScanTargetSyncDuplicateEndpointErrors
      │   ├─ Resolve-ScanTargetSyncSyncPlan
      │   │   ├─ Get-ScanTargetSyncSyncRows
      │   │   └─ Assert-UniqueScanTargetSyncSyncRows
      │   ├─ Assert-ScanTargetSyncCsvPlanOrStop
      │   └─ Write-ScanTargetSyncCsvSummary
      │
      ├─ Test-ScanTargetSyncNoSyncTarget
      │   └─ Complete-ScanTargetSyncEndCsvExport
      │
      ├─ Invoke-ScanTargetSyncScanAndSync
      │   ├─ New-ScanTargetSyncSyncIndex
      │   ├─ Open-ScanTargetSyncPageAndValidate
      │   ├─ Invoke-ScanTargetSyncUiScan
      │   │   ├─ GetVisibleRows
      │   │   ├─ Update-ScanTargetSyncUiScanStateFromVisibleRows
      │   │   ├─ Invoke-ScanTargetSyncVisibleEndpointSyncBatch
      │   │   │   └─ Invoke-ScanTargetSyncSyncForEndpoint
      │   │   └─ Move-ScanTargetSyncUiScanCursor
      │   ├─ Add-ScanTargetSyncUiScanValidationFailures
      │   ├─ Get-ScanTargetSyncSuccessBreakdown
      │   └─ Add-ScanTargetSyncSuccessValidationFailures
      │
      ├─ Complete-ScanTargetSyncWorkflow
      │   ├─ Confirm-ScanTargetSyncPostSelectionContract
      │   ├─ Write-ScanTargetSyncProcessingSummary
      │   └─ Complete-ScanTargetSyncEndCsvExport
      │
      ├─ Assert-ScanTargetSyncWorkflowSucceeded
      └─ catch
          └─ Export-ScanTargetSyncFatalResultIfNeeded
```

## 4. この機能の安全設計

この機能は、以下の順で安全確認を重ねます。

1. CSVファイルが存在するか。
2. 必須列があるか。
3. 各行の日付が判定可能か。
4. endpointがCSV内で重複していないか。
5. CSV全行がONまたはOFFに分類できたか。
6. UI一覧件数とCSV件数が一致するか。
7. UI一覧を全件走査できたか。
8. CSVにあるendpointがUIに存在するか。
9. UIにあるendpointがCSVに存在するか。
10. 成功扱いの行のチェック状態が、目的状態と一致しているか。

どれかが崩れると、失敗CSVまたはCSVデータエラーCSVに出力し、必要に応じて例外で停止します。

## 5. 混乱しやすい点

`Plan`、`State`、`ScanState` は別物です。

| 名前 | 何を持つか |
|---|---|
| `Plan` | CSVから作った処理計画。ON行、OFF行、CSVエラー行、同期対象行。 |
| `State` | ジョブ全体の状態。失敗行、CSVエラー出力行、終了CSV出力済みかどうか。 |
| `ScanState` | UI走査中だけ使う状態。見たendpoint、処理済みendpoint、成功行、スクロール回数。 |

`Plan` は「何をしたいか」、`State` は「何が起きたか」、`ScanState` は「画面をどこまで見たか」です。
