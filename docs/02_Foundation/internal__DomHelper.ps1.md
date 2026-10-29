# modules/Foundation/internal/DomHelper.ps1 設計書

## 1. このファイルを一言でいうと

このファイルは、PowerShell側からブラウザ内のJavaScript helperを安全に呼び出すためのFacadeである。

具体的には、次を担当する。

```text
- JavaScript helper名とメソッド名の安全性を確認する
- PowerShellの値をJavaScriptリテラルに変換する
- helperメソッド呼び出し用のJavaScript式を組み立てる
- そのJavaScript式を Invoke-FoundationJavaScript / Wait-FoundationJavaScript に渡す
- 条件が満たされるまでDOM helper呼び出しをポーリングする
- DOM契約チェック用の呼び出しを行い、fatalなら停止する
```

このファイル自体は、画面上のボタンや表を探さない。  
実際のDOM探索は、ブラウザ内に登録済みの `window.__InstalledAppExportDomHelper` などのJavaScript helperが行う。

---

## このファイルを変更する典型ケース

- DOM bundle生成、helper登録、contract検証の方針が変わった場合
- DOM helper未登録時の扱いや戻り値契約が変わった場合
- FeatureのJavaScript helperとの境界が変わった場合


## 2. このファイルが担当する範囲

| 担当 | 内容 |
|---|---|
| helper名検証 | `__InstalledAppExportDomHelper` のようなJavaScript identifierだけ許可する |
| メソッド名検証 | `findAssetRowsInfo` のようなJavaScript identifierだけ許可する |
| 引数変換 | PowerShellオブジェクトをJSON化し、JavaScriptの引数配列にする |
| JavaScript式生成 | `window[helperName][methodName](...args)` 相当の式を作る |
| 実行委譲 | 作成した式を `Invoke-FoundationJavaScript` に渡す |
| 待機 | helper呼び出し結果が期待条件を満たすまで繰り返す |
| 契約確認 | helperのcontractメソッドを実行し、DOM契約結果を評価する |

---

## 3. このファイルが担当しない範囲

| 担当しないこと | 担当ファイル |
|---|---|
| DOM JavaScriptファイルをブラウザへ登録する | `DomBundle.ps1` |
| DOM契約結果の整形とfatal判定 | `DomContract.ps1` |
| CDP通信の詳細 | `CdpTransport.ps1` / `CdpRuntime.ps1` など |
| FeatureごとのOperation定義 | 各Feature moduleの `DomOperations.ps1` |
| 実際のHTML要素探索やクリック | `dom/features/*/*.js` |

このファイルは「PowerShellから登録済みJavaScript helperを呼ぶ」ための共通層である。

---

## 4. このファイルが必要になる実行シナリオ

DOM系Feature moduleの `DomOperations.ps1` は、直接 `Invoke-FoundationJavaScript` を呼ばず、このファイルの関数を使う。

代表的な流れ。

```text
InstalledAppExport DomOperations
  ↓
Invoke-FoundationDomHelperMethod
  ↓
New-FoundationDomHelperMethodExpression
  ↓
Invoke-FoundationJavaScript
  ↓
ブラウザ内で window.__InstalledAppExportDomHelper.<methodName>(...args) を実行
```

待機が必要な場合は次の流れになる。

```text
Workflow / DomAdapter
  ↓
Wait-FoundationDomHelperMethodResult
  ↓
Invoke-FoundationDomHelperMethod を繰り返す
  ↓
AcceptResult が true を返したら成功
  ↓
timeoutまで成功しなければ例外
```

画面契約の確認では次の流れになる。

```text
Workflow / DomAdapter
  ↓
Assert-FoundationDomHelperContract
  ↓
Wait-DomContractResult
  ↓
Assert-DomContractResult
```

---

## 5. このファイルが扱う主なデータ

## 5.1 HelperName

JavaScript側に登録されるグローバルオブジェクト名。

例。

```text
__InstalledAppExportDomHelper
__ScanTargetSyncDomHelper
__DeviceListExportDomHelper
```

