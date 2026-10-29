# modules/Foundation/internal/DomBundle.ps1 設計書

## 1. このファイルを一言でいうと

このファイルは、`foundation.jobs.psd1` のジョブ定義からDOM JavaScriptファイルの一覧を解決し、それらを1つのJavaScript bundleとして結合して、ブラウザに登録するためのファイルである。

DOMを使うジョブでは、PowerShell側の処理を始める前に、ブラウザ内へFeature専用のJavaScript helperを入れておく必要がある。

このファイルはその入口である。

---

## このファイルを変更する典型ケース

- DOM bundle生成、helper登録、contract検証の方針が変わった場合
- DOM helper未登録時の扱いや戻り値契約が変わった場合
- FeatureのJavaScript helperとの境界が変わった場合


## 2. このファイルが担当する範囲

このファイルの責務は、次の4つに分けられる。

| 領域 | 内容 |
|---|---|
| ジョブ定義の読み取り | `JobDefinition` から `DomFeaturePath` / `DomFeaturePaths` を読む |
| DOM対象ジョブの検証 | `UsesDom = $false` のジョブにDOM bundle登録をさせない |
| DOMファイルの解決 | 相対パスをリポジトリRootからの絶対パスへ変換する |
| DOM bundle登録 | JavaScriptファイルを結合して `Invoke-FoundationJavaScript` でブラウザへ送る |

---

## 3. このファイルが担当しない範囲

| 担当しないこと | 担当ファイル |
|---|---|
| 実際にCDPでJavaScriptを実行する | `CdpRuntime.ps1` |
| JavaScript helperメソッドを呼ぶ式を作る | `DomHelper.ps1` |
| DOM契約チェック結果を評価する | `DomContract.ps1` |
| Feature固有のJavaScript実装 | `dom/features/*/*.js` |
| JobNameからJobDefinition全体を検証する | 主に `JobRegistry.ps1` |

このファイルは「DOM JavaScriptをどこから読み、どう登録するか」に集中している。

---

## 4. このファイルが必要になる実行シナリオ

DOM系ジョブの起動時に使われる。

代表的な流れは次である。

```text
Invoke-InstalledAppExportJob / Invoke-ScanTargetSyncJob / Invoke-DeviceListExportJob
  ↓
Register-FoundationDomBundle -Context $Context
  ↓
Register-DomBundle
  ↓
Get-DomBundleDefinition
  ↓
Get-FoundationDomFeaturePathsFromDefinition
  ↓
Get-DomBundleScript
  ↓
Invoke-FoundationJavaScript
  ↓
ブラウザ内に window.__InstalledAppExportDomHelper などが登録される
```

この登録が終わっていない状態でFeature moduleがDOM操作を呼ぶと、JavaScript側のhelperが存在しないため失敗する。

---

## 5. 入力となるJobDefinitionの形

このファイルが特に見るのは、`foundation.jobs.psd1` の各ジョブ定義である。

DOMを使うジョブは、次のように `DomFeaturePaths` を持つ。

```text
InstalledAppExport
  ModulePath      : modules\InstalledAppExport\InstalledAppExport.psm1
  CommandName     : Invoke-InstalledAppExportJob
  DomFeaturePaths : 複数のJavaScriptファイルパス
```

DOMを使わないジョブは、次のように `UsesDom = $false` を持つ。

```text
LastMonthInstallExtract
  ModulePath  : modules\LastMonthInstallExtract\LastMonthInstallExtract.psm1
  CommandName : Invoke-LastMonthInstallExtractJob
  UsesDom     : false
```

この違いは重要である。

`UsesDom = $false` のジョブにDOM bundle登録を許すと、本来ファイル処理だけで完結するジョブにブラウザ依存が混ざってしまう。

---

## 6. `DomFeaturePath` と `DomFeaturePaths`

このファイルは、単数形と複数形の両方を扱える。

| キー | 意味 |
|---|---|
| `DomFeaturePath` | DOM JavaScriptファイルが1つだけの場合 |
| `DomFeaturePaths` | DOM JavaScriptファイルが複数ある場合 |

ただし、両方を同時に指定することはできない。

```text
DomFeaturePath と DomFeaturePaths が同時にある
  ↓
どちらを正とするか曖昧
  ↓
例外にする
```

