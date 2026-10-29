# main/modules/Foundation/internal/Logging.ps1

## 1. このファイルを一言でいうと

このファイルは、Foundation全体で使うログ出力機能を定義します。

コンソールに出すログ、ファイルに残すログ、セクション区切り、オブジェクトのJSON表示を扱います。

## このファイルを変更する典型ケース

- Foundation共通サービスのcallback、戻り値、例外分類が変わった場合
- Feature moduleから使う共通境界の意味が変わった場合
- 複数Jobに影響する安全確認や診断情報が変わった場合


## 2. このファイルが担当する範囲

このファイルが担当するのは、次です。

```text
- Loggerオブジェクトを作る
- ログの出力先を決める
- ログ行に日時・レベル・RunIdを付ける
- Warning / Error / Info の出し分けをする
- オブジェクトをJSON化してログに出す
- ログセクションの区切りを出す
```

`RunId` は、1回の実行を識別するためのIDです。  
同じジョブを複数回実行したとき、ログファイルやログ行を区別するために使われます。

## 3. このファイルが担当しない範囲

このファイルは、次のことは担当しません。

```text
- どのジョブを実行するか決める
- どの業務処理が成功・失敗したか判定する
- CSVファイルを作る
- ブラウザやDOMを操作する
- ログ内容の業務的な文章を組み立てる
```

例えば、`InstalledAppExport` ジョブが「対象端末が見つからない」とログに出すかどうかは、`InstalledAppExport` 側の責務です。  
`Logging.ps1` は、その文字列をどの形式でどこに出すかだけを担当します。

## 4. 実行時の位置づけ

このファイルの関数は、主に `RunContext.ps1` から使われます。

```text
Initialize-FoundationRuntime
  ↓
New-FoundationRunContext
  ↓
New-FoundationLogger
  ↓
Context.Logger に格納
  ↓
New-FoundationServices
  ↓
Context.Services.Logger.WriteInfo / WriteWarning / WriteObject / WriteSection として各ジョブへ渡る
```

Feature module は、多くの場合 `Write-FoundationLog` を直接呼びません。  
`Context.Services.Logger` または各Feature moduleの `Dependencies.ps1` を経由して、`WriteInfo` や `WriteWarning` というscriptblockとして使います。

## 5. このファイル内の関数呼び出しツリー

```text
New-FoundationLogger
  ├─ Expand-FoundationPath
  ├─ Initialize-FoundationOutputDirectory
  ├─ Join-Path
  └─ $script:FoundationLogger に保存

Write-FoundationLog
  ├─ Get-Date
  ├─ Write-Host または Write-Warning
  ├─ Add-Content
  └─ ConvertTo-Json  ※ Data が指定された場合

Write-FoundationSection
  └─ Write-FoundationLog を複数回呼ぶ

Write-FoundationObject
  ├─ Write-FoundationLog  ※ Message がある場合
  ├─ ConvertTo-Json
  └─ Write-FoundationLog

Close-FoundationLogger
  └─ 現在は何もしない
```

## 6. Loggerオブジェクトの形

`New-FoundationLogger` は、次のような `[pscustomobject]` を返します。

```text
Logger
  Level    : ログレベル文字列。例: Info / Debug
  Console  : コンソール出力するか
  File     : ファイル出力するか
  FilePath : ファイル出力先。File=falseならnull
  RunId    : 実行ID
```

重要なのは、このオブジェクト自体にはメソッドがないことです。  
単なる設定の入れ物です。

実際の出力処理は `Write-FoundationLog` が担当します。

## 7. 関数ごとの説明

## New-FoundationLogger

### 何をするか

ログ出力の設定を読み、Loggerオブジェクトを作ります。

入力の `$Config` は、通常 `foundation.config.psd1` の `Common.Logging` から来ます。

概念的には次の設定です。

```text
Logging
  Level     : Info など
  Console   : コンソールに出すか
  File      : ファイルに出すか
  Directory : ログファイルを置くディレクトリ
```

### なぜ必要か

各関数が毎回 `Console` や `FilePath` を判断すると、ログ設定の知識がプロジェクト全体に散らばります。

`New-FoundationLogger` で最初にLoggerを作っておくことで、以降は同じ設定を使い回せます。

### 入力

```text
Config : ログ設定のhashtable。省略時は空hashtable
RunId  : 実行ID。ログファイル名やログ行に入る
```

### 出力

`Logger` オブジェクトを返します。  
また、`$script:FoundationLogger` にも保存します。

### 副作用

```text
- File=true の場合、ログディレクトリを作成する
- $script:FoundationLogger を更新する
```

`$script:FoundationLogger` は、Foundationモジュールのscriptスコープ変数です。  
`Write-FoundationLog` の `Logger` 引数を省略した場合、この変数が使われます。

### 失敗条件

```text
- File=true なのに Directory が空
- Directory が安全な出力先として作成・解決できない
```

ログディレクトリの安全確認は、`Initialize-FoundationOutputDirectory` を経由します。  
これは `FileSystem.ps1` 側の関数です。

### PowerShell文法上のポイント

```text
$Config.ContainsKey('Level')
```

これは、hashtableに指定キーが存在するかを確認しています。  
存在すれば設定値を使い、なければデフォルト値を使います。

```text
$script:FoundationLogger = $logger
```

