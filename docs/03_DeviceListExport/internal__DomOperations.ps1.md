# modules/DeviceListExport/internal/DomOperations.ps1

## 1. このファイルを一言でいうと

DeviceListExportのPowerShell側DOM operation名と、JavaScript helperメソッド名を対応させるファイルである。

ここは、PowerShellとブラウザ内JavaScriptの境界である。

## このファイルを変更する典型ケース

- DOM operation の `MethodName`、`Await`、`MissingHelperBehavior` が変わった場合
- JavaScript helperとの契約、戻り値、例外扱いが変わった場合
- raw Foundation DOM helper呼び出しの境界が変わった場合


## 2. このファイルが担当する範囲

```text
- DeviceListExport用helper名を定義する
- DOM operation一覧を定義する
- operation名から呼び出し定義を作る
- FoundationのDOM helper呼び出し関数へ委譲する
```

## 3. このファイルが担当しない範囲

```text
- Workflowの順序を決める
- 操作ボタンを探すselectorを書く
- CSVダウンロードを待つ
- DOM bundleを登録する
```

selectorやDOM探索の実体は `dom/features/device-list-export/*.js` にある。

## 4. DeviceListExport DOM helper名

このファイルでは、DeviceListExport用JavaScript helper名として次を使う。

```text
__DeviceListExportDomHelper
```

ブラウザ側では、DOM bundle登録後に次のようなグローバルオブジェクトが用意される。

```text
window.__DeviceListExportDomHelper
```

PowerShell側は、このhelperのメソッドをCDP経由で呼ぶ。

## 5. DOM operation対応表

| Operation | JavaScript MethodName | 用途 | helper未登録時の扱い |
|---|---|---|---|
| `DetectPageIdentity` | `detectDeviceListExportPageIdentity` | 対象画面か判定する | 契約失敗として返す |
| `ValidateInitialContract` | `validateInitialContract` | 初期契約を検証する | 契約失敗として返す |
| `ValidateExportPageContract` | `validateExportPageContract` | エクスポート画面契約を検証する | 契約失敗として返す |
| `ClickTaskButton` | `clickTaskButton` | 操作ボタンをクリックする | 例外 |
| `IsTaskMenuReady` | `isTaskMenuReady` | 操作メニュー表示を判定する | falseを返す |
| `ClickExportMenuItem` | `clickExportMenuItem` | エクスポートメニューをクリックする | 例外 |
| `ValidateExportPostcondition` | `validateExportPostcondition` | クリック後契約を検証する | 契約失敗として返す |

## 6. MissingHelperBehaviorの意味

helper未登録時の扱いはoperationごとに異なる。

### ReturnContractFailure

契約確認系operationで使う。

```text
DetectPageIdentity
ValidateInitialContract
ValidateExportPageContract
ValidateExportPostcondition
```

helperがないこと自体を「契約違反の結果」として返す。
これにより、契約検証の枠組みでエラーを説明できる。

### Throw

クリック操作で使う。

```text
ClickTaskButton
ClickExportMenuItem
```

クリック操作は副作用を持つため、helperがない状態で続行してはいけない。
そのため即座に例外にする。

### ReturnValue

待機判定で使う。

```text
IsTaskMenuReady
```

helperがない場合は `false` を返す。
待機処理はfalseを受け取ると待ち続け、最終的にタイムアウトする。

## 7. 関数呼び出しツリー

```text
Invoke-DeviceListExportDomOperation
  ├─ New-DeviceListExportDomHelperParameters
  │   └─ Get-DeviceListExportDomOperationDefinition
  └─ Invoke-FoundationDomHelperMethod

Wait-DeviceListExportDomOperation
  ├─ New-DeviceListExportDomHelperParameters
  │   └─ Get-DeviceListExportDomOperationDefinition
  └─ Wait-FoundationDomHelperMethod

Assert-DeviceListExportDomOperationContract
  ├─ New-DeviceListExportDomHelperParameters
  │   └─ Get-DeviceListExportDomOperationDefinition
  └─ Assert-FoundationDomHelperContract
```

