# DOM JavaScript の読み方

この範囲は、PowerShell から CDP 経由でブラウザ内へ登録される JavaScript helper です。PowerShell側の `DomOperations.ps1` は、`window.__DeviceListExportDomHelper`、`window.__InstalledAppExportDomHelper`、`window.__ScanTargetSyncDomHelper` のメソッド名を指定して呼び出します。

## 1. この層の役割

DOM JavaScript は、ブラウザ画面の DOM 構造を直接調べ、必要な要素を探し、クリックやスクロールを実行します。PowerShell 側は CSS selector や HTML 構造を直接知らず、業務名の operation だけを呼びます。

```text
PowerShell Workflow
  ↓ 業務名で呼ぶ
DomAdapter.ps1
  ↓ operation名で呼ぶ
DomOperations.ps1
  ↓ helper名 + method名で呼ぶ
Foundation/DomHelper.ps1
  ↓ CDP Runtime.evaluate
ブラウザ内 JavaScript helper
  ↓ document.querySelector / element.click / scrollTop
実画面DOM
```

PowerShell はジョブ全体の順序、設定、ログ、ファイル出力を扱います。DOM要素の探索、可視判定、クリック可能判定、スクロールはブラウザ内 JavaScript 側へ閉じ込めます。

---

## 2. helper の組み立て方

各 feature は複数の `*.js` に分かれています。`index.js` が最終的な helper オブジェクトを作り、その他のファイルは `window.__XxxDomHelperParts` に part object を追加します。

```text
contract.js / list.js / actions.js など
  ↓
window.__XxxDomHelperParts.push(part)
  ↓
index.js
  ↓
Object.assign(domHelper, part)
  ↓
window.__XxxDomHelper = domHelper
```

`index.js` は最後に読み込む前提です。先に読むと、合成対象の part object がまだ登録されておらず、PowerShell側から呼ぶ helper method が欠落します。

---

## 3. 変更時に最も危険な点

DOM JavaScript の修正で最も危険なのは、「候補が複数あるのに最初の1件をクリックする」変更です。このプロジェクトでは、重要なクリック操作では原則として候補数が1件であることを確認します。候補数が0件なら画面変更または読み込み未完了、候補数が複数なら誤クリックの危険として扱います。

selector を弱める変更は、別の画面要素を候補に含める可能性があります。selector を強める変更は、画面の軽微な差で候補が0件になる可能性があります。どちらも PowerShell側の operation 名だけを見ていても分からないため、JavaScript側の契約確認と JS test を同時に確認します。

---

## 4. PowerShell側との対応表

| Feature | helper名 | PowerShell側ファイル | JavaScript側入口 |
|---|---|---|---|
| DeviceListExport | `__DeviceListExportDomHelper` | `main/modules/DeviceListExport/internal/DomOperations.ps1` | `main/dom/features/device-list-export/index.js` |
| InstalledAppExport | `__InstalledAppExportDomHelper` | `main/modules/InstalledAppExport/internal/DomOperations.ps1` | `main/dom/features/installed-app-export/index.js` |
| ScanTargetSync | `__ScanTargetSyncDomHelper` | `main/modules/ScanTargetSync/internal/DomOperations.ps1` | `main/dom/features/scan-target-sync/index.js` |

operation と method の完全な対応は `docs/08_DOM_JavaScript/PowerShell_DOM対応表.md` を参照してください。

---

## 5. 読む順番

DOM JavaScript を変更する場合は、次の順で読むと追いやすいです。

```text
1. docs/08_DOM_JavaScript/PowerShell_DOM対応表.md
2. docs/08_DOM_JavaScript/DOM契約とselector診断の読み方.md
3. 対象 feature の index.js.md
4. 対象 feature の contract.js.md
5. 対象 operation を実装している list.js.md / actions.js.md / export.js.md / apps.js.md
6. 対応する main/modules/<Feature>/internal/DomOperations.ps1
7. 対応する tests/js/*.test.js と *.DomOperations.Tests.ps1
```

`contract.js` は長いですが、最初から細部を全部読む必要はありません。まずは「どの scope の契約か」「fatal と warning の分類は何か」「PowerShell側の `ContractScope` と一致しているか」を確認してください。

---

## 6. 変更時に同時確認するもの

DOM JavaScript の method 名、contract scope、戻り値構造を変更した場合は、JavaScript ファイルだけでなく、次も確認します。

| 変更したもの | 同時に確認するもの |
|---|---|
| helper名 | `DomOperations.ps1` の `HelperName`, `PowerShell_DOM対応表.md` |
| method名 | `DomOperations.ps1` の `MethodName`, JS behavior test |
| contract scope | `DomOperations.ps1` の `ContractScope`, `DOM契約とselector診断の読み方.md` |
| 戻り値構造 | `DomAdapter.ps1`, Workflow, JS test |
| selector | contract docs, JS behavior test, 画面契約の fatal / warning 分類 |
| 読み込み順 | `foundation.jobs.psd1` の `DomFeaturePaths`, `dom.syntax.test.js` |

---

## 7. この文書を更新する条件

DOM helper の構成、読む順番、PowerShell側との境界、変更時の参照先が変わった場合に更新します。個別 method の細かい仕様だけが変わった場合は、対応する個別ファイルドキュメントを更新します。
