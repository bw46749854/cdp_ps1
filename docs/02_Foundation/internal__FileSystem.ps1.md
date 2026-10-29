# main/modules/Foundation/internal/FileSystem.ps1

## 1. このファイルを一言でいうと

このファイルは、Foundation全体で使うファイルシステム操作を安全に行うための共通基盤です。

特に重要なのは、削除処理です。  
CSV出力や一時ダウンロードフォルダの掃除ではファイル削除が発生します。  
このファイルは、誤って危険な場所を削除しないための防波堤です。

## このファイルを変更する典型ケース

- Foundation共通サービスのcallback、戻り値、例外分類が変わった場合
- Feature moduleから使う共通境界の意味が変わった場合
- 複数Jobに影響する安全確認や診断情報が変わった場合


## 2. このファイルが担当する範囲

```text
- 出力ディレクトリを安全に作る
- 作業ディレクトリを安全に作る
- 指定パスが許可ディレクトリ配下か判定する
- 指定ファイルを安全に削除する
- ディレクトリ配下の中身を安全に削除する
```

## 3. このファイルが担当しない範囲

```text
- CSVの中身を作る
- ダウンロード完了を待つ
- どのファイル名にするか決める
- どのジョブでどのディレクトリを使うか決める
- ブラウザからファイルをダウンロードする
```

例えば、`InstalledAppExport` ジョブのCSVファイル名に端末名を入れるかどうかは、`InstalledAppExport` 側の責務です。  
`FileSystem.ps1` は、そのファイルを消してよい場所にあるか、ディレクトリを作ってよいかを確認します。

## 4. 実行時の位置づけ

`RunContext.ps1` は、このファイルの関数を `Context.Services.FileSystem` に包んで各ジョブへ渡します。

```text
New-FoundationRunContext
  ↓
New-FoundationServices
  ↓
New-FoundationFileSystemService
  ↓
Context.Services.FileSystem
  ├─ InitializeOutputDirectory
  ├─ ClearDirectory
  ├─ AssertSafeDirectory
  ├─ TestPathUnderDirectory
  └─ RemoveFileIfExists
```

Feature module からの利用例は次です。

```text
DeviceListExport.Runner
  - 一時ダウンロードディレクトリを作る
  - 最終保存ディレクトリを作る
  - 一時ダウンロードディレクトリを空にする

InstalledAppExport.Runner / InstalledAppExport.RowAction
  - 一時ダウンロードディレクトリを作る
  - CSV取得前に一時ディレクトリを空にする

ScanTargetSync.Output / LastMonthInstallExtract.Output
  - 出力先ディレクトリを確認する
  - 既存の出力CSVを安全に削除する
```

## 5. このファイル内の関数呼び出しツリー

```text
Assert-FoundationSafeDirectory
  ├─ IsNullOrWhiteSpace
  ├─ System.IO.Path.GetFullPath
  ├─ System.IO.Path.GetPathRoot
  ├─ Environment.GetFolderPath(UserProfile)
  ├─ Test-Path
  ├─ New-Item
  └─ Resolve-Path

Initialize-FoundationOutputDirectory
  ├─ Assert-FoundationSafeDirectory
  └─ New-Item

Test-PathUnderDirectory
  ├─ Assert-FoundationSafeDirectory
  ├─ System.IO.Path.GetFullPath
  └─ StartsWith

Remove-FileIfExistsSafely
  ├─ Assert-FoundationSafeDirectory
  ├─ Test-PathUnderDirectory
  ├─ Test-Path
  ├─ Get-Item
  └─ Remove-Item

Clear-DirectoryContentsSafely
  ├─ Assert-FoundationSafeDirectory
  ├─ Test-Path
  ├─ New-Item
  ├─ Get-ChildItem
  ├─ Test-PathUnderDirectory
  └─ Remove-Item
```

## 6. 安全確認の考え方

このファイルの中心は、`Assert-FoundationSafeDirectory` です。

この関数は、次のような危険な指定を止めます。

