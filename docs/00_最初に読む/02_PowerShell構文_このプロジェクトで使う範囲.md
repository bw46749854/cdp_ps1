# PowerShell構文: このプロジェクトで使う範囲

## このドキュメントの目的

このドキュメントは、PowerShell全体の入門ではありません。

このプロジェクトのソースを読むために必要な構文だけを説明します。説明は、実際のプロジェクト内での使われ方に限定します。

## cmdlet とユーザー定義関数の違い

PowerShellには、最初から用意されている命令と、このプロジェクトで定義された関数があります。

| 種類 | 例 | 説明 |
|---|---|---|
| cmdlet | `Import-Module`, `Get-Command`, `Test-Path`, `Resolve-Path`, `Join-Path` | PowerShellや.NET環境が提供する標準機能 |
| ユーザー定義関数 | `Invoke-FoundationEntrypoint`, `Open-InstalledAppExportDetailPanel`, `Get-ScanTargetSyncEvaluation` | このプロジェクト内で `function` により定義された機能 |

見た目はどちらも同じように呼べます。

```powershell
Test-Path -LiteralPath $ConfigPath
Get-ScanTargetSyncEvaluation -ScanCompletedRaw $value -LastConnectedRaw $other -DaysThreshold 7
```

違いは、どこで定義されているかです。

- `Test-Path` はPowerShell標準です。
- `Get-ScanTargetSyncEvaluation` は `modules/ScanTargetSync/internal/Rules.ps1` にあります。

ソースを読むときは、まず「これは標準cmdletか、このプロジェクトの関数か」を区別します。

## `param(...)`

`param(...)` は、スクリプトや関数が受け取る引数を定義します。

例:

```powershell
function Invoke-FoundationEntrypoint {
    param(
        [Parameter(Mandatory)][string]$RootPath,
        [Parameter(Mandatory)][string]$ConfigPath,
        [Parameter(Mandatory)][string]$JobName
    )
}
```

この例では、関数を呼ぶときに `RootPath`, `ConfigPath`, `JobName` が必要です。

```powershell
Invoke-FoundationEntrypoint -RootPath $dir -ConfigPath $config -JobName InstalledAppExport
```

## `[Parameter(Mandatory)]`

`[Parameter(Mandatory)]` は、その引数が必須であることを表します。

この指定がある引数を渡さないと、PowerShellが入力を要求したり、エラーになったりします。

このプロジェクトでは、必須の前提を関数の入口で明示するために使われています。

例:

```powershell
param(
    [Parameter(Mandatory)][string]$JobName
)
```

`JobName` がないと、どのジョブを実行するか決められません。そのため必須です。

## 型指定: `[string]`, `[int]`, `[bool]`, `[datetime]`

PowerShellでは、引数や変数に型を付けられます。

| 型 | 意味 | このプロジェクトでの例 |
|---|---|---|
| `[string]` | 文字列 | ジョブ名、ファイルパス、端末名 |
| `[int]` | 整数 | タイムアウト秒数、閾値日数 |
| `[bool]` | 真偽値 | 対象か、CSVエラーか |
| `[datetime]` | 日付時刻 | CSV上の日付判定 |
| `[object]` | 任意の値 | 設定オブジェクトや戻り値全般 |
| `[pscustomobject]` | 名前付きプロパティを持つオブジェクト | 結果行、評価結果、依存オブジェクト |

例:

```powershell
param(
    [Parameter(Mandatory)][int]$DaysThreshold
)
```

これは、`DaysThreshold` が数値であることを表します。

## `[AllowNull()]`

`[AllowNull()]` は、`$null` を引数として受け取ってよいことを明示します。

例:

```powershell
param(
    [AllowNull()][object]$ElapsedDays
)
```

`ElapsedDays` は差分日数です。ただし、日付を計算できないケースでは `$null` になります。

このように、業務上「値が存在しない」ことを正しく表すために使います。

## `$null`

`$null` は「値がない」ことを表す特別な値です。

例:

```powershell
if ($null -eq $scanCompleted) {
    return New-ScanTargetSyncCsvErrorEvaluation ...
}
```

このプロジェクトでは、日付変換に失敗した場合などに `$null` が使われます。

比較では、次の書き方がよく出ます。

```powershell
$null -eq $value
$value -eq $null
```

PowerShellでは、慣習的に `$null` を左側に置く書き方が安全とされます。配列との比較時に意図しない挙動を避けやすいためです。

## `[string]::IsNullOrWhiteSpace(...)`

これは.NETの文字列チェック機能です。

```powershell
[string]::IsNullOrWhiteSpace($text)
```

意味は、次のどれかなら `$true` です。

- `$null`
- 空文字 `""`
- スペースやタブだけの文字列

このプロジェクトでは、CSVの空欄判定や、引数が渡されたかどうかの判定で使われます。

例:

```powershell
if ([string]::IsNullOrWhiteSpace($JobRegistryPath)) {
    $JobRegistryPath = Get-FoundationDefaultJobRegistryPath -RootPath $RootPath
}
```