このファイルでは、`window[helperName]` の形で参照する。

## 5.2 MethodName

Helperオブジェクトに定義されているJavaScriptメソッド名。

例。

```text
findAssetRowsInfo
syncEndpointCheckbox
validatePageContract
```

## 5.3 Arguments

PowerShell側からJavaScriptメソッドへ渡す引数配列。

PowerShell上では、文字列、数値、真偽値、`[pscustomobject]`、配列、`$null` などが渡される。  
このファイルはそれらをJSONへ変換し、JavaScript側で扱えるリテラルにする。

## 5.4 MissingHelperBehavior

helperが登録されていない場合の動作を表す。

| 値 | 動作 |
|---|---|
| `Throw` | JavaScript側で例外を投げる |
| `ReturnNull` | `null` を返す |
| `ReturnValue` | 指定された代替値を返す |
| `ReturnContractFailure` | DOM契約失敗の形をしたオブジェクトを返す |

通常は `Throw` でよい。  
ただし、契約チェックでは「helperがない」こと自体をContractResultとして扱いたい場面があるため、`ReturnContractFailure` が用意されている。

---

## 6. このファイル内の関数呼び出しツリー

```text
Invoke-FoundationDomHelperMethod
  ├─ New-FoundationDomHelperMethodExpression
  │   ├─ Test-FoundationDomHelperIdentifier
  │   ├─ ConvertTo-FoundationJavaScriptLiteral
  │   ├─ ConvertTo-FoundationJavaScriptArgumentArrayLiteral
  │   │   └─ ConvertTo-FoundationJavaScriptLiteral
  │   └─ New-FoundationDomHelperMissingScript
  │       ├─ ConvertTo-FoundationJavaScriptLiteral
  │       └─ New-FoundationDomHelperMissingContractResult
  └─ Invoke-FoundationJavaScript
```

待機系は次のようになる。

```text
Wait-FoundationDomHelperMethodResult
  ├─ Resolve-FoundationDomHelperTimingRuntime
  │   ├─ New-FoundationDomHelperTimingRuntime
  │   └─ Get-FoundationDomHelperTimingScriptBlock
  ├─ Get-FoundationDomHelperNow
  ├─ Get-FoundationDomHelperRemainingSeconds
  ├─ Invoke-FoundationDomHelperMethod
  ├─ AcceptResult scriptblock 実行
  └─ Invoke-FoundationDomHelperSleepMilliseconds
```

契約確認は次のようになる。

```text
Assert-FoundationDomHelperContract
  ├─ New-FoundationDomHelperMethodExpression
  ├─ Wait-DomContractResult
  └─ Assert-DomContractResult
```

---

## 7. 関数ごとの説明

## 7.1 Test-FoundationDomHelperIdentifier

### 何をするか

helper名またはメソッド名が、JavaScript identifierとして安全な形式か確認する。

許可される例。

```text
__InstalledAppExportDomHelper
syncEndpointCheckbox
findRows
$helper
_helper1
```

許可されない例。

```text
window.__InstalledAppExportDomHelper
bad-method
alert(1)
helper.name
```

### なぜ必要か

このファイルはJavaScript式を文字列として組み立てる。  
もしhelper名やメソッド名に任意のJavaScript断片を混ぜられると、意図しないコードを実行できてしまう。

そのため、名前として安全な文字だけを許可する。

### 入力

| 引数 | 意味 |
|---|---|
| `Name` | 確認する名前 |
| `ParameterName` | エラーメッセージに出す引数名 |

### 出力

正常なら何も返さない。  
不正なら例外を投げる。

### PowerShell文法上のポイント

#### `-notmatch '^[A-Za-z_$][A-Za-z0-9_$]*$'`

正規表現でJavaScript identifier形式を確認している。

意味は次の通り。

```text
^              文字列の先頭
[A-Za-z_$]     先頭は英字、_、$ のいずれか
[A-Za-z0-9_$]* 2文字目以降は英数字、_、$ を0文字以上
$              文字列の末尾
```

