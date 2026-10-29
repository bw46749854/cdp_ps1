# DOM helperとDOM bundleの境界

## 1. この文書の目的

この文書は、PowerShell側の処理がどのようにブラウザ内JavaScriptへつながるのかを説明する。

このプロジェクトでは、Feature moduleが直接HTML要素を探したり、直接JavaScript文字列を組み立てたりしない構成になっている。代わりに、Foundationが次の2つの作業を担当する。

```text
1. DOM JavaScript bundleをブラウザに登録する
2. 登録済みJavaScript helperのメソッドを呼び出す
```

この2つを分けて理解する必要がある。

---

## 2. 用語整理

| 用語 | 意味 |
|---|---|
| DOM | ブラウザ内にあるHTML画面構造。ボタン、表、チェックボックスなどをJavaScriptから操作できる形で表したもの |
| DOM helper | ブラウザ内に登録されるJavaScriptオブジェクト。例: `window.__InstalledAppExportDomHelper` |
| DOM bundle | 複数のJavaScriptファイルを結合してブラウザへ投入するスクリプト全体 |
| Feature DOM file | `dom/features/installed-app-export/*.js` のような、機能別のJavaScriptファイル |
| Operation | PowerShell側から見た画面操作名。例: `ClickCsvButton` など |
| MethodName | JavaScript helper側の実メソッド名。PowerShellのOperationが最終的に呼ぶJavaScript関数名 |
| Contract | JavaScript側が「画面が期待通りか」を確認して返す結果形式 |

---

## 3. 全体の呼び出し経路

DOM系ジョブでは、概ね次の順番で処理が進む。

```text
run_job.ps1
  ↓
Invoke-FoundationEntrypoint
  ↓
Initialize-FoundationRuntime
  ↓
Context.JobDefinition を作る
  ↓
Feature module の Invoke-xxxJob
  ↓
Register-FoundationDomBundle -Context $Context
  ↓
Register-DomBundle
  ↓
Get-DomBundleDefinition
  ↓
Get-DomBundleScript
  ↓
Invoke-FoundationJavaScript
  ↓
ブラウザ内に window.__xxxDomHelper が登録される
```

その後、実際の画面操作では次の経路を通る。

```text
Feature Workflow
  ↓
Feature DomAdapter
  ↓
Feature DomOperations
  ↓
Invoke-FoundationDomHelperMethod
  ↓
New-FoundationDomHelperMethodExpression
  ↓
Invoke-FoundationJavaScript
  ↓
window.__xxxDomHelper.<methodName>(...args)
```

ここで重要なのは、**DOM bundle登録**と**DOM helper呼び出し**は別の処理だという点である。

---

## 4. なぜJavaScriptを事前登録するのか

PowerShellから毎回長いJavaScriptを直接送る方法もある。しかし、このプロジェクトではその方法を避けている。

理由は次の通り。

| 理由 | 説明 |
|---|---|
| 責務を分けるため | HTML要素の探索やクリックはJavaScript側に閉じ込める |
| PowerShell側を業務操作名に寄せるため | PowerShell側は `syncEndpointCheckbox` のような意味のある操作名で呼べる |
| テストしやすくするため | JavaScript helperの存在やメソッド名をテストで検証できる |
| 画面変更の影響を局所化するため | selector変更は主にDOM JavaScript側に閉じる |

---

## 5. `DomFeaturePaths` の意味

`foundation.jobs.psd1` では、DOMを使うジョブに `DomFeaturePaths` が定義されている。

例として、InstalledAppExportジョブでは次のようなファイル群を指定する。

```text
contract.js
list.js
detail.js
apps.js
actions.js
index.js
```

これは単なるファイル一覧ではない。

この配列は、**ブラウザに読み込ませる順番**を意味する。

たとえば `index.js` が他のファイルで定義された部品をまとめて `window.__InstalledAppExportDomHelper` を作る構成なら、`index.js` は最後に読み込まれる必要がある。順番を変えると、JavaScript側で「まだ定義されていない関数を参照する」問題が起きる可能性がある。

---

## 6. `UsesDom = $false` の意味

LastMonthInstallExtractジョブやCompositeJobsは、ブラウザDOMを直接使わない。

