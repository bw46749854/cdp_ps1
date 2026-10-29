# modules/DeviceListExport/internal/DomAdapter.ps1

## 1. このファイルを一言でいうと

Workflowから見えるDeviceListExport用の画面操作関数を提供するファイルである。

`DomAdapter.ps1` は、業務的な名前のPowerShell関数を並べる。
その関数の中で、低い層の `DomOperations.ps1` を呼ぶ。

## このファイルを変更する典型ケース

- Workflowから呼ぶ画面操作の業務名が変わった場合
- DomOperationsへ渡す引数や戻り値の形が変わった場合
- DOM操作失敗時の扱いをFeature内で変える場合


## 2. このファイルが担当する範囲

```text
- DeviceListExport用DOM bundleを登録する
- 現在のページがDeviceListExport対象画面か判定する
- 初期DOM契約を検証する
- エクスポート対象画面契約を検証する
- 操作ボタンをクリックする
- 操作メニュー表示を待つ
- エクスポートメニュー項目をクリックする
- エクスポートクリック後のDOM契約を検証する
```

## 3. このファイルが担当しない範囲

```text
- JavaScript helper名の対応表を持つこと
- CSS selectorを定義すること
- CSVファイルを待つこと
- ダウンロード先を設定すること
```

JavaScript helper名の対応表は `DomOperations.ps1`、selectorは `dom/features/device-list-export/*.js` 側の責務である。

## 4. 関数呼び出しツリー

```text
Register-DeviceListExportDomAdapter
  └─ Register-FoundationDomBundle

Test-DeviceListExportPageIdentity
  ├─ Register-DeviceListExportDomAdapter
  ├─ Invoke-DeviceListExportDomOperation DetectPageIdentity
  └─ returns { Matched, Reason, Result }

Assert-DeviceListExportInitialContract
  └─ Assert-DeviceListExportDomOperationContract ValidateInitialContract

Assert-DeviceListExportExportPageContract
  └─ Assert-DeviceListExportDomOperationContract ValidateExportPageContract

Invoke-DeviceListExportClickTaskButton
  └─ Invoke-DeviceListExportDomOperation ClickTaskButton

Wait-DeviceListExportTaskMenuReady
  └─ Wait-DeviceListExportDomOperation IsTaskMenuReady

Invoke-DeviceListExportClickExportMenuItem
  └─ Invoke-DeviceListExportDomOperation ClickExportMenuItem

Assert-DeviceListExportPostcondition
  └─ Assert-DeviceListExportDomOperationContract ValidateExportPostcondition
```

## 5. 関数ごとの説明

### Register-DeviceListExportDomAdapter

`Context.JobDefinition.DomFeaturePaths` に指定されたDeviceListExport用JavaScript bundleをブラウザへ登録する。

実際の登録処理はFoundationの `Register-FoundationDomBundle` に委譲する。
この関数があることで、DeviceListExport側のWorkflowやDependenciesは共通基盤の詳細を直接知らなくてよい。

### Test-DeviceListExportPageIdentity

現在接続しているブラウザタブがDeviceListExport対象画面か確認する。

処理は次の通り。

```text
1. DeviceListExport用DOM bundleを登録する
2. DetectPageIdentity operationを実行する
3. JavaScript側の戻り値 ok が true なら Matched = true
4. 失敗時は理由文字列を作る
5. { Matched, Reason, Result } を返す
```

戻り値の形は次である。

```text
PageIdentityResult
  Matched : 対象画面ならtrue
  Reason  : 一致・不一致の理由
  Result  : JavaScript helperから返った詳細結果
```

`OpenPageMatchingIdentity` はこの `Matched` を見て対象タブを選ぶ。

### Assert-DeviceListExportInitialContract

初期DOM契約を検証する。

契約検証とは、画面操作の前提が満たされているかをまとめて確認する処理である。
JavaScript側の `validateInitialContract` を呼ぶ。

fatalな契約違反があれば、Foundation側で例外になる。

### Assert-DeviceListExportExportPageContract

エクスポート操作対象画面の契約を検証する。

操作ボタンや画面タイトルなど、エクスポート操作の前提が満たされているかを確認する。

### Invoke-DeviceListExportClickTaskButton

操作ボタンをクリックする。

JavaScript側の `clickTaskButton` を呼ぶ。
このoperationは非同期操作として扱われるため、`DomOperations.ps1` の定義では `Await = true` になっている。

### Wait-DeviceListExportTaskMenuReady

操作メニューが表示されるまで待つ。

内部では `IsTaskMenuReady` operationを繰り返し評価する。
戻り値がtrueになるまで待ち、指定秒数を超えるとタイムアウトになる。

### Invoke-DeviceListExportClickExportMenuItem

操作メニュー内の「CSV出力」項目をクリックする。

JavaScript側の `clickExportMenuItem` を呼ぶ。
このクリックにより、ブラウザのCSVダウンロードが開始される。

### Assert-DeviceListExportPostcondition

エクスポートクリック後のDOM契約を検証する。

クリックがDOM上で成立したか、クリック後に致命的な画面状態になっていないかを確認する。

## 6. DomAdapterがある理由

Workflowが直接 `Invoke-DeviceListExportDomOperation -Operation ClickTaskButton` と書くことも技術的にはできる。
しかし、それをするとWorkflowがDOM operation名を知ることになる。

このプロジェクトでは、次の分離を守る。

```text
Workflow
  「操作ボタンをクリックする」という業務手順を知る

DomAdapter
  その業務手順をDeviceListExport用DOM operationに変換する

DomOperations
  DOM operationをJavaScript helperメソッド名に変換する
```

## 7. 変更時の注意

### PageIdentity判定を削らない

複数タブが開いているとき、誤ったタブを操作する危険がある。
`Test-DeviceListExportPageIdentity` は、対象画面だけを選ぶための境界である。

### 契約検証をクリック後だけにしない

クリック前に画面構造が変わっている場合、クリック操作自体が危険になる。
そのため、初期契約、エクスポート対象画面契約、クリック後契約に分かれている。

### JavaScriptメソッド名をこのファイルに書かない

`clickTaskButton` や `validateExportPageContract` などのJavaScript名は `DomOperations.ps1` に閉じ込める。
このファイルには、業務名のPowerShell関数だけを置く。

## 8. 本ドキュメント内容の要点

```text
- DomAdapterはWorkflowから見える画面操作の窓口である
- PageIdentity判定は誤タブ操作防止のためにある
- 契約検証はクリック前後の安全確認である
- JavaScript helper名はDomOperationsに閉じ込められている
```
