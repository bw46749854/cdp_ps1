# Foundationテスト

## 1. 対象

このドキュメントでは、Foundationに関するテストを整理する。

```text
Foundation.Config.Tests.ps1
Foundation.JobRegistry.Tests.ps1
Foundation.JobRegistry.UsesDom.Tests.ps1
Foundation.RunContext.Tests.ps1
Foundation.Entrypoint.Tests.ps1
Foundation.Logging.Tests.ps1
Foundation.FileSystem.Tests.ps1
Foundation.Errors.Tests.ps1
Foundation.DomBundle.Tests.ps1
Foundation.DomBundle.UsesDom.Tests.ps1
Foundation.DomContract.Tests.ps1
Foundation.DomHelper.Tests.ps1
Foundation.ScrollableList.Tests.ps1
Foundation.CdpInternals.Tests.ps1
Foundation.CdpRuntime.Tests.ps1
Foundation.CdpTransport.Errors.Tests.ps1
Foundation.PublicApi.Tests.ps1
```

## 2. Config / JobRegistry / Entrypoint

### Foundation.Config.Tests.ps1

このテストは、`foundation.config.psd1` の読み方を固定する。

守っている仕様は以下である。

```text
- Common が存在する
- Jobs が存在する
- Common / Jobs は hashtable である
- Config.Jobs[JobName] からジョブ別設定を取得できる
- 存在しないJobNameやhashtableでないJob設定はエラーになる
```

このテストが落ちた場合、`Config.ps1` または `foundation.config.psd1` の構造変更を疑う。

### Foundation.JobRegistry.Tests.ps1

このテストは、`foundation.jobs.psd1` の読み方を固定する。

特に重要なのは以下である。

```text
JobName
  ↓
JobDefinition
  ├─ ModulePath
  ├─ CommandName
  ├─ DomFeaturePaths
  └─ UsesDom
```

守っている仕様は以下である。

```text
- Jobsキーが必須
- 各JobDefinitionにModulePathとCommandNameが必須
- CommandNameはPowerShellコマンド名として妥当である必要がある
- DomFeaturePathとDomFeaturePathsは同時指定できない
- DomFeaturePathsは配列でなければならない
- 未使用ジョブのファイル存在確認は通常import時に要求しない
- 実行対象ジョブのModulePathは解決できる必要がある
```

### Foundation.JobRegistry.UsesDom.Tests.ps1

`UsesDom` の意味を固定するテストである。

```text
UsesDom = false
  → DOM feature path を持ってはいけない

UsesDom未指定 + DomFeaturePathsあり
  → DOMジョブとして扱える

file-only job
  → DOM bundle登録対象にしない
```

LastMonthInstallExtractのようなDOMなしジョブを追加・変更するときに重要である。

### Foundation.Entrypoint.Tests.ps1

`run_job.ps1` からFoundation entrypointを通り、JobRegistryで解決したmoduleとcommandを呼ぶ流れを守る。

固定している仕様は次である。

```text
run_job.ps1
  ↓
Invoke-FoundationEntrypoint
  ↓
foundation.jobs.psd1 から ModulePath / CommandName を取得
  ↓
Import-Module ModulePath
  ↓
Get-Command CommandName
  ↓
& $command -Context $context
```

このテストが落ちた場合、`Bootstrap.ps1`、`JobRegistry.ps1`、`run_job.ps1` のいずれかが起動契約を壊している可能性がある。

## 3. RunContext / Services

### Foundation.RunContext.Tests.ps1

`Context` に何が入るかを固定する。

重要な仕様は以下である。

```text
Context
  ├─ RootPath
  ├─ RunId
  ├─ JobName
  ├─ JobDefinition
  ├─ ConfigPath
  ├─ JobRegistryPath
  ├─ Config
  ├─ CommonSettings
  ├─ JobSettings
  ├─ Logger
  ├─ Services
  └─ Page
```

`Services` には、Feature moduleが使う共通portが入る。

```text
Services.Logger
Services.FileSystem
Services.Browser
Services.Timing
```

このテストが落ちる典型例は以下である。

```text
Contextのプロパティ名を変えた
Servicesのport名を変えた
Browser service作成時にCDP接続を即時実行してしまった
script-scope loggerに依存した
```

## 4. Logging / FileSystem / Errors

### Foundation.Logging.Tests.ps1