---

## 7.2 ConvertTo-FoundationJavaScriptLiteral

### 何をするか

PowerShellの値をJavaScriptリテラルとして使える文字列へ変換する。

| PowerShell値 | 出力イメージ |
|---|---|
| `$null` | `null` |
| `'abc'` | `"abc"` |
| `$true` | `true` |
| `[pscustomobject]@{ Name='PC01' }` | `{"Name":"PC01"}` |

### なぜ必要か

JavaScriptメソッドへ引数を渡すには、PowerShellの値をJavaScript側で解釈できる形にする必要がある。

手動で文字列連結すると、引用符やバックスラッシュの扱いを誤りやすい。  
そのため、`ConvertTo-Json` で安全にJSON化している。

### 入力

| 引数 | 意味 |
|---|---|
| `Value` | JavaScriptへ渡したい値 |
| `Depth` | JSON化する深さ |

### 出力

JavaScriptリテラル文字列。

### 失敗条件

非常に深いオブジェクトや、JSON化できない特殊オブジェクトを渡すと失敗する可能性がある。

---

## 7.3 ConvertTo-FoundationJavaScriptArgumentArrayLiteral

### 何をするか

PowerShellの引数配列を、JavaScriptの配列リテラルへ変換する。

例。

```text
PowerShell側:
@('PC01', $true, $null)

JavaScript側:
["PC01",true,null]
```

### なぜ必要か

JavaScript helper呼び出しでは、最終的に次のような形を作る。

```text
helper[methodName].apply(helper, args)
```

この `args` に渡す配列を作るための関数である。

---

## 7.4 New-FoundationDomHelperMissingContractResult

### 何をするか

helperが登録されていない状態を、DOM契約失敗の形に変換したオブジェクトを作る。

返すオブジェクトは概ね次の意味を持つ。

```text
scope        : 契約チェック範囲
ok           : false
fatalCount   : 1
warningCount : 0
checks       : helper.registered が fatal で失敗
reason       : helper_not_registered
```

### なぜ必要か

契約チェックでは、helper未登録も「契約違反」として扱いたい。

単にJavaScript例外にすると、`Assert-DomContractResult` の形式に乗らない。  
この関数でContractResult風のオブジェクトを作ることで、helper未登録も同じ診断経路に載せられる。

---

## 7.5 New-FoundationDomHelperMissingScript

### 何をするか

JavaScript helperが存在しなかった場合に実行するJavaScript断片を作る。

### 動作パターン

| MissingHelperBehavior | 生成される動作 |
|---|---|
| `Throw` | `throw new Error(...)` |
| `ReturnNull` | `return null;` |
| `ReturnValue` | 指定値をJSON化して返す |
| `ReturnContractFailure` | ContractResult形式の失敗オブジェクトを返す |

### なぜ必要か

helper未登録時の扱いは、呼び出し目的によって異なる。

例えば、通常のクリック操作ならhelperがない時点で例外にすべきである。  
一方、画面契約チェックなら「helper未登録」という診断結果として返した方が、エラーメッセージが整理される。

### 変更時の注意

`ReturnContractFailure` の形を変える場合は、`DomContract.ps1` が期待する `fatalCount`、`warningCount`、`checks` の形を壊さないようにする。

---

## 7.6 New-FoundationDomHelperMethodExpression

### 何をするか

JavaScript helperメソッドを呼び出すためのJavaScript式を作る。

非同期でない場合は、概ね次の構造の式を作る。

```text
(() => {
  const helperName = "__InstalledAppExportDomHelper";
  const methodName = "findRows";
  const args = [...];
  const helper = window[helperName];

  if (!helper) { ... }
  if (typeof helper[methodName] !== 'function') { ... }

  return helper[methodName].apply(helper, args);
})()
```

`-Await` が指定された場合は、`async` 即時実行関数になり、結果を `await` する。

### なぜ必要か

