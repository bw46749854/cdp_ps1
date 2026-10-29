# ScanTargetSync internal/Rules.ps1

## この文書の位置づけ

この文書は `main/modules/ScanTargetSync/internal/Rules.ps1` の個別ファイルドキュメントです。
入力CSVの各行を、ON対象、OFF対象、CSVデータエラーに分類するPolicy層を説明します。

## このファイルを変更する典型ケース

- 業務判定条件、抽出条件、CSVエラー条件が変わった場合
- Policy判定結果の形や分類名が変わった場合
- ルール説明文やテストで固定している境界が変わった場合


## このファイルの責務

`Rules.ps1` は業務判定の中心です。
ブラウザ、DOM helper、ファイルI/O、ログ出力、時刻取得には依存しません。

主な責務は次です。

```text
CSV行の文字列を判定しやすい形に正規化する
手動スキャンの完了日・最終通信日の妥当性を評価する
ON対象 / OFF対象 / CSVエラーを分類する
Policy判定結果を後続Workflowが扱いやすい行構造へ変換する
ルール説明文を返す
```

## 判定の大枠

`Get-ScanTargetSyncEvaluation` は、1行分のCSVを見て評価結果を返します。
評価結果は概念上、次のいずれかです。

| 区分 | 意味 | 後続での扱い |
|---|---|---|
| CSVエラー | 必須日付が解釈できない、業務判定に使えない | CSVデータエラーCSVへ出す |
| ON対象 | 手動スキャン対象としてチェックONへ揃える | `Reconciliation.ps1` でSyncRow化 |
| OFF対象 | 手動スキャン対象外としてチェックOFFへ揃える | `Reconciliation.ps1` でSyncRow化 |
| 非対象 | 同期もエラー出力もしない | Plan上の同期対象には入れない |

## 主な関数群

| 関数群 | 役割 |
|---|---|
| `ConvertTo-ScanTargetSyncOptionalText` | CSVセル値を比較しやすい文字列へ正規化する |
| `Convert-ScanTargetSyncRuleDate` / `Get-ScanTargetSyncElapsedDays` | 判定用日付と経過日数を扱う |
| `New-ScanTargetSyncEvaluationResult` | 評価結果共通形を作る |
| `Test-ScanTargetSyncScanCompletionIsMissing` | 手動スキャンの完了日が未入力か判定する |
| `New-ScanTargetSyncMissingCompletionEvaluation` | 完了日未入力をON対象評価へ変換する |
| `New-ScanTargetSyncCsvErrorEvaluation` | 日付不正などをCSVエラー評価へ変換する |
| `New-ScanTargetSyncTargetEvaluation` | ON/OFF対象評価を作る |
| `New-ScanTargetSyncNonTargetEvaluation` | 同期対象外評価を作る |
| `Get-ScanTargetSyncEvaluation` | CSV行1件のPolicy判定を行う |
| `New-ScanTargetSyncTargetRow` | 後続で扱う対象行構造を作る |
| `Get-ScanTargetSyncTargetExtraction` | CSV全体をON行、OFF行、CSVエラー行へ分類する |
| `Get-ScanTargetSyncRuleDescription` | 現在の判定ルール説明を返す |

## `Get-ScanTargetSyncTargetExtraction` の位置づけ

この関数は、CSV行配列を受け取り、Policy判定の結果をまとめます。
後続の `Workflow.CsvPlan.ps1` は、この結果を使って同期Planを作ります。

```text
CsvRows
  ↓
Get-ScanTargetSyncEvaluation per row
  ↓
OnRows / OffRows / CsvErrorRows
```

ここではUIにendpointが存在するかどうかは見ません。
CSVだけで判断できることに限定します。

## ここに書かないこと

`Rules.ps1` に次を追加してはいけません。

- ブラウザページを開く処理
- DOM helper呼び出し
- UI一覧の走査
- endpoint重複の全体整合処理
- 結果CSVの書き出し
- ログ出力やファイル操作

## 変更時に見るテスト

- `main/tests/ScanTargetSync.Rules.Tests.ps1`
- `main/tests/ScanTargetSync.CsvInput.Tests.ps1`
- `main/tests/ScanTargetSync.Workflow.Tests.ps1`
- `main/tests/Architecture.Tests.ps1`

## 更新条件

ON/OFF判定、CSVエラー条件、評価結果構造、対象行構造、ルール説明が変わった場合に更新します。