ログ出力の構成を固定する。  
特に、設定からconsole抑制loggerを作れることを確認する。

### Foundation.FileSystem.Tests.ps1

安全なファイル操作を固定する。

```text
- 許可ディレクトリ配下のpathは許可
- 許可ディレクトリ外のpathは拒否
- 削除は許可ディレクトリ内だけ
- 許可外のファイル削除は実行しない
```

このテストは、OutputやDownloadの安全性の土台である。

### Foundation.Errors.Tests.ps1

致命的エラー分類を固定する。

特に、DOM helper登録失敗はfatal errorとして扱う。  
空メッセージはfatal扱いしない。

## 5. DomBundle / DomContract / DomHelper

### Foundation.DomBundle.Tests.ps1

DOM JavaScript bundle登録の仕様を固定する。

重要な仕様は以下である。

```text
- ハードコードされたJobNameではなく、JobDefinitionのDomFeaturePathsを見る
- DomFeaturePathsの順番通りにJSを結合する
- DomFeaturePathとDomFeaturePathsの同時指定は禁止
- Context.JobDefinitionからDOM bundleを登録できる
- RootPath + JobName互換の古い呼び方も一定範囲で維持する
```

このテストが落ちた場合、`DomBundle.ps1` と `foundation.jobs.psd1` の関係を確認する。

### Foundation.DomBundle.UsesDom.Tests.ps1

DOMなしジョブにDOM bundleを作らないことを固定する。

```text
UsesDom = false のジョブ
  → Register-FoundationDomBundle は拒否
```

LastMonthInstallExtract系の変更時に重要である。

### Foundation.DomContract.Tests.ps1

JavaScript helperの契約チェック結果の扱いを固定する。

```text
result = null
  → エラー

fatal checkあり
  → throw

warningのみ
  → warning出力して継続

failureなし
  → warningもthrowもしない
```

画面変更による契約違反をどう扱うかを決めるテストである。

### Foundation.DomHelper.Tests.ps1

PowerShellからJavaScript helper methodを呼ぶ式の生成と実行を固定する。

主な仕様は以下である。

```text
- helper名、method名、arguments、await指定を1つのJavaScript式に組み立てる
- helper名とmethod名はJavaScript識別子として妥当でなければならない
- helperが存在しないとき、契約失敗オブジェクトとして扱える
- Invoke-FoundationJavaScriptへtimeout付きで委譲する
- Wait系はTiming runtimeを注入してpollingする
```

## 6. ScrollableList

### Foundation.ScrollableList.Tests.ps1

スクロール可能な一覧を処理する共通Workflowの仕様を固定する。

代表仕様は以下である。

```text
- 必要なoperation scriptblockが揃っていない場合はエラー
- 表示中の未処理行だけを処理する
- 完了条件を満たすと終了する
- visible rowがない場合は設定されたメッセージでthrowする
- スクロールしても新しい行が増えない場合は安全に止める
```

InstalledAppExportの一覧走査はこの共通Workflowに依存している。

## 7. CDP系テスト

### Foundation.CdpInternals.Tests.ps1

CDP内部分割の契約を固定する。

```text
CdpSession
  command timeout、command id、websocket状態を持つ

CdpTransport
  HTTP / WebSocket / Console / Timing を注入可能なportとして提供する

CdpConnection / CdpCommand
  低レベル送受信をtransport経由で行う
```

### Foundation.CdpRuntime.Tests.ps1

Feature moduleから見えるCDP Runtime facadeの仕様を固定する。

代表仕様は以下である。

```text
- Runtime.evaluateを安全なoptionで呼ぶ
- JavaScript例外descriptionをPowerShell側へ表面化する
- Browser.setDownloadBehaviorが使えない場合はPage.setDownloadBehaviorへfallbackする
- page identity matcherで対象タブを選べる
- RunContext close時にpage-owned CDP sessionを閉じる
```

### Foundation.CdpTransport.Errors.Tests.ps1

異常系を固定する。

```text
- CDP応答JSONが壊れている場合はcommand context付きでエラー
- CDP error responseはmethodとcommand id付きで表面化
- 関係ないcommand idの応答は無視して待つ
- receive resultがnullならWebSocket close扱い
- deadline超過時はtransport abort
- close失敗時はwarningし、disposeは行う
```

CDP層は低レベルで壊れ方が複雑なため、このテストは変更時に重要である。
