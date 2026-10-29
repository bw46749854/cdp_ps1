# DOM JavaScript テスト

## 1. 対象

このドキュメントでは、`main/tests/js` 配下を扱う。

```text
tests/js/device-list-export.dom.behavior.test.js
tests/js/device-list-export.identity.contract.test.js
tests/js/dom.contract.sanitize.test.js
tests/js/dom.syntax.test.js
tests/js/installed-app-export.dom.behavior.test.js
tests/js/scan-target-sync.dom.behavior.test.js
```

これらはNode.jsでDOM helperの振る舞いを確認するテストである。  
実ブラウザではなく、FakeElement / FakeDocument などの簡易DOMを作って、JavaScript helperを評価している。

---

## 2. dom.syntax.test.js

このテストは、DOM JavaScriptファイルが構文として読み込めることを確認する。

主な意味は以下である。

```text
- contract.js / list.js / actions.js / index.js などをNodeのvmで読み込める
- 構文エラーがない
- bundle順序の前提を壊していない
```

このテストが落ちる場合、JavaScript構文ミス、IIFE構造の破壊、または依存順序の問題を疑う。

---

## 3. dom.contract.sanitize.test.js

DOM契約結果をPowerShellへ返す前に、detailsが安全に整形されることを確認する。

守っている観点は以下である。

```text
- DOM elementや循環参照など、JSON化しにくい値を安全に扱う
- 契約失敗情報がPowerShell側で読める形になる
- contract resultが過剰に壊れたオブジェクトにならない
```

PowerShell側では `DomContract.ps1` がこの結果を受け取る。  
したがって、このテストはJavaScript側とPowerShell側の境界安定性に関係する。

---

## 4. device-list-export.dom.behavior.test.js

DeviceListExport DOM helperの画面操作を確認する。

主な確認対象は以下である。

```text
- window.__DeviceListExportDomHelper が登録される
- 期待methodが存在する
- ページ契約チェックが通る
- 操作ボタンを見つける
- 操作ボタンをクリックする
- 操作メニューready判定を返す
- エクスポートmenu itemを見つける
- エクスポートmenu itemをクリックする
- クリック後契約を確認する
```

対応するPowerShell側は以下である。

```text
modules/DeviceListExport/internal/DomOperations.ps1
modules/DeviceListExport/internal/DomAdapter.ps1
modules/DeviceListExport/internal/Workflow.ps1
```

このテストが落ちる場合、画面要素探索ロジックまたはDOM helper method名・戻り値契約を確認する。

---

## 5. device-list-export.identity.contract.test.js

DeviceListExportとScanTargetSyncは、どちらも同じ「端末一覧系の画面」を前提にする。  
このテストは、DeviceListExport側のidentity contractが期待どおり画面を判定できることを確認する。

主に見るべき観点は以下である。

```text
- 対象ページと別ページを識別できる
- device default / sensor / navigation などの画面要素を使って判定する
- 画面構造が変わった場合に契約違反として検出できる
```

---

## 6. installed-app-export.dom.behavior.test.js

InstalledAppExport DOM helperの振る舞いを確認する。

確認対象は以下である。

```text
- window.__InstalledAppExportDomHelper が登録される
- 一覧行を検出する
- スクロール対象コンテナを扱う
- 行キーを作る
- 詳細パネルを開く
- 詳細パネル内の端末名を確認する
- アプリタブを開く
- アプリ一覧を確認する
- CSVボタンをクリックする
- 詳細パネルを閉じる
```

InstalledAppExportはDOM操作範囲が広いため、このJSテストは特に重要である。

PowerShell側の `InstalledAppExport/internal/RowAction.ps1` は、これらのJS helper結果を前提に1台分のCSV取得を進める。  
JS側の戻り値構造を変える場合、PowerShell側のDomOperations / DomAdapter / RowActionも確認する必要がある。

---

## 7. scan-target-sync.dom.behavior.test.js

ScanTargetSync DOM helperの振る舞いを確認する。

主な確認対象は以下である。

```text
- window.__ScanTargetSyncDomHelper が登録される
- 対象scopeを検出する
- endpoint行を検出する
- checkbox状態を読み取る
- desired stateに合わせてcheckboxを同期する
- sync結果を安定したオブジェクトで返す
- 後続メニュー契約を確認する
```

ScanTargetSyncでは、CSV側のON/OFF計画とUI側のcheckbox状態を同期する。  
このテストは、そのUI実装側の土台を守っている。

---

## 8. PowerShell側テストとの関係

DOM JavaScriptのテストだけでは、PowerShell側operationとの対応は保証できない。

そのため、以下の組み合わせで読む。

```text
JS behavior test
  → JavaScript helper単体の振る舞いを確認する

*.DomOperations.Tests.ps1
  → PowerShell側operation定義の妥当性を確認する

Dom.OperationRegistryContract.Tests.ps1
  → PowerShell側MethodNameがJS bundle内に実在することを確認する

Documentation.Tests.ps1
  → DomOperations.ps1 と PowerShell_DOM対応表.md のdocs同期を確認する
```

つまり、DOMまわりを変更したときは、JS test、PowerShell operation test、operation registry contract、ドキュメント品質ゲートをセットで見る。

---

## 9. DOM JavaScript変更時の危険箇所

次の変更は影響が大きい。

```text
window.__XxxDomHelper の名前を変える
method名を変える
戻り値の ok / value / details / action などの形を変える
contract resultのscope名を変える
fatal / warning の分類を変える
selector条件を弱める
selector条件を強める
index.jsの登録順序を変える
```

これらは、PowerShell側 `DomOperations.ps1`、`DomContract.ps1`、`DomHelper.ps1`、各Workflowに影響する可能性がある。

DOM JavaScript の method 名、contract scope、戻り値構造を変更した場合は、JS test だけでなく、PowerShell側の DomOperations / DomAdapter / Workflow と `docs/08_DOM_JavaScript` の対応も確認する。

---

## 10. selector と contract scope を変更する場合

selector を変更した場合は、次の2つを分けて確認する。

```text
1. JavaScript helper単体として期待どおり候補を拾えるか
2. PowerShell側operationとして、どの契約失敗・操作失敗として見えるか
```

たとえば、候補が0件になる変更と候補が複数件になる変更は、どちらも失敗だが意味が違う。0件は画面変更や読み込み未完了の可能性があり、複数件は誤クリックの危険がある。

contract scope を変更した場合は、次を同時に確認する。

```text
- JavaScript側 contractResult(scope, ...)
- PowerShell側 DomOperations.ps1 の ContractScope
- docs/08_DOM_JavaScript/PowerShell_DOM対応表.md
- docs/08_DOM_JavaScript/DOM契約とselector診断の読み方.md
- Dom.OperationRegistryContract.Tests.ps1
```

---

## 11. この文書を更新する条件

DOM JavaScriptテストの対象ファイル、守る契約、PowerShell側テストとの関係、DOM変更時の確認範囲が変わった場合に更新する。
