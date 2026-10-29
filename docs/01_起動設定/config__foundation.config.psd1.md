# main/config/foundation.config.psd1

## 1. このファイルを一言でいうと

このファイルは、ジョブ実行時に使う設定値を定義するファイルです。

`foundation.jobs.psd1` が「どの実装を呼ぶか」を定義するのに対して、`foundation.config.psd1` は「その実装をどの設定で動かすか」を定義します。

---

## このファイルを変更する典型ケース

- 設定キー、既定値、環境ごとに編集する項目が変わった場合
- Jobごとの設定構造や連携Job設定が変わった場合
- sampleから実設定を作る手順や注意点が変わった場合


## 2. このファイルが担当する範囲

担当すること:

```text
- 共通設定を定義する
- ジョブごとのフォルダを定義する
- ジョブごとのファイル名を定義する
- ジョブごとのタイムアウト値を定義する
- ジョブごとの閾値を定義する
- ジョブごとの必要ヘッダーを定義する
```

担当しないこと:

```text
- ジョブのModulePathを定義する
- ジョブのCommandNameを定義する
- DOM JavaScriptのパスを定義する
- Feature moduleの読み込み順を定義する
- 業務ロジックそのものを実装する
```

---

## 3. ファイル全体の構造

最上位には `Common` と `Jobs` があります。

```text
@{
  Common = @{
    DebuggerUrl = ...
    Logging = @{
      ...
    }
    Cdp = @{
      ...
    }
  }

  Jobs = @{
    InstalledAppExport = @{
      ...
    }
    ScanTargetSync = @{
      ...
    }
    DeviceListExport = @{
      ...
    }
    LastMonthInstallExtract = @{
      ...
    }
    CompositeJob = @{
      ...
    }
  }
}
```

`Common` は全ジョブ共通の設定です。  
`Jobs` はジョブごとの設定です。

---

## 4. `Common` の意味

## `DebuggerUrl`

```text
http://localhost:9222/json
```

Chrome DevTools Protocol へ接続するためのURLです。  
DOMを操作するジョブでは、ブラウザがこのdebugger endpointを公開している必要があります。

`LastMonthInstallExtract` のようなDOMを使わないジョブでは、通常この値は使いません。

## `Logging`

```text
Level     = Info
Console   = true
File      = false
Directory = logs
```

ログ出力の設定です。  
`New-FoundationRunContext` で `New-FoundationLogger` に渡され、`$context.Logger` が作られます。

## `Cdp`

```text
ConnectTimeoutSeconds = 15
CommandTimeoutSeconds = 30
```

CDP接続やコマンド応答待ちのタイムアウトです。  
DOM操作ジョブでブラウザ接続を開くときに使われます。

---

## 5. `Jobs.InstalledAppExport` の意味

```text
TempDirectory                = monthly\tmp
DownloadDirectory            = monthly\Downloads
DownloadFilePrefix           = app_list_
FailureCsvFileName           = installed_app_export_error_list.csv
DownloadTimeoutSeconds       = 120
DownloadStableSeconds        = 2
DetailPanelCloseWaitSeconds  = 3
MaxScanLoops                 = 500
SameScrollLimit              = 2
```

InstalledAppExportジョブは、画面の端末一覧から端末ごとのLastMonthInstallExtract CSVを取得します。

| キー | 意味 |
|---|---|
| `TempDirectory` | ダウンロード前の一時作業用フォルダ |
| `DownloadDirectory` | 成果物CSVを置くフォルダ |
| `DownloadFilePrefix` | リネーム後のCSVファイル名の接頭辞 |
| `FailureCsvFileName` | 失敗行一覧CSVのファイル名 |
| `DownloadTimeoutSeconds` | CSVダウンロード完了を待つ最大秒数 |
| `DownloadStableSeconds` | ダウンロード済みファイルが安定したとみなす秒数 |
| `DetailPanelCloseWaitSeconds` | 詳細パネルを閉じた後の待機秒数 |
| `MaxScanLoops` | スクロール一覧を走査する最大回数 |
| `SameScrollLimit` | 同じ位置に留まったとみなす回数上限 |

`DownloadTimeoutSeconds` を短くしすぎると、正常なダウンロードでも失敗扱いになります。  
`MaxScanLoops` を小さくしすぎると、一覧の途中までしか走査できません。

