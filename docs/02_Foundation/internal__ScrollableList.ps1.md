# main/modules/Foundation/internal/ScrollableList.ps1

## 1. このファイルを一言でいうと

このファイルは、画面に一部だけ表示されるスクロール可能な一覧を、重複なく最後まで処理するための共通Workflowです。

`InstalledAppExport` や `ScanTargetSync` のように、画面上の一覧をスクロールしながら処理するジョブで使われます。

## このファイルを変更する典型ケース

- Foundation共通サービスのcallback、戻り値、例外分類が変わった場合
- Feature moduleから使う共通境界の意味が変わった場合
- 複数Jobに影響する安全確認や診断情報が変わった場合


## 2. このファイルが担当する範囲

```text
- 処理済み行のキーを記録する
- 現在見えている行を取得する
- 未処理の表示行だけを処理する
- 未処理行がなければ下へスクロールする
- スクロールしても位置が変わらない状態を数える
- 期待件数に到達したら終了する
- 最大ループ数を超えたら停止する
- 結果オブジェクトを返す
```

## 3. このファイルが担当しない範囲

```text
- DOMから行をどう取得するか
- 行の一意キーを何にするか
- 1行を処理するときに何をするか
- 画面をどうスクロールするか
- InstalledAppExport固有、ScanTargetSync固有の業務判断
```

これらは、呼び出し元が `Operations` としてscriptblockを渡します。

## 4. なぜ Operations という形にしているのか

スクロール可能な一覧の走査には、共通部分と個別部分があります。

共通部分は次です。

```text
見えている行を取る
未処理行だけ処理する
処理済みキーを記録する
必要ならスクロールする
終了条件を判定する
```

一方で、ジョブごとに違う部分があります。

```text
InstalledAppExportでは、行キーは端末名や行識別子になる
ScanTargetSyncでは、行キーはendpoint名などになる
行を処理する内容もジョブごとに違う
DOMから見えている行を取る方法も画面ごとに違う
```

そのため、このファイルは「一覧走査の骨格」だけを持ち、個別処理はscriptblockとして外から受け取ります。

## 5. Operationsの契約

`Invoke-ScrollableListWorkflow` に渡す `Operations` は、次の4つのscriptblockを持つ必要があります。

```text
Operations
  GetVisibleRows : 現在画面に表示されている行の配列を返す
  GetRowKey      : 行から一意キーを取り出す
  ProcessRow     : 行1件を処理する
  ScrollDown     : 一覧を下へスクロールする
```

`Assert-ScrollableListOperations` は、この4つが存在し、すべてscriptblockであることを確認します。

## 6. 全体の処理フロー

```text
Invoke-ScrollableListWorkflow
  ├─ Assert-ScrollableListOperations
  ├─ Resolve-ScrollableListRuntime
  ├─ New-ScrollableListState
  ├─ for loop
  │   ├─ 期待件数に到達していれば終了
  │   ├─ Get-ScrollableListVisibleRowsStep
  │   │   └─ Operations.GetVisibleRows
  │   ├─ Invoke-ScrollableListUnprocessedRowsStep
  │   │   ├─ Get-UnprocessedVisibleRows
  │   │   ├─ Operations.GetRowKey
  │   │   ├─ Operations.ProcessRow
  │   │   └─ finallyでProcessedに記録
  │   ├─ 未処理行を処理できた場合は次ループへ
  │   └─ Invoke-ScrollableListScrollStep
  │       ├─ Operations.ScrollDown
  │       ├─ Runtime.SleepMilliseconds
  │       ├─ Test-ScrollableListScrollMoved
  │       └─ SameScrollCount更新
  ├─ Assert-ScrollableListProgress
  └─ Complete-ScrollableListWorkflow
```

## 7. Stateオブジェクトの形

`New-ScrollableListState` は、次の `[pscustomobject]` を返します。

```text
ScrollableListState
  TotalCount      : 期待件数
  Processed       : 処理済みキーを保持するhashtable
  LoopCount       : 現在までのループ回数
  SameScrollCount : スクロールしても位置が変わらなかった連続回数
```

`Processed` は配列ではなくhashtableです。  
理由は、キーが既に存在するかを `ContainsKey` で高速に判定するためです。

## 8. 戻り値オブジェクトの形

`Complete-ScrollableListWorkflow` は、次の形の結果を返します。

```text
ScrollableListResult
  ProcessedCount : 処理済み件数
  TotalCount     : 期待件数
  LoopCount      : 実行したループ回数
  Completed      : ProcessedCount >= TotalCount か
  ProcessedKeys  : 処理済みキー一覧
```

呼び出し元は、この結果を見て、期待件数に到達したかを判断できます。

## 9. 関数ごとの説明

## New-ScrollableListState

### 何をするか

一覧走査の状態を初期化します。

### 入力

```text
TotalCount : 処理したい期待件数
```

### 出力

