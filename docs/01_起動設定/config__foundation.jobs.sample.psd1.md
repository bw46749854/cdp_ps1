# main/config/foundation.jobs.sample.psd1

## この文書の位置づけ

この文書は `main/config/foundation.jobs.sample.psd1` の個別ファイルドキュメントです。
実運用で使う `foundation.jobs.psd1` を作るためのサンプルジョブレジストリの読み方を説明します。

## このファイルを変更する典型ケース

- 設定キー、既定値、環境ごとに編集する項目が変わった場合
- Jobごとの設定構造や連携Job設定が変わった場合
- sampleから実設定を作る手順や注意点が変わった場合


## このファイルの役割

`foundation.jobs.sample.psd1` は、JobNameと実装moduleの対応を定義する雛形です。
初期導入時はこのsampleをコピーして `foundation.jobs.psd1` を作ります。

```text
foundation.jobs.sample.psd1
  ↓ copy / rename
foundation.jobs.psd1
  ↓
JobName → ModulePath / CommandName / DomFeaturePaths
```

## 主なキー

| キー | 意味 |
|---|---|
| `ModulePath` | 読み込むPowerShell module path |
| `CommandName` | module import後に実行する公開関数名 |
| `DomFeaturePaths` | DOMを使うJobで注入するJavaScript feature file群 |
| `UsesDom` | DOMを使わないJobでは `$false` にする |

## DOM Feature Paths の注意

DOMを使うJobでは、JavaScript fileの順序が意味を持ちます。
`contract.js` や個別機能を先に読み、最後に `index.js` で helper を公開する構成です。
順序を変える場合は、DOM JavaScriptドキュメントとJSテストを確認してください。

## sample編集時の注意

- `JobName` を増やす場合は、対応するmoduleとexport済みcommandが必要です。
- `UsesDom = $false` のJobに `DomFeaturePaths` を持たせないでください。
- Composite Jobは `modules/CompositeJobs/CompositeJobs.psm1` を使い、子Jobの内部処理を再実装しません。
- sample更新時は、実際の `foundation.jobs.psd1` ドキュメントも更新対象にしてください。

## 詳細参照

- `docs/01_起動設定/config__foundation.jobs.psd1.md`
- `docs/02_Foundation/internal__JobRegistry.ps1.md`
- `docs/02_Foundation/internal__DomBundle.ps1.md`
- `docs/08_DOM_JavaScript/PowerShell_DOM対応表.md`
- `docs/07_CompositeJobs/CompositeJobs_ジョブ連携.md`

## 更新条件

sampleのJobName、module path、command name、DOM feature path、`UsesDom` の方針が変わった場合に更新します。