---

## 6. `Jobs.ScanTargetSync` の意味

```text
InputCsvPath       = %USERPROFILE%\Downloads\sensor_devices.csv
OutputDirectory    = weekly\Downloads
CsvErrorFileName   = scan_target_sync_error_list.csv
FailureCsvFileName = scan_target_sync_failure_list.csv
DaysThreshold      = 7
MaxScanLoops       = 500
SameScrollLimit    = 5
```

ScanTargetSyncジョブは、CSVと画面上の端末一覧を突き合わせ、対象端末のチェックボックスを操作します。

| キー | 意味 |
|---|---|
| `InputCsvPath` | 入力CSVのパス |
| `OutputDirectory` | エラーCSVや失敗CSVを出力するフォルダ |
| `CsvErrorFileName` | CSV内容エラーの出力ファイル名 |
| `FailureCsvFileName` | 画面操作失敗などの出力ファイル名 |
| `DaysThreshold` | 対象判定に使う日数閾値 |
| `MaxScanLoops` | UI一覧を走査する最大回数 |
| `SameScrollLimit` | 同じスクロール位置が続いた時の停止判定 |

`DaysThreshold = 7` の場合、手動スキャン完了日と最終通信日時の差分が7日以上なら対象になります。  
この値は業務判定結果に直結します。

`%USERPROFILE%` は環境変数です。  
`Config.ps1` の `Expand-FoundationPath` によって、実行ユーザーのホームディレクトリに展開されます。

---

## 7. `Jobs.DeviceListExport` の意味

```text
TempDirectory                 = weekly\tmp\device_list_export
DownloadDirectory             = weekly\Downloads
DownloadedCsvFileNamePattern  = ^.+\.csv$
OutputFileNameTemplate        = sensor_devices_{0}.csv
DownloadTimeoutSeconds        = 120
DownloadStableSeconds         = 2
NavigationTimeoutSeconds      = 20
TaskMenuTimeoutSeconds        = 10
```

DeviceListExportジョブは、画面からデバイス一覧CSVをエクスポートします。

| キー | 意味 |
|---|---|
| `TempDirectory` | ダウンロード一時フォルダ |
| `DownloadDirectory` | エクスポート後CSVを置くフォルダ |
| `DownloadedCsvFileNamePattern` | ダウンロードされたCSVを探す正規表現 |
| `OutputFileNameTemplate` | 最終出力ファイル名のテンプレート |
| `DownloadTimeoutSeconds` | CSVダウンロード待ち秒数 |
| `DownloadStableSeconds` | ファイル安定確認秒数 |
| `NavigationTimeoutSeconds` | 画面遷移待ち秒数 |
| `TaskMenuTimeoutSeconds` | 操作メニュー表示待ち秒数 |

`OutputFileNameTemplate` の `{0}` には、通常タイムスタンプなどが入ります。  
同名ファイルの上書きや混同を避けるための設定です。

---

## 8. `Jobs.LastMonthInstallExtract` の意味

```text
TargetDirectory     = monthly\Downloads
OutputCsvFileName   = pc_installation.csv
FailureCsvFileName  = pc_installation_failure_list.csv
FileNamePattern     = ^.+_(PCXX-\d{2}-\d{3})\.csv$
RequiredHeaders     = アプリ名, バージョン, 導入日
```

LastMonthInstallExtractジョブは、InstalledAppExportジョブなどで取得済みのLastMonthInstallExtract CSVを読み、インストール情報を抽出します。

| キー | 意味 |
|---|---|
| `TargetDirectory` | 解析対象CSVが置かれているフォルダ |
| `OutputCsvFileName` | 正常抽出結果のCSV名 |
| `FailureCsvFileName` | 解析失敗一覧CSV名 |
| `FileNamePattern` | CSVファイル名から端末名を取り出す正規表現 |
| `RequiredHeaders` | CSVに必須の列名 |

`FileNamePattern` の `PCXX-\d{2}-\d{3}` は、端末名を取り出すための捕捉部分です。  
ファイル名ルールを変更すると、LastMonthInstallExtractジョブが端末名を取得できなくなる可能性があります。

`RequiredHeaders` を変更すると、CSV列不足の判定結果が変わります。

