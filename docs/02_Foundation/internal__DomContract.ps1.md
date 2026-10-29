# modules/Foundation/internal/DomContract.ps1 設計書

## 1. このファイルを一言でいうと

このファイルは、ブラウザ内JavaScript helperが返した **DOM契約チェック結果** をPowerShell側で読み取り、ログに出しやすい文字列へ整形し、致命的な契約違反があれば処理を止めるためのファイルである。

ここでいう「契約」とは、次のような前提を指す。

```text
- 期待するDOM helperが登録されている
- 期待する画面要素が存在する
- 画面要素が一意に特定できる
- 操作対象が見えている
- 画面がそのジョブの処理に進んでよい状態になっている
```

---

## このファイルを変更する典型ケース

- DOM bundle生成、helper登録、contract検証の方針が変わった場合
- DOM helper未登録時の扱いや戻り値契約が変わった場合
- FeatureのJavaScript helperとの境界が変わった場合


## 2. このファイルが担当する範囲

このファイルが担当するのは、**DOM契約チェック結果の解釈**である。

具体的には次を行う。

| 担当 | 内容 |
|---|---|
| 結果の整形 | ContractResultを人間が読める複数行テキストへ変換する |
| warningの扱い | `warningCount > 0` の場合、警告として表示する |
| fatalの扱い | `fatalCount > 0` の場合、例外を投げて処理を止める |
| null防止 | ContractResultが空なら異常として止める |

---

## 3. このファイルが担当しない範囲

このファイルは、DOMそのものを操作しない。

| 担当しないこと | 担当ファイル |
|---|---|
| JavaScriptファイルをブラウザへ登録する | `DomBundle.ps1` |
| JavaScript helperメソッドを呼ぶ式を作る | `DomHelper.ps1` |
| CDPでJavaScriptを実行する | `CdpRuntime.ps1` など |
| 画面要素を探す | `dom/features/*/*.js` |
| Feature固有の操作名を定義する | 各Feature moduleの `DomOperations.ps1` |

このファイルは、あくまで「返ってきた契約結果をどう扱うか」に責務を限定している。

---

## 4. このファイルが必要になる実行シナリオ

代表的には、次のような流れで使われる。

```text
Feature Workflow
  ↓
画面が期待通りか確認したい
  ↓
Assert-FoundationDomHelperContract
  ↓
JavaScript helperのcontractメソッドを実行
  ↓
ContractResult が返る
  ↓
Assert-DomContractResult
  ↓
warningなら警告、fatalなら停止
```

たとえば、InstalledAppExportジョブで「詳細パネルが開いていること」を確認する場合、JavaScript側はパネルの存在や表示状態を検査し、結果オブジェクトを返す。PowerShell側はその結果をこのファイルの関数で評価する。

---

## 5. 扱うデータの形

このファイルが期待するDOM契約チェック結果は、概ね次の形である。

```text
ContractResult
  scope        : どの画面・どの契約を確認したか
  ok           : 全体として成功か
  fatalCount   : 処理を止めるべき違反の数
  warningCount : 警告として表示すべき違反の数
  checks       : 個別チェック結果の配列
  details      : 補足情報
```

`checks` の各要素は、概ね次の形を持つ。

```text
CheckResult
  name     : チェック名
  ok       : そのチェックが成功したか
  severity : fatal または warning
  message  : 人間向けの説明
  details  : selector、候補数、helper名などの補足情報
```

このファイルは、`checks` の中から `ok -eq $false` のものだけを整形対象にする。成功したチェックまで出すと、エラー時のログが読みにくくなるためである。

---

## 6. このファイル内の関数呼び出しツリー

```text
Assert-DomContractResult
  ├─ Format-DomContractResult
  │   └─ ConvertTo-Json
  ├─ Write-Warning
  └─ throw
```

`Format-DomContractResult` は文字列化だけを担当する。  
`Assert-DomContractResult` は、その文字列を使って warning / fatal を判断する。

---

## 7. 関数ごとの説明

## 7.1 Format-DomContractResult

### 何をするか

DOM契約チェック結果を、ログや例外メッセージに埋め込みやすい文字列へ変換する。

出力イメージは次のような形になる。

```text
scope=asset.detail ok=False fatalCount=1 warningCount=0
[fatal] selector.unique: selector must be unique details={"candidateCount":2,"selector":"button"}
```

### なぜ必要か

JavaScript helperから返る結果は `[pscustomobject]` として扱われる。  
そのまま例外メッセージに入れると、`@{...}` のような読みにくい表示になりやすい。

この関数で整形しておくことで、次の情報がすぐ分かる。

```text
- どの契約が失敗したか
- fatalなのかwarningなのか
- どのチェックが失敗したか
- selectorや候補数などの詳細は何か
```

### 入力

| 引数 | 型 | 意味 |
|---|---|---|
| `Result` | object | JavaScript helperから返ったDOM契約チェック結果 |

