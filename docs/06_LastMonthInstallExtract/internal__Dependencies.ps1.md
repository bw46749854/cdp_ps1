# main/modules/LastMonthInstallExtract/internal/Dependencies.ps1

## 1. このファイルを一言でいうと

`LastMonthInstallExtract` のWorkflowとRunnerが使う外部依存を、`Input`、`Output`、`Logger`、`Timing` というPortにまとめるファイルです。

## このファイルを変更する典型ケース

- 依存port、callback名、既定実装の作り方が変わった場合
- Workflow / Runner が使う外部I/Oの差し替え境界が変わった場合
- 依存検証の粒度や必須callbackが変わった場合


## 2. このファイルが必要な理由

`LastMonthInstallExtract` はブラウザを使わない代わりに、ファイルシステム、現在日時、ログ出力に依存します。これらを関数内で直接呼ぶと、テストが難しくなります。

そこで、このファイルでは次のような callback の束を作ります。

```text
Dependencies
  Input
    GetTargetCsvFiles
    ReadAllBytes
  Output
    InitializeOutputDirectory
    ExportInstallationCsv
    ExportFailureCsv
  Logger
    WriteInfo
    WriteWarning
    WriteSection
  Timing
    Now
    TimestampText
```

## 3. 関数呼び出しツリー

```text
Resolve-LastMonthInstallExtractJobDependencies
  ├─ Resolve-LastMonthInstallExtractInstallationWorkflowDependencies
  │   ├─ New-LastMonthInstallExtractInputPort
  │   ├─ New-LastMonthInstallExtractLoggerPort
  │   ├─ New-LastMonthInstallExtractTimingPort
  │   └─ Assert-LastMonthInstallExtractInstallationWorkflowDependencies
  ├─ New-LastMonthInstallExtractOutputPort
  │   └─ New-LastMonthInstallExtractFileSystemPort
  └─ Assert-LastMonthInstallExtractJobDependencies
```

Workflow単体に必要なのは `Input`、`Logger`、`Timing` です。Runnerまで含めると、CSV出力のために `Output` も必要になります。

## 4. 関数ごとの説明

### Get-LastMonthInstallExtractDependencyProperty

hashtableではなく pscustomobject のプロパティを安全に取り出す補助関数です。指定プロパティがなければ `$null` を返します。

### Get-LastMonthInstallExtractCallbackScriptBlock

指定された callback が `[scriptblock]` かどうかを検証します。

ここで明示的に検証することで、Workflowの途中で「メソッドがない」「文字列を実行しようとした」といった分かりにくいエラーになるのを防ぎます。

### New-LastMonthInstallExtractLoggerPort

`Context.Services.Logger` が既に適切な形ならそれを使います。なければ、Foundationの `Write-FoundationLog` と `Write-FoundationSection` を callback に包みます。

### New-LastMonthInstallExtractInputPort

実ファイル入力用のPortです。

| callback | 実体 |
|---|---|
| `GetTargetCsvFiles` | `Get-LastMonthInstallExtractTargetCsvFileInfos` |
| `ReadAllBytes` | `Read-LastMonthInstallExtractFileBytes` |

### New-LastMonthInstallExtractFileSystemPort

`Context.Services.FileSystem` に必要なscriptblockが揃っているか検証します。

必要なscriptblockは次です。

```text
InitializeOutputDirectory
AssertSafeDirectory
TestPathUnderDirectory
RemoveFileIfExists
```

### New-LastMonthInstallExtractOutputPort

出力CSV作成用のPortです。`ExportInstallationCsv` と `ExportFailureCsv` を callback 化し、内部で `FileSystem` service を使います。

### New-LastMonthInstallExtractTimingPort

`Context.Services.Timing` があればそれを使い、なければ `Get-Date` を使う既定実装を返します。

テストではここを差し替えることで、前月範囲や失敗行のTimestampを固定できます。

### Assert-LastMonthInstallExtractInstallationWorkflowDependencies

Workflow単体に必要な依存が揃っているか検証します。

### Assert-LastMonthInstallExtractJobDependencies

Runnerまで含めたジョブ全体に必要な依存が揃っているか検証します。

## 5. PowerShell文法上のポイント

### scriptblock

`{ ... }` で作る実行可能な処理ブロックです。このプロジェクトでは「関数を直接呼ばず、後で差し替え可能な処理」として使っています。

### GetNewClosure

callbackの中で参照している変数を、その時点の値として閉じ込めるために使います。

たとえば `New-LastMonthInstallExtractLoggerPort` は `$logger` や `$writeFoundationLogCommand` を callback 内で使います。`GetNewClosure()` がないと、後でスコープが変わったときに参照が不安定になる可能性があります。

## 6. 変更時の注意

Workflowに `Read-LastMonthInstallExtractFileBytes` や `Export-Csv` を直接書かないでください。`Dependencies.ps1` の価値は、I/Oを差し替え可能な境界として隠すことです。

`Assert-*Dependencies` を削ると、依存不足の検出が遅れ、Workflowの途中で分かりにくい例外になります。

`Timing.Now` を使わずに直接 `Get-Date` を呼ぶと、前月判定のテストが不安定になります。

## 7. 関連するテスト

- `LastMonthInstallExtract.Dependencies.Tests.ps1`: 必須callback不足時の拒否、Workflow用依存とJob用依存の違い、注入依存の保持を確認する。
- `LastMonthInstallExtract.Workflow.Tests.ps1`: Workflow-only dependenciesで処理できることを確認する。
