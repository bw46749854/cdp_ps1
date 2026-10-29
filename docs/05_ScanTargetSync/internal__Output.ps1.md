# ScanTargetSync internal/Output.ps1

## この文書の位置づけ

この文書は `main/modules/ScanTargetSync/internal/Output.ps1` の個別ファイルドキュメントです。
CSVデータエラーCSVとチェック処理失敗CSVの行形状・出力境界を説明します。

## このファイルを変更する典型ケース

- 出力CSVの列、ファイル名、文字コード、書き出し単位が変わった場合
- 成功行・失敗行・summaryの形が変わった場合
- 出力前の安全確認や既存ファイル扱いが変わった場合


## このファイルの責務

`Output.ps1` は、最終的にファイルへ出すCSVの行構造と出力処理を担当します。
Workflowは出力タイミングを決め、物理出力はこのファイルの関数を通します。

## 関数ごとの役割

| 関数 | 役割 |
|---|---|
| `New-ScanTargetSyncFailureRow` | チェック処理失敗CSV用の行を作る |
| `Export-ScanTargetSyncCsvErrorCsv` | CSVデータエラー行をCSVへ出力する |
| `Export-ScanTargetSyncFailureCsv` | チェック処理失敗行をCSVへ出力する |

## 失敗行とCSVエラー行の違い

| 種類 | 由来 | 例 |
|---|---|---|
| CSVデータエラー | 入力CSVだけで検出できる不備 | 日付不正、endpoint重複 |
| チェック処理失敗 | UI走査・同期・結果検証で検出する異常 | UIにendpointがない、data-id衝突、同期失敗 |

## ここに書かないこと

- ON/OFF判定
- UI全件走査
- DOM helper method名
- Workflowの分岐順序

## 変更時に見るテスト

- `main/tests/ScanTargetSync.Output.Tests.ps1`
- `main/tests/ScanTargetSync.Workflow.Tests.ps1`

## 更新条件

出力CSVの列、行構造、空データ時の出力方針、ファイル出力の境界が変わった場合に更新します。