### 出力

複数行の文字列。

### 副作用

なし。ログ出力もしない。例外も投げない。

### 失敗条件

基本的には、`Result` が想定外の形でも可能な範囲で文字列化する。  
ただし、`ConvertTo-Json` が扱えない極端なオブジェクトを `details` に含めた場合は失敗する可能性がある。

### PowerShell文法上のポイント

#### `New-Object System.Collections.Generic.List[string]`

文字列を順番に追加するために、.NETのListを使っている。

PowerShellの配列に `+=` で追加し続けると、要素数が増えたときに毎回配列コピーが発生する。ここではログ行を集める用途なのでListを使っている。

#### `foreach ($check in @($Result.checks))`

`@(...)` は、値を必ず配列として扱うための書き方である。

`$Result.checks` が1件だけの場合でも、`foreach` が安定して動くようにしている。

#### `ConvertTo-Json -Compress -Depth 12`

`details` を1行JSONにする。

- `-Compress` は空白や改行を詰める。
- `-Depth 12` は深い入れ子のオブジェクトも途中で省略されにくくする。

### 変更時の注意

この関数の出力形式を大きく変えると、例外メッセージやテストの期待値が変わる。  
特に、失敗したチェックだけを出す方針を変える場合は、エラー時ログが長くなりすぎないか確認する。

---

## 7.2 Assert-DomContractResult

### 何をするか

DOM契約チェック結果を検査し、次の判断を行う。

| 条件 | 動作 |
|---|---|
| `Result` が空 | 例外を投げる |
| `warningCount > 0` | `Write-Warning` で警告を出す |
| `fatalCount > 0` | 例外を投げて処理を止める |
| warningもfatalもない | 何もせず通す |

### なぜ必要か

DOM契約チェックは、画面操作を続行してよいかを判断する境界である。

例えば、期待するボタンが見つからない状態で処理を続けると、次のような事故が起きる。

```text
- 別のボタンを押す
- 空の一覧を正しい一覧だと誤認する
- 画面変更に気付かず、誤ったCSVを取得する
- チェックボックス操作対象を間違える
```

そのため、`fatalCount` が1以上なら、処理を即座に止める。

### 入力

| 引数 | 型 | 意味 |
|---|---|---|
| `Result` | object | DOM契約チェック結果 |
| `Description` | string | どの場面の契約チェックかを表す説明 |

### 出力

正常時は戻り値を明示しない。  
異常時は例外を投げる。

### 副作用

`warningCount > 0` の場合、`Write-Warning` で警告を出す。

### 失敗条件

| 条件 | 例外内容の意味 |
|---|---|
| `Result` が `$null` | JavaScript側から契約結果が返らなかった |
| `fatalCount > 0` | 契約違反のため処理継続不可 |

### PowerShell文法上のポイント

#### `[int]$Result.warningCount`

JavaScript由来の値は、PowerShell側では型が曖昧になることがある。  
ここでは数値比較を安定させるため、`[int]` にキャストしている。

#### `throw "..."`

`throw` は現在の処理を例外として停止する。  
このファイルでは、fatalなDOM契約違反を「続行不能」として扱うために使っている。

### 変更時の注意

`fatalCount > 0` でも止めないように変更してはいけない。  
それをすると、壊れた画面状態のまま後続のクリックやCSV取得が実行される可能性がある。

`warningCount` の扱いを例外に変える場合も注意が必要である。  
warningは「注意は必要だが続行可能」という契約で使われるため、すべて停止にすると運用上過剰に止まる可能性がある。

---

## 8. このファイルを変更するときの判断基準

このファイルは、DOM系ジョブ全体の安全装置である。

変更前に次を確認する。

| 変更内容 | 確認すること |
|---|---|
| 出力フォーマット変更 | エラー時に必要な `scope`、`severity`、`message`、`details` が残るか |
| warning判定変更 | 警告だけで処理を止めすぎないか |
| fatal判定変更 | 致命的な画面不整合を見逃さないか |
| detailsのJSON化変更 | selectorや候補数などの診断情報が消えないか |

---

## 9. 関連するテスト

このファイルの設計境界は、主に次のテストで守られる。

```text
tests/Foundation.DomContract.Tests.ps1
```

特に確認されているのは次である。

```text
- 失敗したcheckだけを整形すること
- detailsをJSONとして含めること
- Resultがnullなら例外にすること
- fatalがあれば例外にすること
- warningだけなら警告を出して続行すること
- 成功時は警告も例外も出さないこと
```

---

## 10. 本ドキュメント内容の要点

```text
- DomContract.ps1 はDOM操作をしない
- JavaScript helperが返した契約結果をPowerShell側で評価する
- warningは警告、fatalは停止である
- Format-DomContractResult は人間が読むための整形を担当する
- Assert-DomContractResult は処理を続けてよいかを判断する
```