`$script:` は、同じモジュールスクリプトスコープに値を保存する指定です。  
このため、後続の `Write-FoundationLog` で Logger 引数を省略しても、直近で作成されたLoggerを使えます。

### 変更時の注意

`File=true` のときのディレクトリチェックを緩めてはいけません。  
ログ出力は一見安全そうに見えますが、任意パスにファイルを書ける処理です。  
`Initialize-FoundationOutputDirectory` 経由にしている理由は、出力先の安全確認を共通化するためです。

## Write-FoundationLog

### 何をするか

1行のログを出力します。

出力先はLoggerの設定に従います。

```text
Logger.Console = true ならコンソール出力
Logger.File    = true ならファイル追記
```

### なぜ必要か

ジョブごとの処理は、ログ出力方法の詳細を知る必要がありません。

`Write-FoundationLog` に集約することで、ログの形式を統一できます。

### 入力

```text
Logger  : Loggerオブジェクト。省略時は $script:FoundationLogger
Level   : Debug / Info / Warning / Error
Message : 出力する文字列
Data    : 追加でJSON出力する任意オブジェクト
```

### 出力

戻り値は実質ありません。  
コンソールまたはファイルへ出力する副作用が主です。

### 副作用

```text
- コンソールに文字列を出す
- ログファイルに文字列を追記する
- Data がある場合、DataをJSON化してログファイルに追記する
```

### 失敗条件

```text
- File=true だが FilePath が不正
- ログファイルへ書き込めない
- Data が深すぎる、またはJSON化できない
```

### ログ行の形

通常のログ行は次の形です。

```text
[yyyy-MM-dd HH:mm:ss] [INFO] [RunId] メッセージ
```

`RunId` が空の場合は、RunId部分は出ません。

### PowerShell文法上のポイント

```text
[ValidateSet('Debug','Info','Warning','Error')]
```

この属性により、`Level` には指定された4値しか渡せません。  
タイプミスしたログレベルを早期に止めるための仕組みです。

```text
Microsoft.PowerShell.Utility\Write-Host
```

完全修飾名で `Write-Host` を呼んでいます。  
同名関数やエイリアスの影響を避けるためです。

### 変更時の注意

`Warning` のときだけ `Write-Warning` を使っています。  
これにより、警告として扱われる表示になります。

ただし、`Error` は `Write-Error` ではなく `Write-Host` です。  
ここで `Write-Error` に変えると、ログ出力そのものがエラー制御に影響する可能性があります。

ログ出力は診断のための副作用であり、原則として業務処理の成否を変えるべきではありません。

## Write-FoundationSection

### 何をするか

ログに大きな区切りを出します。

例として、ジョブ開始、フェーズ開始、出力フェーズ開始などで使います。

### 入力

```text
Logger : Loggerオブジェクト
Title  : セクション名
```

### 出力・副作用

`Write-FoundationLog` を複数回呼び、区切り線とタイトルを出します。

### 変更時の注意

この関数に業務判断を入れてはいけません。  
この関数は「見やすいログの整形」だけを担当します。

## Write-FoundationObject

### 何をするか

オブジェクトをJSON文字列に変換してログに出します。

### なぜ必要か

PowerShellのオブジェクトは、そのまま文字列にすると中身が読みにくくなる場合があります。  
`ConvertTo-Json` を使うことで、プロパティ構造をログ上で追いやすくしています。

### 入力

```text
Logger  : Loggerオブジェクト
Message : オブジェクトの前に出す任意メッセージ
Data    : 出力対象オブジェクト
Depth   : JSON化する深さ
```

### 変更時の注意

`Depth` を小さくしすぎると、ネストした結果オブジェクトが途中で切れます。  
一方で大きくしすぎるとログが長くなります。

このプロジェクトでは、結果オブジェクトや設定オブジェクトを診断するため、ある程度深く出せるようにしています。

## Close-FoundationLogger

### 何をするか

現在は何もしません。

### なぜ存在するか

今の実装は、ログを書き込むたびに `Add-Content` でファイルへ追記しています。  
ファイルハンドルを長時間保持していないため、明示的なcloseは不要です。

ただし、将来ログ実装を変更して、ストリームを開きっぱなしにする設計にした場合、この関数にクローズ処理を追加できます。

## 8. このファイルを変更するときの判断基準

```text
- ログ形式を変えるだけなら、このファイル内で閉じる可能性が高い
- Loggerオブジェクトのプロパティ名を変えると、RunContextやテストが壊れる
- Write-FoundationLog をエラー発生関数に変えると、ログ出力が業務処理に影響する
- ファイル出力時の安全確認を削ると、任意パス書き込みリスクが上がる
```

## 9. このファイルを守っているテスト

```text
Foundation.Logging.Tests.ps1
  - ConfigからLoggerが作られること
  - Console / File / Level / RunId が期待通り保持されること

Foundation.PublicApi.Tests.ps1
  - Write-FoundationLog / Write-FoundationSection / Write-FoundationObject が公開APIとして存在すること
```

## 10. 本ドキュメント内容の要点

```text
- Logging.ps1 はログ出力形式と出力先を担当する
- 業務的に何をログに出すかは各ジョブ側の責務
- Loggerは設定の入れ物で、出力処理は Write-FoundationLog が行う
- RunId は1回の実行を追跡するための識別子
- このファイルの変更は全ジョブの診断性に影響する
```
