# modules/DeviceListExport/internal/Dependencies.ps1

## 1. このファイルを一言でいうと

`Workflow.ps1` が直接呼ぶ部品を、scriptblockの束として組み立てるファイルである。

Workflowは、`Register-DeviceListExportDomAdapter` や `Wait-DeviceListExportDownloadedCsv` を直接呼ばない。
代わりに、`Dependencies` オブジェクトに入ったscriptblockを呼ぶ。

これにより、テストではDOMやファイルシステムを実際に操作せず、偽物のscriptblockに差し替えられる。

## このファイルを変更する典型ケース

- 依存port、callback名、既定実装の作り方が変わった場合
- Workflow / Runner が使う外部I/Oの差し替え境界が変わった場合
- 依存検証の粒度や必須callbackが変わった場合


## 2. このファイルが担当する範囲

```text
- pscustomobjectから指定プロパティを安全に取り出す
- callbackがscriptblockであることを検証する
- 本番用DOM callbackを作る
- 本番用Download callbackを作る
- Logger portを作る
- Timing portを作る
- Workflowに必要な依存が揃っているか検証する
- 引数で渡されたDependenciesと本番用依存を合成する
```

## 3. このファイルが担当しない範囲

```text
- DOM操作そのもの
- CSVファイル探索そのもの
- Workflowの処理順序
- ログの出力先実装
```

ここでは「何を呼ぶか」を束ねるだけで、実処理の中身は各担当ファイルに置く。

## 4. 依存オブジェクトの形

`Resolve-DeviceListExportWorkflowDependencies` が返すオブジェクトは次の形である。

```text
Dependencies
  Dom
    Register
    AssertInitialContract
    AssertExportPageContract
    ClickTaskButton
    WaitTaskMenuReady
    ClickExportMenuItem
    AssertPostcondition

  Download
    WaitDownloadedCsv
    RenameDownloadedCsv

  Logger
    WriteInfo
    WriteWarning
    WriteObject

  Timing
    TimestampText
    SleepMilliseconds
```

Workflowはこの形を前提にする。

## 5. 関数呼び出しツリー

```text
Resolve-DeviceListExportWorkflowDependencies
  ├─ Get-DeviceListExportDependencyProperty
  ├─ New-DeviceListExportDomCallbacks
  │   ├─ Get-DeviceListExportDependencyCommand x 複数
  │   └─ returns Dom callbacks
  ├─ New-DeviceListExportDownloadCallbacks
  │   ├─ Get-DeviceListExportDependencyCommand x 2
  │   └─ returns Download callbacks
  ├─ New-DeviceListExportLoggerPort
  │   ├─ Get-DeviceListExportDependencyProperty x 複数
  │   └─ fallback to Write-FoundationLog / Write-FoundationObject
  ├─ New-DeviceListExportTimingPort
  │   └─ fallback to Get-Date / Start-Sleep
  ├─ Assert-DeviceListExportWorkflowDependencies
  │   └─ Get-DeviceListExportCallbackScriptBlock x 複数
  └─ return resolved Dependencies
```

## 6. 関数ごとの説明

### Get-DeviceListExportDependencyProperty

任意のオブジェクトから、指定されたプロパティ値を安全に取り出す。

PowerShellでは、存在しないプロパティにアクセスしても状況によって分かりにくい挙動になることがある。
この関数では、プロパティがなければ `$null` を返す。

用途は、外部から渡された任意の `Dependencies` オブジェクトを扱うためである。

### Get-DeviceListExportCallbackScriptBlock

指定したcallbackがscriptblockであることを保証する。

```text
Callbacks.Dom.Register が存在しない
Callbacks.Dom.Register が文字列である
Callbacks.Dom.Register がnullである
```

このような場合は例外を投げる。
Workflowが実行途中で意味不明なエラーを出すより、依存解決時点で不足を明確にするためである。

### Get-DeviceListExportDependencyCommand

関数名から `CommandInfo` を取得する。

```text
Get-Command -Name <Name> -CommandType Function
```

単に名前文字列をscriptblock内に書くのではなく、依存構築時に `CommandInfo` を取得して閉じ込める。
これにより、Workflow実行時のスコープや名前解決に依存しにくくなる。

### New-DeviceListExportModuleBoundScriptBlock

モジュールスコープに束縛されたscriptblockを作る。

`Test-DeviceListExportPageIdentity` はDeviceListExportモジュール内部関数である。
ページ識別用callbackはFoundation側から呼ばれるため、単純なscriptblockだと関数解決スコープがずれる可能性がある。

この関数では、可能ならモジュールの `NewBoundScriptBlock` を使い、無理なら `GetNewClosure()` で現在スコープを閉じ込める。

### New-DeviceListExportPageIdentityMatcher

ブラウザタブがDeviceListExport対象ページかどうかを判定するcallbackを作る。

戻り値は次のようなscriptblockである。

```text
param($PageTarget, $Session)
Test-DeviceListExportPageIdentity -Context $Context
```

`PageTarget` や `Session` を受け取る形にしているのは、Foundationの `OpenPageMatchingIdentity` 側がその形でcallbackを呼ぶためである。
DeviceListExport側では、実際の判定に `$Context` を使う。