現在の主要DOMジョブでは、複数ファイルを順番に読み込むため `DomFeaturePaths` が使われている。

---

## 7. DOMファイル順序の意味

`DomFeaturePaths` の順序は重要である。

たとえばInstalledAppExportジョブでは、概ね次のような意味を持つ。

```text
contract.js
  ↓
list.js
  ↓
detail.js
  ↓
apps.js
  ↓
actions.js
  ↓
index.js
```

一般に、最後の `index.js` が他のファイルで定義された部品をまとめて `window.__InstalledAppExportDomHelper` を作る。  
そのため、順番を入れ替えると、JavaScript側でまだ定義されていない部品を参照して失敗する可能性がある。

`DomBundle.ps1` はこの順序を保持して連結する。

---

## 8. このファイル内の関数呼び出しツリー

```text
Register-DomBundle
  ├─ Get-DomBundleDefinition
  │   ├─ Resolve-FoundationDomBundleJobDefinition
  │   │   ├─ Get-FoundationDefaultJobRegistryPath
  │   │   ├─ Import-FoundationJobRegistry
  │   │   └─ Get-FoundationJobDefinition
  │   └─ Get-FoundationDomFeaturePathsFromDefinition
  │       ├─ Test-DomBundleJobDefinitionKey
  │       ├─ Get-DomBundleJobDefinitionRawValue
  │       ├─ Get-FoundationJobDefinitionValue
  │       │   └─ Get-DomBundleJobDefinitionRawValue
  │       └─ ConvertTo-FoundationDomFeaturePathList
  │           └─ Resolve-FoundationJobRegistryPath
  ├─ Get-DomBundleScript
  │   ├─ Assert-DomBundleFileExists
  │   └─ Get-Content
  ├─ Invoke-FoundationJavaScript
  └─ Write-FoundationLog
```

補助関数として、ジョブ定義から値を読む関数群がある。

```text
Test-DomBundleJobDefinitionKey
Get-DomBundleJobDefinitionRawValue
Get-FoundationJobDefinitionValue
```

これらは、`JobDefinition` が hashtable でも pscustomobject でも読めるようにするために存在する。

---

## 9. 関数ごとの説明

## 9.1 Test-DomBundleJobDefinitionKey

### 何をするか

`JobDefinition` に指定キーが存在するかを確認する。

### なぜ必要か

`JobDefinition` は通常hashtableとして扱われるが、テストや変換の都合で `[pscustomobject]` のような形になる可能性もある。

この関数は、次の両方に対応する。

```text
hashtable      → ContainsKey($Key)
pscustomobject → PSObject.Properties[$Key]
```

### 入力

| 引数 | 意味 |
|---|---|
| `Definition` | ジョブ定義 |
| `Key` | 存在確認するキー名 |
| `JobName` | エラーメッセージ用のジョブ名 |

### 出力

キーがあれば `$true`、なければ `$false`。

### 失敗条件

`Definition` が `$null` の場合は例外を投げる。

### 変更時の注意

この関数がhashtableだけにしか対応しなくなると、テストで作る簡易オブジェクトや将来の設定読み替えで壊れやすくなる。

---

## 9.2 Get-DomBundleJobDefinitionRawValue

### 何をするか

`JobDefinition` から指定キーの値を取り出す。

### なぜ必要か

キーが存在しない場合に、PowerShell標準の曖昧な `$null` ではなく、明確なエラーメッセージで止めるためである。

例。

```text
ジョブ定義に必須キーがありません: Jobs.InstalledAppExport.DomFeaturePaths
```

### 入力

| 引数 | 意味 |
|---|---|
| `Definition` | ジョブ定義 |
| `Key` | 取得するキー名 |
| `JobName` | エラー表示用のジョブ名 |

### 出力

指定キーの生の値。

### 失敗条件

指定キーが存在しない場合、例外を投げる。

---

## 9.3 Get-FoundationJobDefinitionValue

### 何をするか

`JobDefinition` から指定キーの値を取り出し、空文字でない文字列として返す。

### なぜ必要か

`ModulePath`、`CommandName`、`DomFeaturePath` のような値は、空文字では意味がない。

```text
キーはあるが値が空
  ↓
パス解決やコマンド解決で後から分かりにくく失敗する
```

そのため、この段階で明確に止める。

### 出力

空でない文字列。

