# main/modules/Foundation/internal/Errors.ps1

## 1. このファイルを一言でいうと

このファイルは、発生したエラーメッセージが「処理を継続してよい失敗」か「自動化全体を止めるべき致命的失敗」かを判定します。

現在定義されている関数は `Test-FoundationFatalError` だけです。

## このファイルを変更する典型ケース

- Foundation共通サービスのcallback、戻り値、例外分類が変わった場合
- Feature moduleから使う共通境界の意味が変わった場合
- 複数Jobに影響する安全確認や診断情報が変わった場合


## 2. このファイルが担当する範囲

```text
- エラーメッセージ文字列を受け取る
- CDP / WebSocket / DOM helper 登録失敗などを fatal と判定する
- 空文字やnullを fatal ではないと判定する
```

## 3. このファイルが担当しない範囲

```text
- エラーをthrowする
- エラーをログに出す
- どの端末処理をリトライするか決める
- ブラウザ接続を復旧する
- DOM helperを登録する
```

このファイルは、あくまで「分類」だけを行います。

## 4. なぜこの分類が必要か

自動化処理には、継続できる失敗と継続すべきでない失敗があります。

例えば、ある1台の端末でチェックボックス操作に失敗しただけなら、失敗行として記録し、次の端末へ進める場合があります。

一方で、次のようなエラーは、以降の端末でも同じように失敗する可能性が高いです。

```text
- CDP接続がタイムアウトした
- WebSocketが壊れた
- DOM helperが登録されていない
- DOM helper methodが存在しない
```

このような状態で処理を続けると、同じ失敗を大量に積み上げるだけになります。  
そのため、fatal として扱い、上位のWorkflowで処理全体を止める判断材料にします。

## 5. 実行時の位置づけ

`Errors.ps1` の `Test-FoundationFatalError` は、`Foundation.psm1` で公開されています。

`ScanTargetSync` では、`Dependencies.ps1` がこの関数を `EndpointAction.TestFoundationFatalError` として包み、`Workflow.EndpointSync.ps1` で利用します。

概念的には次の流れです。

```text
Endpointごとの画面操作
  ↓
例外発生
  ↓
例外メッセージを取り出す
  ↓
Test-FoundationFatalError
  ├─ true  → 自動化基盤の致命的失敗として扱う
  └─ false → 個別行の失敗として扱える可能性がある
```

## 6. 判定条件

`Test-FoundationFatalError` は、メッセージ文字列に特定の断片が含まれるかを見ています。

| メッセージ断片 | fatal とする理由 |
|---|---|
| `CDPタイムアウト` | ブラウザ制御通信が成立していない可能性が高い |
| `ClientWebSocket` | CDP通信の土台が壊れている可能性がある |
| `WebSocket` | ブラウザとの双方向通信が壊れている可能性がある |
| `破棄されたオブジェクト` | 接続やセッションが既に利用不能な可能性がある |
| `helper_not_registered` | JavaScript helperが登録されていない |
| `DOM helper is not registered` | DOM helper全体が未登録 |
| `DOM helper method is not registered` | 期待するDOM操作が存在しない |

## 7. 関数説明

## Test-FoundationFatalError

### 何をするか

エラーメッセージを受け取り、自動化全体として致命的な種類かどうかを `true` / `false` で返します。

### 入力

```text
Message : エラーメッセージ文字列。空文字も許可
```

### 出力

```text
true  : fatal error と判定する
false : fatal error ではない
```

### 副作用

ありません。  
ログ出力もthrowも行いません。

### 失敗条件

基本的にありません。  
`null` や空文字を受け取っても `false` を返します。

### PowerShell文法上のポイント

```text
[AllowEmptyString()][string]$Message
```

空文字の引数を許可します。  
この関数では、空文字は「fatalではない」と判定するため、空文字を受け取った時点でバインドエラーにしたくありません。

```text
if ([string]::IsNullOrWhiteSpace($Message)) { return $false }
```

`null`、空文字、空白だけの文字列をまとめて扱います。

```text
$Message -like '*WebSocket*'
```

`-like` はワイルドカード一致です。  
ここでは、メッセージ全文が完全一致しなくても、特定の断片を含んでいれば fatal と判定します。

### 変更時の注意

この関数は単純に見えますが、Workflowの継続可否に影響します。

条件を増やすと、これまで個別失敗として扱っていたエラーでジョブ全体が止まる可能性があります。  
条件を減らすと、ブラウザ制御が壊れているのに処理を続けてしまう可能性があります。

## 8. なぜ例外型ではなく文字列で判定しているのか

理想的には、例外型やエラーコードで判定する方が堅いです。  
しかし、このプロジェクトでは、PowerShell、CDP、WebSocket、JavaScript helperから来るエラーが混ざります。

それぞれの例外型をきれいに統一できていないため、現時点ではメッセージ断片で分類しています。

これは万能ではありません。  
ただし、fatal 判定を1箇所に集めているため、将来エラーコード方式に変える場合も、このファイルを中心に修正できます。

## 9. このファイルを変更するときの判断基準

```text
- fatal 条件を追加すると、ジョブが途中停止しやすくなる
- fatal 条件を削ると、壊れたブラウザ状態で処理を続ける可能性がある
- 個別業務エラーをここに入れすぎると、共通基盤が業務知識を持ちすぎる
- DOM / CDP / WebSocket のような自動化基盤エラーに限定するのが基本
```

## 10. このファイルを守っているテスト

```text
Foundation.Errors.Tests.ps1
  - DOM helper登録失敗系メッセージをfatalと判定する
  - 空文字とnullをfatalではないと判定する

Foundation.PublicApi.Tests.ps1
  - Test-FoundationFatalError が公開APIとして存在すること
```

## 11. 本ドキュメント内容の要点

```text
- Errors.ps1 はエラーを発生させるファイルではなく、エラーを分類するファイル
- fatal とは「個別行の失敗」ではなく「自動化基盤が壊れている可能性が高い失敗」
- 判定は現在、例外型ではなくメッセージ断片で行っている
- 条件変更はWorkflowの停止・継続判断に影響する
```
