# ScanTargetSync PolicyとWorkflowの分離

## この文書の位置づけ

この文書は横断ガイドです。
`ScanTargetSync` の関数一覧、引数詳細、DOM operation一覧、CSV列の完全仕様の正本ではありません。

目的は、`ScanTargetSync` の全体像をつかみ、変更内容に応じて読むべき個別ファイルドキュメントへ進めるようにすることです。
詳細仕様は `docs/05_ScanTargetSync/internal__*.md` を正とします。

## この文書を変更する典型ケース

- ScanTargetSyncのPolicy、Reconciliation、Workflowの責務関係が変わった場合
- CSV判定とUI同期を分けて読む導線が変わった場合
- 変更内容別の参照先や誤解しやすい点が変わった場合


## ScanTargetSync が解く業務問題

`ScanTargetSync` は、入力CSVと管理画面のデバイス一覧を突き合わせ、手動スキャン対象にすべきendpointだけをチェックONへ、対象外にすべきendpointをチェックOFFへ揃えるJobです。

このJobでは、次の情報が混ざりやすいため、責務を分けて読む必要があります。

```text
CSVの値をどう解釈するか
どのendpointをON/OFF対象にするか
CSVとUIのendpointが一致しているか
画面上でどの行を操作するか
操作後の結果が整合しているか
どのCSVへエラーを出すか
```

## 処理全体の流れ

```text
Invoke-ScanTargetSyncJob
  ↓
Resolve dependencies
  ↓
CSV入力を読み込む
  ↓
CSV行をPolicy判定する
  ↓
ON/OFF同期対象Planを作る
  ↓
対象ページを開き、画面契約を確認する
  ↓
UI一覧を上から下まで走査する
  ↓
見えたendpointが同期対象ならチェック状態を揃える
  ↓
UI走査結果とCSV Planの差異を検証する
  ↓
成功/失敗を集計する
  ↓
CSVデータエラーCSVとチェック処理失敗CSVを出力する
```

## 4つの責務領域

### Policy

CSVの値だけで判断できる業務ルールを扱います。
ブラウザやDOM helperには依存しません。

主なファイル:

- `internal__CsvInput.ps1.md`
- `internal__CsvInputFile.ps1.md`
- `internal__Rules.ps1.md`
- `internal__Reconciliation.ps1.md`

### Workflow

処理順序、状態、結果検証、早期終了、致命的エラー時の保険出力を扱います。
Policyの判定結果を使いますが、判定式そのものは持ちません。

主なファイル:

- `internal__Workflow.ps1.md`
- `internal__Workflow.Orchestration.ps1.md`
- `internal__Workflow.CsvPlan.ps1.md`
- `internal__Workflow.Page.ps1.md`
- `internal__Workflow.UiScan.ps1.md`
- `internal__Workflow.UiScanState.ps1.md`
- `internal__Workflow.EndpointSync.ps1.md`
- `internal__Workflow.Result.ps1.md`
- `internal__Workflow.State.ps1.md`
- `internal__Workflow.Export.ps1.md`
- `internal__Workflow.Fatal.ps1.md`

### DOM

管理画面を読む・操作する境界です。
Workflowは業務名の関数を呼び、DOM helper method名や `Await` 契約は `DomOperations.ps1` に閉じます。

主なファイル:

- `internal__DomAdapter.ps1.md`
- `internal__DomOperations.ps1.md`
- `docs/08_DOM_JavaScript/scan-target-sync/*.md`

### Output / Dependencies

出力CSVと外部依存の境界です。
Workflowが低レベルI/Oや時刻、ログ出力、DOM helperへ直接依存しないようにします。

主なファイル:

- `internal__Output.ps1.md`
- `internal__Dependencies.ps1.md`
- `internal__Runner.ps1.md`

## 誤解しやすい点