### 失敗条件

| 条件 | 結果 |
|---|---|
| キーがない | 例外 |
| 値が空または空白 | 例外 |

### 注意点

この関数は `DomBundle.ps1` にあるが、名前は `Get-FoundationJobDefinitionValue` である。  
`Bootstrap.ps1` 側で `ModulePath` や `CommandName` を読むときにも使われるため、DOM専用ではない共通的な値取得関数として扱われている。

---

## 9.4 ConvertTo-FoundationDomFeaturePathList

### 何をするか

`DomFeaturePaths` の値を検証し、各要素をRootPath基準の実パスへ変換する。

### なぜ必要か

`DomFeaturePaths` は文字列配列である必要がある。

許可する形。

```text
@(
  'dom\features\installed-app-export\contract.js'
  'dom\features\installed-app-export\list.js'
)
```

許可しない形。

```text
'dom\features\installed-app-export\index.js'   # 単なる文字列
@()                                  # 空配列
@( '', 'dom\features\x.js' )         # 空要素を含む
```

単なる文字列を許可しない理由は、単数ファイルなら `DomFeaturePath` を使う設計だからである。  
`DomFeaturePaths` は「複数ファイルの配列」であることを明確にしている。

### 出力

解決済みパスの配列。

### 失敗条件

| 条件 | 結果 |
|---|---|
| 値がnull | 例外 |
| 文字列単体 | 例外 |
| 配列でない | 例外 |
| 空配列 | 例外 |
| 空要素を含む | 例外 |

### PowerShell文法上のポイント

#### `$Value -is [System.Array]`

PowerShellでは、1件だけの値と配列の区別が曖昧になりやすい。  
ここでは明示的に配列であることを確認している。

#### `return $paths.ToArray()`

.NETのListを、PowerShellで扱いやすい配列へ戻している。

---

## 9.5 Get-FoundationDomFeaturePathsFromDefinition

### 何をするか

`JobDefinition` からDOM feature fileのパス一覧を取得する。

### 判定順序

```text
1. UsesDom キーがあるか確認する
2. UsesDom がある場合、boolean型か確認する
3. UsesDom が false ならDOM bundle登録不可として例外
4. DomFeaturePath の有無を確認する
5. DomFeaturePaths の有無を確認する
6. 両方ある場合は例外
7. 両方ない場合は例外
8. DomFeaturePath があれば単一パスとして返す
9. DomFeaturePaths があれば配列として返す
```

### なぜ必要か

DOMを使うジョブと使わないジョブを明確に分けるためである。

`UsesDom = $false` のジョブでDOMファイルを登録しようとするのは設計違反である。  
この関数はその違反を早期に検出する。

### 変更時の注意

`UsesDom = $false` のチェックを削ると、LastMonthInstallExtractやCompositeJobsのような非DOMジョブにDOM依存を混入させやすくなる。

---

## 9.6 Resolve-FoundationDomBundleJobDefinition

### 何をするか

DOM bundle登録に使う `JobDefinition` を確定する。

### 入力パターン

この関数は2つの使い方に対応している。

```text
1. すでに JobDefinition が渡されている
   → そのまま使う

2. JobDefinition が渡されていない
   → foundation.jobs.psd1 を読んで JobName から取得する
```

### なぜ必要か

通常のジョブ実行時には、`Context.JobDefinition` がすでに存在する。  
しかし、互換性やテストのために、`RootPath` と `JobName` だけからDOM bundleを登録したい場面もある。

この関数はその両方を吸収する。

---

## 9.7 Get-DomBundleDefinition

### 何をするか

外部から見た「DOM bundleに必要なファイル一覧」を取得する中心関数である。

### 処理の流れ

```text
JobName が空でないことを確認
  ↓
Resolve-FoundationDomBundleJobDefinition
  ↓
Get-FoundationDomFeaturePathsFromDefinition
  ↓
配列として返す
```

### 出力

DOM JavaScriptファイルのパス配列。

### 失敗条件

| 条件 | 結果 |
|---|---|
| JobNameが空 | 例外 |
| JobDefinitionが解決できない | 例外 |
| DOM feature pathがない | 例外 |
| UsesDomがfalse | 例外 |

---

## 9.8 Assert-DomBundleFileExists

### 何をするか

DOM bundleに含める各JavaScriptファイルが存在するかを確認する。

