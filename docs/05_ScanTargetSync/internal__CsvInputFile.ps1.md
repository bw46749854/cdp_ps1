# main/modules/ScanTargetSync/internal/CsvInputFile.ps1

## 1. このファイルを一言でいうと

入力CSVファイルを実際に読み込むファイルです。ファイル存在確認、区切り文字判定、`Import-Csv` 実行を担当します。

## このファイルを変更する典型ケース

- 入力ファイルの列、文字コード、区切り文字、必須項目が変わった場合
- 入力値の正規化、検証、読み飛ばし条件が変わった場合
- Rules / Workflowへ渡す行オブジェクトの形が変わった場合


## 2. Import-VendorDeviceCsv

処理手順は次の通りです。

```text
Import-VendorDeviceCsv
  ├─ Pathが空でないか確認
  ├─ ファイルが存在するか確認
  ├─ 先頭行をUTF-8で読む
  ├─ 先頭行にタブがあればTSV扱い
  ├─ そうでなければカンマCSV扱い
  └─ Import-Csv -Delimiter ... -Encoding UTF8
```

Vendorから出るCSVは、環境によってタブ区切りになる可能性があるため、先頭行で区切り文字を判定しています。

## 3. Import-ScanTargetSyncInputCsv

`Import-VendorDeviceCsv` の別名に近い関数です。ScanTargetSync側から見ると、入力CSVの読み込み口をこの名前に統一できます。

## 4. 変更時の注意

文字コードや区切り文字の扱いを変えると、`CsvInput.ps1` の必須列チェックに影響します。読み込みに失敗した結果、列名が崩れると、後続の `Assert-ScanTargetSyncInputCsvContract` で必須列不足になります。