そのため、`foundation.jobs.psd1` では次のように表す。

```text
UsesDom = $false
```

この指定があるジョブに対してDOM bundle登録をしようとすると、Foundation基盤はエラーにする。

これは、次のような設計事故を防ぐためである。

```text
DOMを使わないはずのジョブ
  ↓
誤って Register-FoundationDomBundle を呼ぶ
  ↓
不要なブラウザ依存が混入する
```

ファイル処理だけで完結するジョブは、ブラウザに依存しないまま保つ必要がある。

---

## 7. DOM契約チェックとは何か

DOM JavaScript helperは、単にクリックや値取得だけをするわけではない。

画面が期待通りの状態かを確認し、次のような形の結果を返す処理もある。

```text
ContractResult
  scope        : どの契約を確認したか
  ok           : 全体として成功か
  fatalCount   : 処理を止めるべき違反数
  warningCount : 警告扱いの違反数
  checks       : 個別チェック結果の一覧
  details      : 補足情報
```

PowerShell側はこの結果を受け取り、`fatalCount` が1以上なら処理を止める。

この仕組みによって、例えば次のような状況を早期に検出できる。

```text
- 画面に期待するボタンがない
- 表の構造が変わっている
- helper自体が登録されていない
- selectorが複数要素に一致してしまう
```

---

## 8. 混乱しやすい点

### 8.1 PowerShellがHTMLを直接触っているわけではない

Feature moduleの名前を見ると、PowerShellが画面を直接操作しているように見える。

しかし実際には、PowerShellはJavaScript文字列をCDP経由でブラウザへ送り、ブラウザ内JavaScriptに操作を任せている。

```text
PowerShell関数
  ↓
JavaScript式を作る
  ↓
CDPでブラウザへ送る
  ↓
ブラウザ内でDOMを操作する
```

### 8.2 `Register-DomBundle` と `Register-FoundationDomBundle` は似ているが違う

| 関数 | 役割 |
|---|---|
| `Register-DomBundle` | RootPath、JobName、JobDefinitionなどを受け取り、実際にDOM bundleを登録する低めの関数 |
| `Register-FoundationDomBundle` | ContextからRootPath、JobName、JobDefinitionを取り出して `Register-DomBundle` を呼ぶFacade |

Feature moduleからは、通常 `Register-FoundationDomBundle -Context $Context` の形で使う方が読みやすい。

### 8.3 `Invoke-FoundationDomHelperMethod` は直接DOMを触らない

この関数は、DOM helperメソッドを呼ぶJavaScript式を作り、それを `Invoke-FoundationJavaScript` に渡す。

つまり、この関数の責務は「ブラウザ操作」そのものではなく、**PowerShellからJavaScript helperを呼ぶための橋渡し**である。

---

## 9. この範囲を変更するときの判断基準

この範囲は共通基盤なので、安易に変更すると全DOM系ジョブに影響する。

変更前に次を確認する。

| 変更内容 | 確認すること |
|---|---|
| `DomFeaturePaths` の解釈を変える | InstalledAppExport / ScanTargetSync / DeviceListExport のDOM登録順が壊れないか |
| JavaScript式生成を変える | 引数のJSON化、null、bool、配列、文字列エスケープが壊れないか |
| helper名検証を緩める | 任意JavaScript式の混入リスクが上がらないか |
| MissingHelperBehaviorを変える | helper未登録時に、契約違反として扱うべき場面までnull扱いにならないか |
| DOM契約結果の判定を変える | fatalを見逃して、壊れた画面のまま処理が進まないか |

---

## 10. 本ドキュメント内容の要点

この文書を読み終わった時点で、次を説明できればよい。

```text
- DOM bundleは、FeatureごとのJavaScriptファイルをブラウザへ登録する仕組みである
- DOM helperは、登録済みJavaScriptオブジェクトのメソッドをPowerShellから呼ぶ仕組みである
- DOM contractは、画面構造やhelper登録状態が期待通りかを確認する結果形式である
- DOMを使わないジョブにDOM bundle登録をしてはいけない
- Feature moduleがraw JavaScriptを直接組み立てないのは、責務境界を保つためである
```