`ScrollableListState` オブジェクトを返します。

### 変更時の注意

`Processed` をhashtable以外に変えると、`ContainsKey` を使っている後続関数が壊れます。

## Assert-ScrollableListOperations

### 何をするか

`Operations` に必須scriptblockが揃っているか確認します。

### 失敗条件

```text
- GetVisibleRows がない
- GetRowKey がない
- ProcessRow がない
- ScrollDown がない
- いずれかがscriptblockではない
```

### なぜ必要か

この確認をせずに処理を始めると、ループ途中で分かりにくいエラーになります。  
最初に契約違反を止めることで、呼び出し元の実装ミスを早く見つけられます。

### PowerShell文法上のポイント

```text
$Operations.PSObject.Properties.Name -contains $name
```

`[pscustomobject]` が持つプロパティ名一覧を調べています。  
PowerShellでは、オブジェクトのプロパティをこのように動的に確認できます。

```text
$Operations.$name -is [scriptblock]
```

プロパティ値がscriptblockかを確認しています。

## New-ScrollableListRuntime / Assert-ScrollableListRuntime / Resolve-ScrollableListRuntime

### 何をするか

スクロール後の待機処理を差し替え可能にします。

既定では、次の処理です。

```text
SleepMilliseconds = { param([int]$Milliseconds) Start-Sleep -Milliseconds $Milliseconds }
```

### なぜ必要か

本番では実際に待機する必要があります。  
しかしテストで毎回 `Start-Sleep` すると、テストが遅くなります。

そこで、`Runtime.SleepMilliseconds` を外から渡せるようにしています。  
テストでは「何ミリ秒待つ予定だったか記録するだけ」のscriptblockに差し替えられます。

### 変更時の注意

`Runtime` の契約を増やす場合、`Assert-ScrollableListRuntime` とテストも更新する必要があります。

## Get-UnprocessedVisibleRows

### 何をするか

現在表示されている行のうち、まだ処理していない行だけを返します。

### 入力

```text
Rows      : 画面に見えている行配列
Processed : 処理済みキーhashtable
GetRowKey : 行からキーを取り出すscriptblock
```

### 出力

未処理行の配列を返します。

### 重要な仕様

キーが空の行は無視します。

```text
$key が空 → continue
```

キーが空だと、処理済み管理ができません。  
同じ行を重複処理したり、別行を同じものとして扱ったりする危険があるためです。

## Get-ScrollableListVisibleRowsStep

### 何をするか

`Operations.GetVisibleRows` を呼び、現在見えている行を取得します。

### 失敗条件

取得件数が0件の場合、`EmptyRowsMessage` をthrowします。

### なぜ0件でthrowするのか

スクロール可能一覧で「表示行が0件」という状態は、通常、以下のどれかです。

```text
- 画面がまだ読み込まれていない
- DOM取得処理が壊れている
- セレクタが画面変更で合わなくなった
- 対象一覧が本当に空
```

この共通関数では、0件のまま黙って終了すると、成功したように見えてしまいます。  
そのため、呼び出し元が指定したメッセージで明示的に失敗させます。

## Invoke-ScrollableListUnprocessedRowsStep

### 何をするか

現在見えている行から未処理行を取り出し、1件ずつ `Operations.ProcessRow` を実行します。

### 重要な仕様

```text
try { ProcessRow }
finally { Processed[$key] = $true }
```

`ProcessRow` が成功しても失敗しても、キーを処理済みとして記録します。

### なぜ finally で処理済みにするのか

ある行の処理が失敗した後、同じ行を何度も再処理すると、一覧走査が前に進まなくなる可能性があります。

このWorkflowでは、行ごとの成否管理は呼び出し元の `ProcessRow` に任せています。  
共通Workflow側では「このキーは一度処理を試みた」と記録し、次の行や次のスクロールへ進めます。

### 変更時の注意

失敗時に処理済みにしない設計へ変えると、同じ失敗行でループし続ける危険があります。  
リトライ機構を入れる場合は、単に `finally` を消すのではなく、リトライ回数や失敗記録の設計が必要です。

## Test-ScrollableListScrollMoved

### 何をするか

スクロール操作の結果から、実際に表示位置が変わったかを判定します。

### 入力

```text
ScrollResult : ScrollDownが返したオブジェクト
```

### 出力

```text
true  : moved または changed が true
false : それ以外
```

### なぜ moved と changed の両方を見るのか

DOM側の実装やジョブごとの戻り値名の違いを吸収するためです。  
ある操作は `moved` を返し、別の操作は `changed` を返す場合があります。

## Invoke-ScrollableListScrollStep

### 何をするか

未処理行が見つからなかった場合に、一覧を下へスクロールします。

処理の流れは次です。

```text
1. Operations.ScrollDown を呼ぶ
2. 700ms待つ
3. スクロール位置が変わったか判定する
4. 変わったなら SameScrollCount を0に戻す
5. 変わらなければ SameScrollCount を増やす
6. SameScrollCount が SameScrollLimit 以上なら終了指示を返す
```

