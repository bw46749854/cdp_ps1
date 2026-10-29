# main/modules/LastMonthInstallExtract/internal/DelimitedText.ps1

## 1. このファイルを一言でいうと

文字列化されたCSV/TSVを、ヘッダーと行データに変換するファイルです。引用符、エスケープされた引用符、引用符内改行、列数不一致を明示的に扱います。

## このファイルを変更する典型ケース

- 入力ファイルの列、文字コード、区切り文字、必須項目が変わった場合
- 入力値の正規化、検証、読み飛ばし条件が変わった場合
- Rules / Workflowへ渡す行オブジェクトの形が変わった場合


## 2. このファイルが担当する範囲

- 1行目から区切り文字を判定する。
- カンマ区切りCSVとタブ区切りTSVをパースする。
- quoted field を処理する。
- ヘッダーとデータ行を分ける。
- 列数不一致や重複ヘッダーを行単位の異常として返す。

## 3. このファイルが担当しない範囲

- ファイルの文字コード判定。
- 必須ヘッダーが業務上正しいかの判定。
- 導入日の判定。

## 4. 関数呼び出しツリー

```text
Import-LastMonthInstallExtractDelimitedText
  ├─ ConvertFrom-LastMonthInstallExtractDelimitedTextRecords
  │   ├─ quoted field処理
  │   ├─ delimiter処理
  │   ├─ 改行処理
  │   └─ unclosed quote検出
  ├─ ヘッダー取得
  ├─ BOM文字除去
  ├─ 重複ヘッダー検出
  └─ 行ごとのData / IsMalformed作成
```

## 5. 関数ごとの説明

### Get-LastMonthInstallExtractDelimiterFromText

テキストの1行目を見て、タブが含まれていればTSV、そうでなければCSVとして扱います。

```text
1行目に tab あり → "`t"
1行目に tab なし → ","
```

空ファイルや1行目が空の場合は例外です。

### ConvertFrom-LastMonthInstallExtractDelimitedTextRecords

CSV/TSV文字列を、レコード配列へ分解します。

扱うルールは次です。

| ルール | 内容 |
|---|---|
| `"` | 引用符の開始または終了 |
| `""` | 引用符内の `"` 1文字 |
| delimiter | 引用符外なら列区切り |
| CR / LF | 引用符外なら行区切り |
| 引用符内改行 | フィールド文字として扱う |
| 最後まで引用符が閉じない | 例外 |

戻り値の各レコードは次の形です。

```text
DelimitedRecord
  LineNumber
  Fields
```

### Import-LastMonthInstallExtractDelimitedText

レコード配列の1件目をヘッダーとして扱い、2件目以降をデータ行として扱います。

戻り値は次です。

```text
DelimitedTextResult
  Headers
  Rows
    LineNumber
    IsMalformed
    MalformedReason
    Data
```

`Data` はヘッダー名をプロパティ名にした pscustomobject です。

## 6. 異常行の扱い

列数がヘッダー数と違う行は、例外ではなく `IsMalformed = true` の行として返します。

理由は、1行だけ壊れていても他の行は抽出できる可能性があるからです。Workflow側で失敗CSVに記録し、処理を継続します。

ただし、引用符が閉じていない場合はCSV構造全体が壊れているため例外です。

## 7. PowerShell文法上のポイント

`New-Object System.Collections.ArrayList` を使っているのは、行やフィールドを順次追加するためです。通常のPowerShell配列に `+=` で追加すると、要素数が多い場合に毎回配列コピーが発生しやすくなります。

`[void]$arrayList.Add(...)` は、`Add()` の戻り値である追加位置indexを出力に混ぜないためです。

## 8. 変更時の注意

`Get-LastMonthInstallExtractDelimiterFromText` の判定を全行対象に変えると、データ行内のタブでTSV判定される可能性があります。現在はヘッダー行を基準にしています。

重複ヘッダーを許すと、同じプロパティ名に複数列を割り当てることになり、後勝ちで値が潰れる危険があります。

列数不一致を即例外に変えると、1行の異常でファイル全体が処理不能になります。現行設計では、行単位失敗として継続することに価値があります。

## 9. 関連するテスト

- `LastMonthInstallExtract.DelimitedText.Tests.ps1`: TSV判定、CSV既定判定、quoted comma、escaped quote、quoted newline、列数不一致、unclosed quoteを確認する。
