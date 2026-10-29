# main/modules/LastMonthInstallExtract/internal/Encoding.ps1

## 1. このファイルを一言でいうと

CSVファイルのバイト列を、対応済みの文字コードとして安全に文字列へ変換するファイルです。

## このファイルを変更する典型ケース

- 入力ファイルの列、文字コード、区切り文字、必須項目が変わった場合
- 入力値の正規化、検証、読み飛ばし条件が変わった場合
- Rules / Workflowへ渡す行オブジェクトの形が変わった場合


## 2. このファイルが担当する範囲

- BOMの有無を確認する。
- UTF-8 / UTF-16 / UTF-32 の対応範囲でデコードする。
- 対応外のバイト列に対して、推定文字コードをエラーメッセージに含める。

## 3. このファイルが担当しない範囲

- CSV区切り文字の判定。
- CSVレコード分解。
- 導入日判定。
- Shift_JISを正式対応文字コードとして読むこと。

CP932 / Shift_JIS は推定には使いますが、正常デコード対象としては許可していません。

## 4. 関数呼び出しツリー

```text
ConvertFrom-LastMonthInstallExtractSupportedBytes
  ├─ Test-LastMonthInstallExtractBytesPrefix
  ├─ New-LastMonthInstallExtractDecodedTextResult
  └─ catch UTF-8 failure
      └─ Get-LastMonthInstallExtractEncodingGuessFromBytes
          ├─ Test-LastMonthInstallExtractBytesPrefix
          ├─ Register-LastMonthInstallExtractCodePagesEncodingProviderSafely
          └─ Test-LastMonthInstallExtractByteArrayEqual
```

## 5. 対応文字コード

| 条件 | EncodingName |
|---|---|
| UTF-32 LE BOM | `UTF-32 LE BOM付き` |
| UTF-32 BE BOM | `UTF-32 BE BOM付き` |
| UTF-8 BOM | `UTF-8 BOM付き` |
| UTF-16 LE BOM | `UTF-16 LE BOM付き` |
| UTF-16 BE BOM | `UTF-16 BE BOM付き` |
| UTF-8 BOMなしとして厳密デコード成功 | `UTF-8 BOMなし` |

空ファイルは例外です。

## 6. 関数ごとの説明

### Test-LastMonthInstallExtractBytesPrefix

バイト列が指定されたprefixで始まるか確認します。BOM判定で使います。

### Test-LastMonthInstallExtractByteArrayEqual

2つのバイト配列が完全一致するか確認します。CP932推定時に、デコードして再エンコードしたバイト列が元と一致するかを見るために使います。

### Register-LastMonthInstallExtractCodePagesEncodingProviderSafely

`.NET` 環境によってはCP932などのコードページを使うために provider 登録が必要です。Windows PowerShell 5.1では不要な場合があるため、失敗しても無視します。

### Get-LastMonthInstallExtractEncodingGuessFromBytes

対応外だった場合の診断用に、文字コード候補を推定します。

重要なのは、この関数の結果は「読み込み許可」ではなく「エラー説明」です。

### New-LastMonthInstallExtractDecodedTextResult

デコード済み文字列とEncodingNameを持つ結果オブジェクトを作ります。

```text
DecodedTextResult
  Text
  EncodingName
```

### ConvertFrom-LastMonthInstallExtractSupportedBytes

このファイルの主関数です。バイト列を対応文字コードとして文字列に変換します。

UTF-8 BOMなしは、例外を投げる厳密モードでデコードします。不正なUTF-8を無理に置換文字で読むことを避けるためです。

## 7. 変更時の注意

Shift_JIS / CP932 を正式対応に追加する場合は、誤判定リスクを考える必要があります。UTF-8として読めないバイト列がCP932として丸め込まれると、文字化けや列名不一致の原因が隠れる可能性があります。

UTF-8 strict を緩めると、不正バイトが置換文字になり、異常CSVを正常扱いする可能性があります。

BOMの判定順序を変える場合は、UTF-32 BOMをUTF-16 BOMより先に判定する必要があります。UTF-32 LE BOMは `FF FE 00 00` で始まるため、先にUTF-16 LE `FF FE` と判定すると誤分類します。

## 8. 関連するテスト

- `LastMonthInstallExtract.Encoding.Tests.ps1`: UTF-8、UTF-16、UTF-32、空ファイル、対応外バイト列の診断を確認する。