### New-DeviceListExportDomCallbacks

DOM操作用callbackの束を作る。

対応は次の通り。

| callback | 実際に呼ぶ関数 |
|---|---|
| `Register` | `Register-DeviceListExportDomAdapter` |
| `AssertInitialContract` | `Assert-DeviceListExportInitialContract` |
| `AssertExportPageContract` | `Assert-DeviceListExportExportPageContract` |
| `ClickTaskButton` | `Invoke-DeviceListExportClickTaskButton` |
| `WaitTaskMenuReady` | `Wait-DeviceListExportTaskMenuReady` |
| `ClickExportMenuItem` | `Invoke-DeviceListExportClickExportMenuItem` |
| `AssertPostcondition` | `Assert-DeviceListExportPostcondition` |

Workflowはこのcallback名だけを知る。
DomAdapterやDomOperationsの内部関数名をWorkflowに直接書かない。

### New-DeviceListExportDownloadCallbacks

ダウンロード処理用callbackの束を作る。

| callback | 実際に呼ぶ関数 |
|---|---|
| `WaitDownloadedCsv` | `Wait-DeviceListExportDownloadedCsv` |
| `RenameDownloadedCsv` | `Rename-DeviceListExportDownloadedCsv` |

Workflowはファイル探索やMove-Itemの詳細を知らない。

### New-DeviceListExportLoggerPort

Workflowから使うLogger portを作る。

すでに `$Context.Services.Logger` に `WriteInfo` と `WriteObject` がscriptblockとして入っていれば、それを使う。
なければ、`Context.Logger` と共通関数 `Write-FoundationLog` / `Write-FoundationObject` からLogger portを作る。

これにより、テスト時にはログ出力を簡単に差し替えられる。

### New-DeviceListExportTimingPort

時刻とSleep処理のportを作る。

```text
TimestampText
  Get-DateをMMdd形式にする。
  最終出力ファイル名の {0} に入る。

SleepMilliseconds
  Context.Services.Timing.SleepMilliseconds があれば使う。
  なければ Start-Sleep -Milliseconds を使う。
```

`TimestampText` をportにしている理由は、テスト時に日付を固定できるようにするためである。

### Assert-DeviceListExportWorkflowDependencies

Workflowが必要とするcallbackがすべてscriptblockであることを確認する。

この検証がないと、Workflowの途中で `& $null` のような失敗になり、どの依存が足りないのか分かりにくい。

### Resolve-DeviceListExportWorkflowDependencies

本番用依存と外部指定依存を合成する中心関数である。

処理は次の通り。

```text
1. Dependenciesがnullなら空オブジェクトを作る
2. Dependencies.Domがなければ本番用Dom callbacksを作る
3. Dependencies.Downloadがなければ本番用Download callbacksを作る
4. Dependencies.Loggerがなければ本番用Logger portを作る
5. Dependencies.Timingがなければ本番用Timing portを作る
6. 必須callbackを検証する
7. resolved Dependenciesを返す
```

部分差し替えができる点が重要である。
たとえば、テストでDownloadだけ差し替え、DomやLoggerは本番用を使うこともできる。

## 7. PowerShell文法上のポイント

### `[pscustomobject]@{ ... }`

名前付きプロパティを持つ軽量オブジェクトを作る構文である。
ここでは、callbackの束を作るために使っている。

### `GetNewClosure()`

scriptblockが作られた時点の変数を閉じ込める。

たとえば `New-DeviceListExportDomCallbacks` では、`$registerCommand` などのCommandInfoをscriptblockに閉じ込める。
これにより、後でscriptblockを実行したときも同じ関数を呼べる。

### `& $command`

`$command` に入っている `CommandInfo` やscriptblockを実行する。
関数名を文字列で直接呼ぶのではなく、構築済みのコマンドを実行している。

## 8. 変更時の注意

### callback名を変える場合

Workflow側でも同じ名前を使っている。
たとえば `ClickExportMenuItem` を `ClickExport` に変えるなら、`Workflow.ps1` と `Assert-DeviceListExportWorkflowDependencies` も合わせて変える必要がある。

### scriptblock検証を削除しない

依存不足の発見が遅れる。
Workflow途中で失敗すると、原因がDOMなのかDownloadなのかLoggerなのか分かりにくくなる。

### TimestampTextをWorkflowに直書きしない

`Get-Date` をWorkflowに直接書くと、テストで出力ファイル名を固定しにくくなる。
時刻は外部状態なので、Timing portに閉じ込める。

### CommandInfoを閉じ込める設計を単純な関数名呼び出しに戻さない

PowerShellのスコープやモジュール内private関数の名前解決に依存する。
テストや呼び出し元が変わったときに壊れやすくなる。

## 9. 本ドキュメント内容の要点

```text
- DependenciesはWorkflowの呼び出し先をscriptblockで束ねる
- 本番処理とテスト用処理を差し替えるために存在する
- Dom / Download / Logger / Timing の4分類がある
- GetNewClosureやCommandInfoはPowerShellのスコープ問題を避けるために使われる
- Workflowは具体的な関数名ではなくcallback名を呼ぶ
```