これは、ジョブ定義ファイルのパスが指定されていなければ、標準パスを使う処理です。

## `Test-Path`, `Resolve-Path`, `Join-Path`

ファイルパスを扱う標準cmdletです。

| cmdlet | 役割 |
|---|---|
| `Join-Path` | パスを安全につなぐ |
| `Test-Path` | ファイルやディレクトリが存在するか確認する |
| `Resolve-Path` | 相対パスや省略を実際の絶対パスに解決する |

例:

```powershell
$FoundationModulePath = Join-Path $ScriptDirectory "modules\Foundation\Foundation.psm1"

if (-not (Test-Path -LiteralPath $FoundationModulePath)) {
    throw "Foundationモジュールが見つかりません: $FoundationModulePath"
}
```

この処理は、Foundationモジュールの場所を作り、実際に存在するか確認しています。

## `Import-Module`

`Import-Module` は、PowerShellモジュールを読み込む命令です。

例:

```powershell
Import-Module -Name $FoundationModulePath -Force -DisableNameChecking
```

このプロジェクトでは、`.psm1` ファイルをモジュールとして読み込みます。

`run_job.ps1` は、まず `Foundation.psm1` を読みます。Foundationモジュールが読まれることで、`Invoke-FoundationEntrypoint` が使えるようになります。

## dot-source: `. $path`

PowerShellで、行頭に `.` を置いてスクリプトを読み込む書き方があります。

```powershell
. $path
```

これをdot-sourceと呼びます。

このプロジェクトの `*.psm1` では、internal配下の `.ps1` をdot-sourceしています。

例:

```powershell
foreach ($relativePath in @(
    'internal\Models.ps1',
    'internal\DomOperations.ps1',
    'internal\DomAdapter.ps1',
    'internal\Runner.ps1'
)) {
    $path = Join-Path $PSScriptRoot $relativePath
    . $path
}
```

dot-sourceすると、その `.ps1` 内の関数が同じモジュールスコープに読み込まれます。

つまり、`InstalledAppExport.psm1` が `internal\RowAction.ps1` をdot-sourceすると、`Invoke-InstalledAppExportCsvForRow` などの関数がInstalledAppExportモジュール内で使えるようになります。

## `Export-ModuleMember`

`Export-ModuleMember` は、モジュールの外から呼べる関数を指定します。

例:

```powershell
Export-ModuleMember -Function @(
    'Invoke-InstalledAppExportJob'
)
```

この場合、外部から直接呼べるのは `Invoke-InstalledAppExportJob` です。

`internal` 配下の関数は、同じモジュール内では使えますが、通常は外部公開されません。

この設計により、外からは「ジョブを実行する関数」だけが見え、内部の細かい関数は隠されます。

## `& $command`

`&` は、変数に入っているコマンドやscriptblockを実行する演算子です。

例:

```powershell
$command = Get-FoundationJobCommand -JobDefinition $context.JobDefinition -JobName $JobName
$jobResult = & $command -Context $context
```

`Get-FoundationJobCommand` は、`Invoke-InstalledAppExportJob` や `Invoke-LastMonthInstallExtractJob` などの関数情報を返します。

`& $command -Context $context` は、その取得した関数を実際に呼びます。

`JobName` が `InstalledAppExport` なら、実質的には次の呼び出しになります。

```powershell
Invoke-InstalledAppExportJob -Context $context
```

ただし、ソース上ではジョブ名に応じて関数が変わるため、`&` を使って動的に呼び出しています。

## scriptblock: `{ ... }`

PowerShellの `{ ... }` は、処理を値として扱うための構文です。

このプロジェクトでは、DependenciesやServicesで多用されます。

例:

```powershell
ClearDirectory = {
    param([string]$Directory, [string]$Purpose)
    & $clearDirectoryContentsCommand -Directory $Directory -Purpose $Purpose
}.GetNewClosure()
```

これは、`ClearDirectory` という名前のプロパティに「あとで実行できる処理」を入れています。

呼び出す側では、次のように実行します。

```powershell
$Context.Services.FileSystem.ClearDirectory.Invoke($settings.TempDirectory, "一時ダウンロード")
```

この仕組みにより、テストでは本物のファイル削除ではなく、ダミー処理へ差し替えられます。

## `.GetNewClosure()`

`.GetNewClosure()` は、scriptblockが作られた時点の変数を保持するための処理です。

例:

```powershell
$writeFoundationLogCommand = Get-Command -Name Write-FoundationLog

WriteInfo = {
    param([string]$Message)
    & $writeFoundationLogCommand -Logger $Logger -Level Info -Message $Message
}.GetNewClosure()
```

このscriptblockは、あとで実行されます。あとで実行しても、作成時点の `$writeFoundationLogCommand` や `$Logger` を参照できるようにするために `.GetNewClosure()` を使います。

このプロジェクトでは、依存関係を安全に束ねるための重要な構文です。

