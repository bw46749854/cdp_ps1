# ScanTargetSync internal/Workflow.Display.ps1

## この文書の位置づけ

この文書は `main/modules/ScanTargetSync/internal/Workflow.Display.ps1` の個別ファイルドキュメントです。
チェック状態の目的や変更結果を、人が読みやすいログ文言へ変換する小さな表示補助を説明します。

## このファイルを変更する典型ケース

- 処理順序、分岐、リトライ、失敗時の継続方針が変わった場合
- Policy判定結果と依存portのつなぎ方が変わった場合
- Workflowが集約する結果や後続処理への渡し方が変わった場合


## 関数ごとの役割

| 関数 | 役割 |
|---|---|
| `Get-CheckboxDesiredStateDisplay` | `ON` / `OFF` などの目的状態を表示用文言へ変換する |
| `Get-CheckboxChangeResultDisplay` | DOM helper結果から、変更済み / 変更不要などの結果表示を作る |

## ここに書かないこと

- ON/OFF判定そのもの
- DOM操作
- 結果CSVの出力

## 更新条件

ログや失敗理由に表示する目的状態・変更結果の文言方針が変わった場合に更新します。