PowerShell側のFeature moduleが毎回このJavaScript式を手で組み立てると、次の問題が起きる。

```text
- 引数のJSON化がばらつく
- helper未登録時の扱いがばらつく
- awaitの扱いがばらつく
- メソッド名の検証漏れが出る
- テストで境界を守りにくい
```

この関数に集約することで、全Feature moduleが同じ呼び出し形式を使える。

### 入力

| 引数 | 意味 |
|---|---|
| `HelperName` | `window` 上のhelper名 |
| `MethodName` | helper内のメソッド名 |
| `Arguments` | JavaScriptへ渡す引数 |
| `MissingHelperBehavior` | helper未登録時の動作 |
| `MissingValue` | `ReturnValue` 時の代替値 |
| `ContractScope` | 契約失敗として返す場合のscope |
| `MissingHelperMessage` | helper未登録時のメッセージ |
| `JsonDepth` | JSON化の深さ |
| `Await` | Promise結果をawaitするか |

### 出力

JavaScript式文字列。

### 失敗条件

| 条件 | 結果 |
|---|---|
| HelperNameが不正 | 例外 |
| MethodNameが不正 | 例外 |
| MissingHelperBehaviorが不正 | ValidateSetにより拒否 |

### PowerShell文法上のポイント

#### here-string

複数行のJavaScript式を返すために、PowerShellのhere-stringを使っている。

```text
@"
複数行文字列
"@
```

here-stringの中ではPowerShell変数が展開される。  
そのため、事前にJSON化した安全な文字列だけを埋め込むことが重要である。

#### `-Await:$Await`

switch引数を別の関数へ渡すときの書き方である。  
`$Await` がtrueなら `-Await` 指定あり、falseなら指定なしとして渡せる。

---

## 7.7 New-FoundationDomHelperTimingRuntime

### 何をするか

待機処理で使う時刻取得とsleep処理をまとめたオブジェクトを作る。

形は次の通り。

```text
TimingRuntime
  Now               : 現在時刻を返すscriptblock
  SleepMilliseconds : 指定ミリ秒待つscriptblock
```

### なぜ必要か

本番では `Get-Date` と `Start-Sleep` を使えばよい。  
しかし、テストで本当にsleepするとテストが遅くなる。

そこで、時刻とsleepをscriptblockとして差し替えられるようにしている。

---

## 7.8 Get-FoundationDomHelperTimingScriptBlock

### 何をするか

TimingRuntimeから指定名のscriptblockを取り出し、存在しなければ例外にする。

### なぜ必要か

`Wait-FoundationDomHelperMethodResult` は、`Now` と `SleepMilliseconds` が揃っていないと正しく待機できない。

不足したまま進めると、待機ループ内で分かりにくいエラーになるため、先に契約チェックする。

---

## 7.9 Resolve-FoundationDomHelperTimingRuntime

### 何をするか

TimingRuntimeが渡されていなければ本番用を作り、渡されていれば必要なscriptblockを持っているか検証する。

### なぜ必要か

本番実行とテスト実行で同じ待機関数を使うためである。

```text
本番: Timing未指定 → Get-Date / Start-Sleep を使う
テスト: Timing指定 → 仮想時刻 / 仮想sleep を使う
```

---

## 7.10 Get-FoundationDomHelperNow

### 何をするか

TimingRuntimeの `Now` scriptblockを実行し、現在時刻を取得する。

### 失敗条件

`Now` が `$null` を返した場合は例外にする。

時刻が取れないとdeadline計算が成立しないためである。

---

## 7.11 Invoke-FoundationDomHelperSleepMilliseconds

### 何をするか

TimingRuntimeの `SleepMilliseconds` scriptblockを実行する。

### なぜ必要か

待機ループで直接 `Start-Sleep` を呼ぶと、テストで差し替えられない。  
この関数を経由することで、テストでは実時間を待たずに仮想時刻だけ進められる。

---

## 7.12 Get-FoundationDomHelperRemainingSeconds

### 何をするか

deadlineまで残り何秒かを計算する。