## `[pscustomobject]@{ ... }`

`[pscustomobject]@{ ... }` は、名前付きプロパティを持つオブジェクトを作ります。

例:

```powershell
[pscustomobject]@{
    IsTarget    = $true
    IsCsvError  = $false
    ElapsedDays = 9
    Reason      = "最終通信日時との差が 9 日"
}
```

作った後は、次のようにプロパティへアクセスできます。

```powershell
$evaluation.IsTarget
$evaluation.ElapsedDays
$evaluation.Reason
```

このプロジェクトでは、関数の戻り値をただの文字列や配列ではなく、意味のあるプロパティ名で返すために使います。

## `@(...)`

`@(...)` は、結果を配列として扱うための構文です。

例:

```powershell
return @($onRows)
```

PowerShellでは、要素が1件だけのときに配列ではなく単体として扱われることがあります。`@(...)` を使うと、0件でも1件でも複数件でも、配列として安定して扱えます。

このプロジェクトでは、結果行のリストやエラー行のリストを安定した形で返すために使います。

## `foreach`

`foreach` は、配列やリストの各要素を順番に処理します。

例:

```powershell
foreach ($row in $CsvRows) {
    ...
}
```

`ScanTargetSync/internal/Rules.ps1` では、CSVの各行を順に評価し、ON対象、OFF対象、CSVエラーに分類します。

## `continue`

`continue` は、現在のループ処理をそこで終えて、次の要素へ進みます。

例:

```powershell
if ($evaluation.IsCsvError) {
    $csvErrorRows += New-ScanTargetSyncCsvErrorRow ...
    continue
}
```

この例では、CSVエラーになった行は、ON/OFF分類へ進まず、次のCSV行に移ります。

## `try`, `catch`, `finally`

`try/catch/finally` は、エラー処理と後始末を扱う構文です。

```powershell
try {
    危険な処理
}
catch {
    エラー時の処理
}
finally {
    成功しても失敗しても必ず実行する処理
}
```

このプロジェクトで特に重要なのは `finally` です。

InstalledAppExportの1行処理では、CSVダウンロード中に失敗しても、詳細パネルを閉じる必要があります。

```powershell
try {
    ...CSV取得...
}
finally {
    Close-InstalledAppExportDetailPanelSafely -Context $Context
}
```

`finally` があるため、途中で失敗しても画面状態を次の行処理へ持ち越しにくくなります。

## `throw`

`throw` は、処理を失敗として止める命令です。

例:

```powershell
throw "設定ファイルが見つかりません: $ConfigPath"
```

このプロジェクトでは、前提が満たされない場合に `throw` します。

- 設定ファイルがない
- ジョブ定義ファイルがない
- ジョブモジュールがない
- ジョブ定義に書かれた関数が見つからない
- 画面上の端末名が期待と違う

`throw` したエラーは、上位の `catch` でログに残され、最終的に呼び出し元へ再送出されます。

## `| Out-Null`

`| Out-Null` は、戻り値を捨てるための書き方です。

例:

```powershell
Assert-InstalledAppExportDetailPanel -DataId $DataId -AssetName $AssetName | Out-Null
```

この例では、戻り値そのものは使っていません。重要なのは、関数が失敗せずに通ることです。

`Assert-*` 系の関数は、条件が満たされない場合にエラーを投げることがあります。戻り値を使わなくても、確認処理として意味があります。

## バッククォートによる行継続

PowerShellでは、行末のバッククォート `` ` `` を使って、1つの命令を複数行に分けられます。

例:

```powershell
Invoke-FoundationEntrypoint `
    -RootPath $ScriptDirectory `
    -ConfigPath $ConfigPath `
    -JobName $JobName
```

これは1つの関数呼び出しです。見やすくするために引数ごとに改行しています。

読むときは、バッククォートで終わる行は次の行とつながっていると考えてください。

## `$ErrorActionPreference = "Stop"`

この設定は、PowerShellのエラーをできるだけ例外として扱うためのものです。

```powershell
$ErrorActionPreference = "Stop"
```

PowerShellには、失敗しても処理が続く種類のエラーがあります。この設定により、多くのエラーを `try/catch` で捕まえやすくなります。

このプロジェクトは自動化処理なので、失敗に気づかず続行すると危険です。たとえば、CSVダウンロードに失敗したまま次へ進むと、誤った結果ファイルを作る可能性があります。

そのため、失敗は早めに止める方針です。

## 読むときの基本手順

PowerShellファイルを読むときは、次の順番で見ます。

```text
1. Exportされている関数、または外部から呼ばれる関数を探す
2. その関数の param を見る
3. 関数内で呼ばれている関数を上から順に追う
4. return される [pscustomobject] の形を見る
5. try/catch/finally があれば、失敗時と後始末を見る
6. & や scriptblock があれば、実行される処理がどこから来ているかを見る
```

この順番で読むと、細部に入る前に処理の骨格を把握できます。
