# ScanTargetSync internal/Runner.ps1

## この文書の位置づけ

この文書は `main/modules/ScanTargetSync/internal/Runner.ps1` の個別ファイルドキュメントです。
`ScanTargetSync` Jobの公開入口と、最上位Workflowへ処理を渡す外枠を説明します。

## このファイルを変更する典型ケース

- Job開始時の初期化、依存解決、最終結果検査が変わった場合
- Context / Config / JobSettings の渡し方が変わった場合
- Workflow呼び出し前後のログや終了判定が変わった場合


## このファイルの責務

`Runner.ps1` はJobの入口です。
Contextを受け取り、初期化を行い、`Invoke-ScanTargetSyncSyncWorkflow` を呼びます。

## 関数ごとの役割

| 関数 | 役割 |
|---|---|
| `Initialize-ScanTargetSyncJob` | Workflow依存を解決し、出力ディレクトリ初期化に必要な依存を検証する |
| `Invoke-ScanTargetSyncJob` | 外部から呼ばれるJob入口。初期化後、Workflowを呼ぶ |

## Runnerに置くべきではないもの

Runnerは外枠であり、次を持ちません。

- CSVの業務判定
- DOM操作
- UI走査ループ
- 結果検証
- CSV出力の詳細

これらは `Workflow*.ps1`、`Rules.ps1`、`DomOperations.ps1`、`Output.ps1` へ分離します。

## 変更時に見るテスト

- `main/tests/ScanTargetSync.Workflow.Tests.ps1`
- `main/tests/ScanTargetSync.Dependencies.Tests.ps1`
- `main/tests/Architecture.Tests.ps1`

## 更新条件

公開入口、初期化順序、Workflow呼び出し方、RunnerとWorkflowの責務境界が変わった場合に更新します。