1秒未満になった場合でも、最低1秒を返す。

### なぜ必要か

`Invoke-FoundationJavaScript` に渡すtimeoutは秒単位である。  
待機ループ全体の残り時間を超えて1回のJavaScript呼び出しが長く待ちすぎないよう、残り秒数を渡している。

---

## 7.13 Register-FoundationDomBundle

### 何をするか

DOM bundle登録をContextから呼びやすくするFacadeである。

### 2つの呼び方

| ParameterSet | 使い方 |
|---|---|
| `Context` | `-Context $Context` からRootPath、JobName、JobDefinitionを取り出す |
| `RootPath` | `-RootPath` と `-JobName` を直接渡す |

通常のFeature moduleでは、`-Context $Context` を使う。

### なぜ `DomBundle.ps1` ではなくこのファイルにもあるのか

`Register-DomBundle` は低めの実処理である。  
`Register-FoundationDomBundle` はFeature moduleから使いやすい公開Facadeである。

Foundation.psm1では、このFacadeも外部公開されている。

### 失敗条件

`Context` 呼び出しでは、次が空なら例外。

```text
Context
Context.RootPath
Context.JobName
```

`Context.JobDefinition` はそのまま `Register-DomBundle` へ渡される。

---

## 7.14 Invoke-FoundationDomHelperMethod

### 何をするか

JavaScript helperメソッドを1回呼び出す。

### 処理の流れ

```text
New-FoundationDomHelperMethodExpression
  ↓
Invoke-FoundationJavaScript
  ↓
JavaScriptの実行結果を返す
```

### 入力

`New-FoundationDomHelperMethodExpression` とほぼ同じ引数を受け取り、さらに `TimeoutSeconds` を持つ。

### 出力

JavaScript helperメソッドの戻り値。

### 副作用

ブラウザ内でJavaScriptが実行される。  
呼び出すメソッドによっては、クリック、チェックボックス変更、スクロールなどの画面操作が発生する。

### 変更時の注意

この関数でraw JavaScriptを直接書き足し始めると、FeatureごとのDomOperationsとの境界が崩れる。  
helper呼び出しの共通形式だけを扱うべきである。

---

## 7.15 Wait-FoundationDomHelperMethod

### 何をするか

JavaScript helperメソッドを呼ぶ式を作り、`Wait-FoundationJavaScript` に渡す。

### `Invoke-FoundationDomHelperMethod` との違い

| 関数 | 意味 |
|---|---|
| `Invoke-FoundationDomHelperMethod` | JavaScript式を1回実行する |
| `Wait-FoundationDomHelperMethod` | JavaScript式が成功扱いになるまでCDP側の待機処理に委ねる |

この関数自体がポーリングループを持つわけではない。  
待機の詳細は `Wait-FoundationJavaScript` 側に委譲する。

---

## 7.16 Wait-FoundationDomHelperMethodResult

### 何をするか

JavaScript helperメソッドを繰り返し呼び出し、戻り値が `AcceptResult` 条件を満たしたら成功として返す。

### 処理の流れ

```text
AcceptResult が空でないことを確認
  ↓
PollIntervalMilliseconds が1未満なら1に補正
  ↓
TimingRuntimeを解決
  ↓
deadlineを計算
  ↓
期限までループ
      ↓
      残り秒数を計算
      ↓
      Invoke-FoundationDomHelperMethod
      ↓
      戻り値をAcceptResultで判定
      ↓
      trueなら戻り値を返す
      ↓
      falseまたは例外ならsleep
  ↓
タイムアウト時はlast resultまたはlast errorを含めて例外
```

### なぜ必要か

DOM操作では、画面が即座に変わらないことが多い。

例。

```text
- 一覧が描画されるまで待つ
- 詳細パネルが開くまで待つ
- チェックボックス変更が画面に反映されるまで待つ
- ダウンロードボタンが有効になるまで待つ
```

このような場面では、1回だけJavaScriptを実行して失敗扱いにするのではなく、一定時間だけ再試行する必要がある。