## 8. 関数ごとの説明

### Get-DeviceListExportDomOperationDefinition

operation名から定義を取り出す。

未定義のoperation名が渡された場合は例外にする。
この検証により、タイプミスしたoperation名でJavaScriptを呼ぼうとする事故を早めに止める。

戻り値には、元の定義に加えて次も付与する。

```text
HelperName
  __DeviceListExportDomHelper

MissingHelperMessage
  DeviceListExport DOM helper is not registered
```

### New-DeviceListExportDomHelperParameters

FoundationのDOM helper呼び出し関数に渡すパラメータを組み立てる。

組み立てる主な値は次である。

```text
HelperName
MethodName
Arguments
TimeoutSeconds
MissingHelperBehavior
MissingValue
ContractScope
Description
Await
```

この関数があることで、`Invoke`、`Wait`、`Assert` の3種類の呼び出しが同じ定義表を使える。

### Invoke-DeviceListExportDomOperation

即時実行のDOM operationを呼ぶ。

主にクリック操作や単発の値取得で使う。
内部では `Invoke-FoundationDomHelperMethod` に委譲する。

### Wait-DeviceListExportDomOperation

条件が成立するまで待つDOM operationを呼ぶ。

DeviceListExportでは `IsTaskMenuReady` に使う。
内部では `Wait-FoundationDomHelperMethod` に委譲する。

### Assert-DeviceListExportDomOperationContract

契約検証系DOM operationを呼ぶ。

戻り値の契約結果をFoundationで評価し、fatalな問題があれば例外にする。

## 9. PowerShell文法上のポイント

### `$script:` スコープ

`$script:DeviceListExportDomOperations` は、この `.ps1` ファイルがdot-sourceされたモジュール内で共有されるscriptスコープ変数である。
関数をまたいで同じoperation表を参照するために使う。

### ハッシュテーブル

operation定義はハッシュテーブルである。

```text
Operation名 = @{ MethodName = ...; MissingHelperBehavior = ... }
```

PowerShellのハッシュテーブルは、キーから値を取り出す辞書のような構造である。

### splatting

`Invoke-FoundationDomHelperMethod @parameters` の `@parameters` はsplattingである。
ハッシュテーブルのキーをパラメータ名として展開する。

たとえば、以下のように扱われる。

```text
@{
  HelperName = '__DeviceListExportDomHelper'
  MethodName = 'clickTaskButton'
}

↓

Invoke-FoundationDomHelperMethod -HelperName '__DeviceListExportDomHelper' -MethodName 'clickTaskButton'
```

## 10. 変更時の注意

### operation名を変える場合

`DomAdapter.ps1` がそのoperation名を呼んでいる。
operation名を変えるなら、DomAdapter側も変更する必要がある。

### JavaScriptメソッド名を変える場合

`dom/features/device-list-export/*.js` 側に同名メソッドが存在する必要がある。
PowerShell側だけ変更しても、ブラウザ側でメソッドが見つからない。

### MissingHelperBehaviorを安易に変えない

契約確認系を `Throw` にすると、契約結果として診断情報を返せなくなる。
クリック系を `ReturnContractFailure` にすると、実行できないクリックを契約失敗扱いで流してしまい、原因が曖昧になる。

### Awaitを外さない

`ClickTaskButton` と `ClickExportMenuItem` は非同期操作として扱う。
Awaitを外すと、クリック完了前に次のステップへ進み、メニュー待ちやダウンロード待ちが不安定になる可能性がある。

## 11. 本ドキュメント内容の要点

```text
- DomOperationsはPowerShellとJavaScript helperの対応表である
- helper名は__DeviceListExportFoundationである
- operationごとにhelper未登録時の扱いが違う
- Invoke / Wait / Assert は同じoperation定義を使って共通基盤へ委譲する
- JavaScriptメソッド名の変更はPowerShell側とJS側の契約変更である
```
