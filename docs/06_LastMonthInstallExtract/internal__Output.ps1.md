# main/modules/LastMonthInstallExtract/internal/Output.ps1

## 1. このファイルを一言でいうと

`LastMonthInstallExtract` の処理結果をCSVファイルとして出力するファイルです。出力前に、出力先が許可ディレクトリ配下かを確認します。

## このファイルを変更する典型ケース

- 出力CSVの列、ファイル名、文字コード、書き出し単位が変わった場合
- 成功行・失敗行・summaryの形が変わった場合
- 出力前の安全確認や既存ファイル扱いが変わった場合


## 2. このファイルが担当する範囲

- 出力パスの安全確認。
- 成功行CSVの出力。
- 失敗行CSVの出力。
- 失敗行が0件の場合、古い失敗CSVを削除する。

## 3. このファイルが担当しない範囲

- 入力CSVの読み取り。
- 成功行や失敗行の判定。
- 前月範囲の計算。

## 4. 関数呼び出しツリー

```text
Export-LastMonthInstallExtractInstallationCsv
  ├─ Assert-LastMonthInstallExtractOutputPathAllowed
  │   ├─ FileSystemService.AssertSafeDirectory
  │   └─ FileSystemService.TestPathUnderDirectory
  └─ Export-Csv / Set-Content

Export-LastMonthInstallExtractFailureCsv
  ├─ Assert-LastMonthInstallExtractOutputPathAllowed
  ├─ if FailureRows.Count = 0
  │   └─ FileSystemService.RemoveFileIfExists
  └─ Export-Csv
```

## 5. 関数ごとの説明

### Assert-LastMonthInstallExtractOutputPathAllowed

出力ファイルの親ディレクトリを取り出し、そのディレクトリが安全か確認します。

さらに、出力ファイルパスがその安全ディレクトリ配下にあるかを `TestPathUnderDirectory` で確認します。

これは、設定ミスや相対パスの扱いで、意図しない場所へCSVを書き込むことを防ぐためです。

### Export-LastMonthInstallExtractInstallationCsv

成功行をCSVへ出力します。

出力列は固定です。

```text
端末名
アプリ名
バージョン
導入日
```

成功行が0件でも、ヘッダーだけのCSVを作成します。これにより「処理結果ファイルが存在しない」ではなく「対象行が0件だった」と区別できます。

### Export-LastMonthInstallExtractFailureCsv

失敗行がある場合、失敗CSVを出力します。

出力列は固定です。

```text
FileName
AssetName
LineNumber
Reason
Timestamp
```

失敗行が0件の場合は、新しい失敗CSVを作らず、古い失敗CSVが残っていれば削除します。これにより、前回の失敗CSVを今回の失敗と誤認しないようにしています。

## 6. 戻り値の形

### InstallationCsv出力結果

```text
Path
FullName
Created
Count
Directory
```

### FailureCsv出力結果

```text
Path
FullName
Created
Count
OldFileRemoved
```

## 7. 変更時の注意

`Assert-LastMonthInstallExtractOutputPathAllowed` を外してはいけません。出力系処理は副作用が大きいため、必ず共通FileSystem serviceで安全確認します。

成功行0件時にCSVを作らない仕様へ変える場合、利用者が「正常に0件」か「ジョブが失敗して出力されなかった」かを区別できなくなります。

失敗行0件時に古い失敗CSVを残すと、前回の失敗を今回の失敗と誤認します。

## 8. 関連するテスト

- `LastMonthInstallExtract.Output.Tests.ps1`: 成功CSV、空の成功CSV、失敗CSV、古い失敗CSV削除、安全でないパスの拒否を確認する。