### AcceptResultの意味

`AcceptResult` は、戻り値を受け取って成功かどうかを返すscriptblockである。

デフォルトは次の意味。

```text
戻り値が true なら成功
```

Feature側では、戻り値オブジェクトの `ok` プロパティを見るような条件に差し替えられる。

### タイムアウト時の診断

タイムアウト時には、可能な限り次を例外メッセージに含める。

```text
- 最後に得られた戻り値
- 最後に発生したエラー
- Description
```

これにより、「単に待機失敗」ではなく、最後の状態を見て原因を推測できる。

### PowerShell文法上のポイント

#### `& $AcceptResult $result`

`&` はscriptblockを実行する演算子である。

ここでは、呼び出し元から渡された判定関数を実行している。

#### `catch { $lastError = $_.Exception.Message }`

各試行で例外が起きても、すぐには全体を失敗にしない。  
期限までは再試行し、最後にまとめてタイムアウトとして報告する。

### 変更時の注意

`catch` で即throwするように変えると、一時的な画面未準備で処理が止まりやすくなる。  
DOM待機では、短時間の失敗を許容して再試行することに意味がある。

---

## 7.17 Assert-FoundationDomHelperContract

### 何をするか

DOM契約チェック用のhelperメソッドを呼び、結果を評価する。

### 処理の流れ

```text
New-FoundationDomHelperMethodExpression
  ↓
Wait-DomContractResult
  ↓
Assert-DomContractResult
  ↓
ContractResultを返す
```

### なぜ必要か

画面操作を行う前に、画面が期待通りか確認するためである。

例えば次のような場面で使う。

```text
- 対象ページが開いているか
- 一覧が表示されているか
- 詳細パネルが開いているか
- helperが登録されているか
```

`Assert-DomContractResult` によって、fatalな契約違反があれば処理を止める。

---

## 8. このファイルを変更するときの判断基準

| 変更箇所 | 確認すること |
|---|---|
| helper名・メソッド名検証 | 任意JavaScript式を混入できないか |
| JSON化 | 文字列中の引用符、null、配列、booleanが壊れないか |
| `Await` 処理 | Promiseを返すhelperメソッドが正しく待てるか |
| MissingHelperBehavior | helper未登録時の診断が分かりにくくならないか |
| 待機ループ | 一時的な画面未準備を許容できるか |
| TimingRuntime | テストで実sleepが発生しないか |
| Contract確認 | fatalなDOM契約違反を見逃さないか |

---

## 9. 関連するテスト

このファイルの設計境界は、主に次のテストで守られる。

```text
tests/Foundation.DomHelper.Tests.ps1
tests/Foundation.DomBundle.Tests.ps1
tests/Dom.OperationRegistryContract.Tests.ps1
```

特に確認されていること。

```text
- helper名、メソッド名、引数、await呼び出しを含むJavaScript式が作られること
- 文字列中の引用符が正しくJSON化されること
- nullが引数として保持されること
- JavaScript identifierでないhelper名やメソッド名を拒否すること
- helper未登録時のContractFailureオブジェクトを作れること
- Invoke-FoundationJavaScriptへtimeout付きで委譲すること
- TimingRuntimeを注入すれば実際のStart-Sleepを呼ばずに待機テストできること
- TimingRuntimeに必要なscriptblockが欠けていれば先に例外にすること
```

---

## 10. 本ドキュメント内容の要点

```text
- DomHelper.ps1 はPowerShellとブラウザ内JavaScript helperの橋渡しである
- 実際のDOM操作はJavaScript helper側が行う
- HelperNameとMethodNameは安全なJavaScript identifierだけ許可される
- PowerShell引数はJSON化され、JavaScriptのargs配列として渡される
- helper未登録時の扱いは用途に応じて変えられる
- Wait-FoundationDomHelperMethodResult は戻り値条件を満たすまで再試行する
- Assert-FoundationDomHelperContract はDOM契約チェックの入口である
```
