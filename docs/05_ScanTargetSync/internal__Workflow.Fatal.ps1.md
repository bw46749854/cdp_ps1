# ScanTargetSync internal/Workflow.Fatal.ps1

## この文書の位置づけ

この文書は `main/modules/ScanTargetSync/internal/Workflow.Fatal.ps1` の個別ファイルドキュメントです。
Workflow途中で致命的エラーが起きた場合に、可能な限り失敗CSVを出すための保険処理を説明します。

## このファイルを変更する典型ケース

- 処理順序、分岐、リトライ、失敗時の継続方針が変わった場合
- Policy判定結果と依存portのつなぎ方が変わった場合
- Workflowが集約する結果や後続処理への渡し方が変わった場合


## このファイルの責務

`Export-ScanTargetSyncFatalResultIfNeeded` は、終了CSVがまだ出力されていない場合に、`__SCRIPT_FATAL__` の失敗行を追加し、終了CSV出力を試みます。

## 例外処理の方針

異常終了時のCSV出力自体が失敗する可能性があります。
この関数では、その二次的な出力失敗で元の致命的エラーを隠さないようにします。

```text
元のエラー
  ↓
Fatal result exportを試みる
  ↓
出力失敗はWarning扱い
  ↓
元のエラーを上位で再throw
```

## 変更時に見るテスト

- `main/tests/ScanTargetSync.Workflow.Tests.ps1`
- `main/tests/ScanTargetSync.Output.Tests.ps1`

## 更新条件

致命的エラー時の失敗行、終了CSV出力の保険処理、二次例外の扱いが変わった場合に更新します。
