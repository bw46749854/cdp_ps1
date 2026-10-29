# main/modules/LastMonthInstallExtract/internal/Input.ps1

## 1. このファイルを一言でいうと

`LastMonthInstallExtract` ジョブの入力ファイルを探し、ファイルをバイト列として読むための低レベル入力ファイルです。

## このファイルを変更する典型ケース

- 入力ファイルの列、文字コード、区切り文字、必須項目が変わった場合
- 入力値の正規化、検証、読み飛ばし条件が変わった場合
- Rules / Workflowへ渡す行オブジェクトの形が変わった場合


## 2. このファイルが担当する範囲

- 対象ディレクトリ内の `.csv` ファイルを列挙する。
- 生成済みの出力CSVと失敗CSVを入力対象から除外する。
- ファイル内容を `[byte[]]` として読み込む。

## 3. このファイルが担当しない範囲

- CSVの文字コード判定。
- CSVの解析。
- ファイル名から端末名を取り出す処理。
- 導入日判定。

## 4. 関数ごとの説明

### Get-LastMonthInstallExtractTargetCsvFileInfos

対象ディレクトリから `.csv` ファイルを列挙します。

ただし、次のファイルは入力対象から除外します。

```text
OutputCsvFileName
FailureCsvFileName
```

理由は、同じディレクトリに結果CSVを出力するためです。除外しないと、前回または今回の出力CSVを再び入力CSVとして処理してしまいます。

戻り値は次の形です。

```text
FileInfoLike
  Name
  FullName
```

本物の `System.IO.FileInfo` をそのまま返さず、必要な情報だけに絞った pscustomobject にしています。Workflowは `Name` と `FullName` だけ知っていれば十分です。

### Read-LastMonthInstallExtractFileBytes

指定されたパスを `[System.IO.File]::ReadAllBytes()` で読み込みます。

文字列として読まない理由は、文字コード判定を `Encoding.ps1` で行うためです。最初から文字列として読んでしまうと、PowerShell側の既定エンコーディングに影響される可能性があります。

## 5. 変更時の注意

`Get-ChildItem` の `-Filter '*.csv'` を外すと、CSV以外のファイルまで処理対象になります。

出力CSVの除外を削ると、結果CSVを入力CSVとして再処理する危険があります。特に `OutputCsvFileName` は必ず除外する必要があります。

`Read-LastMonthInstallExtractFileBytes` を `Get-Content` に変えると、文字コード判定の責務が壊れます。このファイルはあくまでバイト列を返すだけにしてください。

## 6. 関連するテスト

- `LastMonthInstallExtract.Input.Tests.ps1`: CSV列挙、出力ファイル除外、対象ディレクトリ不存在時の例外を確認する。
