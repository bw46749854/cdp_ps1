# ScanTargetSync internal/Workflow.Orchestration.ps1

## この文書の位置づけ

この文書は `main/modules/ScanTargetSync/internal/Workflow.Orchestration.ps1` の個別ファイルドキュメントです。
ScanTargetSync Workflowの大きな業務フローを組み立てる中核処理を説明します。

## このファイルを変更する典型ケース

- 処理順序、分岐、リトライ、失敗時の継続方針が変わった場合
- Policy判定結果と依存portのつなぎ方が変わった場合
- Workflowが集約する結果や後続処理への渡し方が変わった場合


## このファイルの責務

このファイルは、CSV計画作成、ページ検証、UI走査、結果確定、成功/失敗判定をつなぎます。
細かいPolicy、DOM operation、出力I/Oの実装は持ちません。

## 関数ごとの役割

| 関数 | 役割 |
|---|---|
| `Initialize-ScanTargetSyncWorkflow` | 出力ディレクトリを準備し、開始ログを出す |
| `New-ScanTargetSyncValidatedPlan` | CSV読み込みから同期Plan検証までを行う |
| `Test-ScanTargetSyncNoSyncTarget` | 同期対象がない場合の早期終了条件を判定する |
| `Invoke-ScanTargetSyncScanAndSync` | ページを開き、UI全件走査と同期を実行する |
| `Complete-ScanTargetSyncWorkflow` | 結果検証、サマリ、終了CSV出力を行う |
| `Assert-ScanTargetSyncWorkflowSucceeded` | 最終的な失敗有無を判定し、失敗があれば例外にする |

## 大きな流れ

```text
Initialize
  ↓
New Validated Plan
  ↓
No sync targetならCSV出力して終了
  ↓
Open page and validate
  ↓
Scan and sync UI
  ↓
Validate results
  ↓
Export final CSVs
  ↓
Assert succeeded
```

## ここに書かないこと

- CSV日付parseの詳細
- ON/OFF判定式
- DOM helper method名
- ファイル書き出しの低レベル処理

## 変更時に見るテスト

- `main/tests/ScanTargetSync.Workflow.Tests.ps1`
- `main/tests/ScanTargetSync.Workflow.Normal.Tests.ps1`
- `main/tests/Architecture.Tests.ps1`

## 更新条件

Workflow全体の順序、早期終了条件、結果確定手順、成功/失敗判定が変わった場合に更新します。