### なぜ必要か

存在しないファイルを `Get-Content` で読もうとすると、後段でエラーになる。  
ただし、その時点では「どのジョブのどのDOM bundleが壊れているのか」が分かりにくい。

この関数で先に確認することで、次のような明確なエラーにできる。

```text
DOM bundleファイルが見つかりません: <path>
```

---

## 9.9 Get-DomBundleScript

### 何をするか

複数のDOM JavaScriptファイルを順番に読み込み、1つの文字列に結合する。

### 処理の流れ

```text
Assert-DomBundleFileExists
  ↓
各ファイルを UTF-8 / Raw で読む
  ↓
空行2つで結合する
  ↓
結合済みJavaScript文字列を返す
```

### PowerShell文法上のポイント

#### `Get-Content -Raw -Encoding UTF8`

`-Raw` はファイル全体を1つの文字列として読む。  
JavaScriptファイルを行配列として読むと、結合時に意図しない改行や配列変換が混ざるため、ここでは `-Raw` が適切である。

### 変更時の注意

ファイル結合順を変えてはいけない。  
`DomFeaturePaths` の順番がそのまま実行順になる設計である。

---

## 9.10 Register-DomBundle

### 何をするか

DOM bundle登録の実処理を行う。

### 処理の流れ

```text
Get-DomBundleDefinition
  ↓
Get-DomBundleScript
  ↓
末尾に sourceURL を追加
  ↓
Invoke-FoundationJavaScript
  ↓
戻り値が true か確認
  ↓
ログ出力
```

### `sourceURL` の意味

結合したJavaScriptの末尾に、次のようなコメントを付ける。

```text
//# sourceURL=foundation-InstalledAppExport-dom-bundle.js
```

これは、ブラウザの開発者ツールやエラー表示で、投入されたスクリプトに名前を付けるためのもの。  
実行には必須ではないが、JavaScriptエラーの診断がしやすくなる。

### 戻り値チェック

`Invoke-FoundationJavaScript` の戻り値が `$true` でなければ例外にする。

これは、DOM bundle側のJavaScriptが「登録成功」を明示的に返す契約になっているためである。

### 変更時の注意

戻り値チェックを削ると、JavaScript helperの登録に失敗していてもPowerShell側が処理を続けてしまう。  
その場合、後続のDOM操作で「helperがない」という別のエラーになり、原因が追いにくくなる。

---

## 10. このファイルを変更するときの判断基準

| 変更箇所 | 判断基準 |
|---|---|
| `DomFeaturePaths` の検証 | 複数ファイルの順序が保証されるか |
| `UsesDom` の扱い | 非DOMジョブにDOM依存を混ぜないか |
| パス解決 | RootPath基準の相対パスが壊れないか |
| ファイル読み込み | UTF-8 JavaScriptを正しく読めるか |
| 登録結果チェック | JavaScript登録失敗を早期に検出できるか |

---

## 11. 関連するテスト

このファイルの設計境界は、主に次のテストで守られる。

```text
tests/Foundation.DomBundle.Tests.ps1
tests/Foundation.DomBundle.UsesDom.Tests.ps1
tests/Foundation.JobRegistry.UsesDom.Tests.ps1
tests/Dom.OperationRegistryContract.Tests.ps1
```

特に確認されていること。

```text
- DomFeaturePath を使えること
- DomFeaturePaths を設定順に使うこと
- DOM pathがないジョブは例外にすること
- DomFeaturePath と DomFeaturePaths の同時指定を拒否すること
- DomFeaturePaths が文字列単体なら拒否すること
- Context.JobDefinition からDOM bundle登録できること
- RootPath + JobName からも互換的に登録できること
- UsesDom = false のジョブでDOM bundleを作らないこと
- 固定JobNameや固定DOMファイル名に依存していないこと
```

---

## 12. 本ドキュメント内容の要点

```text
- DomBundle.ps1 はDOM JavaScriptファイルをブラウザへ登録するためのファイルである
- DomFeaturePaths の順番はJavaScript読み込み順であり重要である
- UsesDom = false のジョブにはDOM bundle登録してはいけない
- Register-DomBundle は登録実処理、Register-FoundationDomBundle はContext対応Facadeである
- DOM bundle登録に失敗したら後続DOM操作へ進ませない
```