---

## 9. Composite job の設定

## `WeeklyScanTargetSync`

現在は空のhashtableです。

```text
WeeklyScanTargetSync = @{}
```

設定が空でも、`Jobs` にキーとして存在する必要があります。  
`New-FoundationRunContext` は `Config.Jobs[JobName]` を取得するため、JobNameに対応する設定がないとエラーになります。

## `MonthlyInstallReport`

```text
RunRootDirectory = monthly\runs
```

InstalledAppExport → LastMonthInstallExtract の連携ジョブで、1回の実行ごとに専用ディレクトリを作るための起点です。

これにより、過去のInstalledAppExport CSVと今回のInstalledAppExport CSVが混ざることを防ぎます。

---

## 10. パス解決のルール

`Config.ps1` は、キー名が `*Path` または `*Directory` に一致する値をパスとして扱います。

例:

```text
InputCsvPath
OutputDirectory
TempDirectory
DownloadDirectory
TargetDirectory
RunRootDirectory
```

相対パスは、プロジェクトルート基準の絶対パスに変換されます。

```text
weekly\Downloads
  ↓
<project-root>\weekly\Downloads
```

環境変数も展開されます。

```text
%USERPROFILE%\Downloads\...
  ↓
C:\Users\<user>\Downloads\...
```

このため、Feature module側では相対パスか絶対パスかを意識せず、解決済みの `$context.JobSettings.OutputDirectory` などを使えます。

---

## 11. PowerShell文法上のポイント

## `$true` / `$false`

PowerShellの真偽値です。

```powershell
Console = $true
File = $false
```

文字列の `'true'` ではありません。  
booleanとして扱われます。

## 正規表現文字列

次のような値は正規表現です。

```text
^.+\.csv$
^.+_(PCXX-\d{2}-\d{3})\.csv$
```

PowerShell文字列内では、バックスラッシュ自体は通常の文字です。  
ここでは正規表現側の意味として `\.` が「ドット文字そのもの」を表します。

## 配列

```powershell
RequiredHeaders = @(
    'アプリ名'
    'バージョン'
    '導入日'
)
```

複数の必須ヘッダーを順序付き配列として定義しています。

---

## 12. このファイルの設計境界を守るテスト

`Foundation.Config.Tests.ps1` では、次の契約が確認されています。

```text
- Common と Jobs が必須である
- Common と Jobs は hashtable である
- 任意のジョブ名を受け入れる。ジョブ名は固定リストではない
- 指定JobNameの設定を取得できる
- 指定JobNameの設定がなければエラー
- 指定JobNameの設定がhashtableでなければエラー
```

重要なのは、「有効なジョブ名を `Config.ps1` 側で固定していない」ことです。  
ジョブの存在や実装定義は `foundation.jobs.psd1` 側で扱います。

---

## 13. 変更時の注意

```text
- Path / Directory で終わるキーは自動的にパス解決される
- パスではない値に Path / Directory という名前を付けると、意図せず変換対象になる
- DaysThreshold はScanTargetSyncの業務判定を直接変える
- RequiredHeaders はLastMonthInstallExtractのCSV検証を直接変える
- FileNamePattern はLastMonthInstallExtractの端末名抽出を直接変える
- Composite jobの設定を削除すると、Context作成時にJobSettings取得で失敗する
```

特に、設定名の変更はFeature module側の参照名変更も必要です。  
例えば `DownloadDirectory` を `OutputDirectory` に変えるだけでは動きません。コード側の `$context.JobSettings.DownloadDirectory` も変える必要があります。

---

## 14. 本ドキュメント内容の要点

```text
- foundation.config.psd1 は実行時設定ファイルである
- Common は全ジョブ共通設定である
- Jobs はジョブごとの設定である
- ModulePath / CommandName はここには書かない
- *Path / *Directory のキーは絶対パスに解決される
- JobSettings は Config.Jobs[JobName] から作られる
- 設定値の変更は業務結果や待機挙動を変える
```

## sample設定との関係

初期導入時は `main/config/foundation.config.sample.psd1` をコピーして `foundation.config.psd1` を作ります。
sample側の読み方は `docs/01_起動設定/config__foundation.config.sample.psd1.md` を参照してください。