### 入力

```text
State           : 走査状態
Operations      : ScrollDownを含む操作群
Runtime         : SleepMillisecondsを含む実行環境
Logger          : ログ出力用
SameScrollLimit : 変化なしスクロールを何回まで許容するか
```

### 出力

```text
true  : 走査を続ける
false : これ以上スクロールできないと判断し、走査を止める
```

### 変更時の注意

待機時間 `700ms` を短くしすぎると、画面描画が追いつかず、同じ位置のままと誤判定する可能性があります。  
長くしすぎると、処理全体が遅くなります。

## Assert-ScrollableListProgress

### 何をするか

最大走査ループ数を超えていないか確認します。

### なぜ必要か

スクロール一覧では、DOM取得やスクロール判定が壊れると無限ループに近い状態になる可能性があります。

`MaxScanLoops` は、その暴走を止める安全弁です。

## Complete-ScrollableListWorkflow

### 何をするか

走査状態から、呼び出し元へ返す結果オブジェクトを作ります。

### 注意点

`Completed` は、次の条件です。

```text
Processed.Count >= TotalCount
```

すべての行が業務的に成功したという意味ではありません。  
「期待件数分の行について処理を試みた」という意味です。

## Invoke-ScrollableListWorkflow

### 何をするか

このファイルの主関数です。  
スクロール一覧の走査全体を実行します。

### 入力

```text
TotalCount       : 期待件数
Operations       : GetVisibleRows / GetRowKey / ProcessRow / ScrollDown
Logger           : ログ出力用
MaxScanLoops     : 最大ループ数
SameScrollLimit  : スクロール変化なしの許容回数
EmptyRowsMessage : 表示行0件時のエラーメッセージ
Runtime          : SleepMilliseconds差し替え用
```

### 出力

`ScrollableListResult` を返します。

### 失敗条件

```text
- Operations契約違反
- Runtime契約違反
- 表示行が0件
- 最大走査ループ数を超過
- Operations.ProcessRow 内で例外が発生し、それが呼び出し元で処理されない
- Operations.ScrollDown 内で例外が発生する
```

### 設計上の重要点

この関数は、行処理の中身を知りません。  
`ProcessRow` がCSVダウンロードなのか、チェックボックス操作なのか、結果記録なのかを知りません。

これにより、画面一覧をスクロールする共通パターンだけを再利用できます。

## 10. PowerShell文法上の重要点

## scriptblockを関数のように実行する

```text
& $Operations.GetVisibleRows
& $Operations.ProcessRow $row
```

`&` は呼び出し演算子です。  
変数に入っているscriptblockやCommandInfoを実行するときに使います。

このプロジェクトでは、依存差し替えのためにscriptblockが多用されています。

## hashtableで処理済み管理をする

```text
$State.Processed[$key] = $true
$State.Processed.ContainsKey($key)
```

配列で処理済みを管理すると、毎回先頭から検索する必要があります。  
hashtableならキー存在確認が簡単です。

## forループで上限を持たせる

```text
for ($loop = 0; $loop -lt $MaxScanLoops; $loop++)
```

スクロール処理は外部画面状態に依存します。  
外部画面が壊れていた場合に無限ループしないよう、最大回数を持たせています。

## 11. このファイルを変更するときの判断基準

```text
- Operations契約を変える場合、InstalledAppExport / ScanTargetSync 側のDependenciesやWorkflowに影響する
- ProcessRow失敗時にProcessedへ記録する仕様を変えると、失敗行の扱いが変わる
- SameScrollLimitやMaxScanLoopsの意味を変えると、一覧の終端判定が変わる
- Completedは「成功件数」ではなく「処理試行件数」である点を維持する
- DOM固有のselectorや業務固有の判定をこのファイルに入れてはいけない
```

## 12. このファイルを守っているテスト

```text
Foundation.ScrollableList.Tests.ps1
  - Operationsに必須scriptblockがない場合にthrowする
  - 未処理の表示行を処理し、Completed=trueを返す
  - 表示行が0件の場合、指定メッセージでthrowする
  - Runtime.SleepMillisecondsを差し替えられる
  - Runtime契約違反をWorkflow開始前に検出する

Foundation.PublicApi.Tests.ps1
  - Invoke-ScrollableListWorkflow が公開APIとして存在すること
```

## 13. 本ドキュメント内容の要点

```text
- ScrollableList.ps1 はDOM操作そのものではなく、スクロール一覧走査の骨格を担当する
- 個別処理は Operations のscriptblockとして外から渡す
- Processed hashtable により、同じ行の重複処理を避ける
- ProcessRow失敗時も finally で処理済みにする設計には意味がある
- Completed は業務成功ではなく、期待件数分を処理対象として扱ったかを表す
```