| 条件 | なぜ危険か |
|---|---|
| ディレクトリ文字列が空 | 意図しない現在ディレクトリ操作につながる |
| 解決後パスが空 | パスとして扱えない |
| ドライブルート | `C:\` などを削除対象にすると壊滅的 |
| ユーザープロファイル直下 | `C:\Users\User` 直下の重要データに近すぎる |
| ユーザープロファイル直下の子 | `Downloads` や `Desktop` などを誤って掃除する危険がある |

このプロジェクトでは、一時ダウンロードフォルダや出力フォルダを頻繁に使います。  
安全確認を各ジョブに分散させると、どこかでチェック漏れが起きます。  
そのため、共通関数に集約しています。

## 7. 関数ごとの説明

## Assert-FoundationSafeDirectory

### 何をするか

指定されたディレクトリが、Foundationの出力・作業用として安全に使えるか確認します。  
存在しなければ作成し、最終的に解決済みの実パスを返します。

### 入力

```text
Directory : 確認対象のディレクトリ
Purpose   : エラーメッセージ用の用途名。例: 出力 / 作業 / ログ
```

### 出力

解決済みディレクトリパスを文字列で返します。

### 副作用

```text
- ディレクトリが存在しない場合、作成する
```

### 失敗条件

```text
- Directory が空
- パス解決結果が空
- ドライブルートを指定している
- ユーザープロファイル直下を指定している
- ユーザープロファイル直下の子ディレクトリを指定している
- ディレクトリを作成できない
```

### PowerShell / .NET 文法上のポイント

```text
[System.IO.Path]::GetFullPath($Directory)
```

PowerShellではなく .NET の静的メソッドを呼んでいます。  
相対パスや `..` を含むパスを、正規化されたフルパスにするためです。

```text
TrimEnd([char[]]@(...))
```

末尾の `\` や `/` を取り除いて比較しやすくしています。  
`C:\Users\User` と `C:\Users\User\` を同じものとして扱うためです。

```text
Equals(..., [System.StringComparison]::OrdinalIgnoreCase)
```

Windowsのパス比較では、大文字・小文字を区別しないのが自然です。  
そのため、大小文字を無視した比較をしています。

### 変更時の注意

この関数の条件を緩めると、削除系処理の安全性が全体的に下がります。  
`Clear-DirectoryContentsSafely` や `Remove-FileIfExistsSafely` は、この関数の判断を前提にしています。

## Initialize-FoundationOutputDirectory

### 何をするか

出力用ディレクトリを安全に初期化します。

内部で `Assert-FoundationSafeDirectory` を呼び、その後 `New-Item -ItemType Directory -Force` でディレクトリの存在を保証します。

### 入力

```text
Directory : 出力先ディレクトリ
Purpose   : 用途名
```

### 出力

解決済みディレクトリパスを返します。

### 副作用

```text
- 出力先ディレクトリを作成する可能性がある
```

### 変更時の注意

この関数は「ディレクトリを空にする」関数ではありません。  
中身の削除は `Clear-DirectoryContentsSafely` が担当します。

この役割を混ぜると、単に出力先を確認しただけで既存ファイルが消える危険があります。

## Test-PathUnderDirectory

### 何をするか

指定された `Path` が、指定された `Directory` の配下にあるかを判定します。

### 入力

```text
Path      : 確認対象のパス
Directory : 許可する親ディレクトリ
```

### 出力

```text
true  : Path は Directory 配下
false : Path は Directory 配下ではない
```

### なぜ必要か

削除処理の前に、削除対象が許可された場所にあることを確認するためです。

### 重要な仕様

この関数は、単純な文字列比較ではなく、両方をフルパス化してから比較します。  
これにより、次のような指定をある程度正規化できます。

```text
C:\work\output\..\outside.txt
```

### 変更時の注意

`StartsWith` の比較条件を安易に変更してはいけません。  
パス境界を意識せずに比較すると、例えば次のような誤判定が起きる可能性があります。

```text
許可ディレクトリ: C:\work\out
対象パス        : C:\work\output2\file.csv
```

`C:\work\output2` は `C:\work\out` で始まるように見えますが、配下ではありません。  
この実装では、許可ディレクトリの後ろにディレクトリ区切り文字を付けて比較しています。

## Remove-FileIfExistsSafely

### 何をするか

指定ファイルが存在する場合だけ、安全確認後に削除します。

### 入力

```text
Path             : 削除対象ファイル
AllowedDirectory : 削除を許可する親ディレクトリ
```

### 出力

```text
true  : ファイルが存在し、削除した
false : ファイルが存在しなかった
```

### 副作用

```text
- 条件を満たすファイルを削除する
```

### 失敗条件

```text
- 削除対象が許可ディレクトリ配下ではない
- 削除対象がファイルではなくディレクトリ
- ファイル削除に失敗した
```

### なぜ必要か

出力CSVを再生成するとき、同名ファイルが既にある場合があります。  
上書き前に削除する処理は複数ジョブで必要です。

ただし、削除処理は危険です。  
そのため、各ジョブで `Remove-Item` を直接呼ばず、この関数に集約しています。

### 変更時の注意

`PSIsContainer` のチェックを削除してはいけません。  
これを削ると、ファイルを消すつもりの関数がディレクトリを消せるようになります。

## Clear-DirectoryContentsSafely

### 何をするか

指定ディレクトリの中身を削除します。  
ディレクトリ自体は削除しません。

### 入力

```text
Directory : 中身を削除するディレクトリ
Purpose   : 用途名
```

### 出力

明示的な戻り値はありません。

### 副作用

```text
- 指定ディレクトリ配下のファイル・サブディレクトリを削除する
- ディレクトリが存在しない場合は作成する
```

### 失敗条件

```text
- Directory が安全でない
- 配下項目がDirectory配下として判定できない
- 削除に失敗した
```

### なぜ必要か

ダウンロード処理では、一時フォルダに古いCSVが残っていると、今回ダウンロードしたCSVとの区別が難しくなります。

そのため、`DeviceListExport` や `InstalledAppExport` では、CSVダウンロード前に一時フォルダを空にします。

### 変更時の注意

この関数は強い副作用を持ちます。  
`Assert-FoundationSafeDirectory` と `Test-PathUnderDirectory` のチェックを外してはいけません。

また、この関数を「出力ディレクトリ初期化」の目的で気軽に呼ぶと、既存の成果物を消す可能性があります。  
作るだけなら `Initialize-FoundationOutputDirectory` を使うべきです。

## 8. このファイルを変更するときの判断基準

```text
- 削除系関数の安全条件を緩める変更は高リスク
- Directory作成だけの関数と、中身削除の関数を混ぜてはいけない
- パス比較は文字列比較だけで判断しない
- Feature module側に Remove-Item を直接書き始めたら設計境界が崩れている
```

## 9. このファイルを守っているテスト

```text
Foundation.FileSystem.Tests.ps1
  - 許可ディレクトリ配下のパスをtrueと判定する
  - 許可ディレクトリ外のパスをfalseと判定する
  - 許可ディレクトリ配下の既存ファイルだけ削除する
  - 許可ディレクトリ外のファイル削除を拒否する

Foundation.PublicApi.Tests.ps1
  - Initialize-FoundationOutputDirectory
  - Clear-DirectoryContentsSafely
  - Assert-FoundationSafeDirectory
  - Test-PathUnderDirectory
  - Remove-FileIfExistsSafely
  が公開APIとして存在すること
```

## 10. 本ドキュメント内容の要点

```text
- FileSystem.ps1 はファイル操作そのものより、安全条件を集中管理するためのファイル
- 削除処理は必ず許可ディレクトリ配下か確認する
- ディレクトリを作る処理と中身を消す処理は別責務
- このファイルの変更は複数ジョブの出力・削除安全性に影響する
```