- `Rules.ps1` はCSVだけで判断できるPolicy層です。UI上にendpointが存在するかどうかは見ません。
- `Reconciliation.ps1` はPolicy判定済みの行をendpoint単位の同期計画へ整えます。DOM操作はしません。
- `Workflow.CsvPlan.ps1` はPlan作成の順序を管理します。日付parseやON/OFF判定式を増やす場所ではありません。
- `Workflow.UiScanState.ps1` の `LoopReachedLimit` は初期値を安全側の `$true` にします。正常終了条件で解除されない限り、走査上限到達の可能性として結果検証に渡します。
- `Workflow.Result.ps1` はPolicy層ではありません。UI走査と同期結果を検証し、失敗行と処理サマリに変換するWorkflow補助です。
- `DomOperations.ps1` の `Await = $true` はoperationの意味契約です。呼び出し側の都合で散在させないでください。
- `Dependencies.ps1` は依存portを作る場所です。業務判断やDOM selectorを置かないでください。

## 変更内容別に読むべきファイル

| 変更内容 | まず読む | 次に確認する |
|---|---|---|
| CSV列や入力CSV契約を変える | `CsvInput`, `CsvInputFile` | `Rules`, `Workflow.CsvPlan`, `ScanTargetSync.CsvInput.Tests.ps1` |
| 日付解釈を変える | `CsvInput` | `Rules`, `ScanTargetSync.CsvInput.Tests.ps1` |
| ON/OFF判定を変える | `Rules` | `Reconciliation`, `Workflow.CsvPlan`, `ScanTargetSync.Rules.Tests.ps1` |
| endpoint重複の扱いを変える | `Reconciliation` | `Workflow.CsvPlan`, `Workflow.Result`, `ScanTargetSync.Reconciliation.Tests.ps1` |
| UI一覧走査を変える | `Workflow.UiScan`, `Workflow.UiScanState` | `DomAdapter`, `DomOperations`, JS DOM tests |
| checkbox操作を変える | `Workflow.EndpointSync` | `DomAdapter`, `DomOperations`, `scan-target-sync` JS docs |
| DOM helper methodやAwaitを変える | `DomOperations` | `docs/08_DOM_JavaScript/scan-target-sync`, `Dom.OperationRegistryContract.Tests.ps1` |
| 結果検証・失敗行を変える | `Workflow.Result`, `Workflow.State` | `Output`, `ScanTargetSync.Workflow.Tests.ps1` |
| 出力CSVの列を変える | `Output` | `Workflow.Export`, `Workflow.Fatal`, `ScanTargetSync.Output.Tests.ps1` |
| 依存差し替えやテスト容易性を変える | `Dependencies` | `Runner`, `Architecture.Tests.ps1` |

## 最短の読み順

初めて読む場合は、次の順番で読むと処理が追いやすくなります。

1. `internal__Runner.ps1.md`
2. `internal__Workflow.ps1.md`
3. `internal__Workflow.Orchestration.ps1.md`
4. `internal__Workflow.CsvPlan.ps1.md`
5. `internal__Rules.ps1.md`
6. `internal__Reconciliation.ps1.md`
7. `internal__Workflow.UiScan.ps1.md`
8. `internal__Workflow.UiScanState.ps1.md`
9. `internal__Workflow.EndpointSync.ps1.md`
10. `internal__Workflow.Result.ps1.md`
11. `internal__DomAdapter.ps1.md`
12. `internal__DomOperations.ps1.md`
13. `internal__Output.ps1.md`
14. `internal__Dependencies.ps1.md`

## 詳細参照

- `docs/05_ScanTargetSync/internal__*.md`
- `docs/08_DOM_JavaScript/scan-target-sync/*.md`
- `main/tests/ScanTargetSync.*.Tests.ps1`
- `main/tests/js/scan-target-sync.dom.behavior.test.js`
- `main/tests/Architecture.Tests.ps1`
- `main/ARCHITECTURE.md`

## この文書を更新する条件

この文書を更新するのは、ScanTargetSync全体の責務境界、処理順序、変更内容別の参照先、誤解しやすい点が変わった場合です。

関数追加、引数変更、DOM operation追加、CSV列変更などの詳細だけなら、対応する個別ファイルドキュメントを更新してください。
