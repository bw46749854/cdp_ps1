# ScanTargetSync internal/CsvInput.ps1

## この文書の位置づけ

この文書は `main/modules/ScanTargetSync/internal/CsvInput.ps1` の個別ファイルドキュメントです。
Vendor から出力されたデバイスCSVを、ScanTargetSync のPolicy処理へ渡せる形に検証・正規化する境界を説明します。

## このファイルを変更する典型ケース

- 入力ファイルの列、文字コード、区切り文字、必須項目が変わった場合
- 入力値の正規化、検証、読み飛ばし条件が変わった場合
- Rules / Workflowへ渡す行オブジェクトの形が変わった場合


## このファイルの責務

`CsvInput.ps1` は、CSV行の入力契約と日付文字列の正規化を扱います。
ブラウザ操作、UI走査、チェックボックス操作、結果CSV出力は担当しません。

主な責務は次です。

```text
Vendor CSVの必須列を検証する
手動スキャンの日付文字列を業務判定用の日付に変換する
ScanTargetSync入力CSVの必須列を検証する
CSVデータエラー行を作る
```

## 必須列の契約

`Assert-VendorDeviceCsvContract` は、Vendor デバイスCSVに必要な列が存在するか検証します。
現行実装で必要な列は次です。

```text
ホスト名
利用者
接続状態
最終通信日時
手動スキャンの開始
手動スキャンの完了
```

`Assert-ScanTargetSyncInputCsvContract` は、ScanTargetSync処理で必要な入力CSVの契約を検証します。
CSV列の扱いを変える場合は、このファイルだけでなく `Rules.ps1` と `Workflow.CsvPlan.ps1` も確認してください。

## 日付変換の方針

Vendor CSVでは、手動スキャン日時が次のように複数形式で現れる可能性があります。

```text
2025-09-07T23:11:04+09:00
2025-09-07T14:11:04Z
2025-09-07 23:11:04
2025/9/7
2025年9月7日
-
空欄
```

このプロジェクトの業務判定では、CSVに表示された暦日を守ります。
特に offset 付き日時をUTCやPCローカル時刻へ変換して日付がずれることを避けます。

## 日付変換helperの順序

`Convert-VendorDateOnly` は、次のhelperを組み合わせて日付を返します。

| 関数 | 役割 |
|---|---|
| `Test-VendorDateTextIsMissing` | 空欄、空白、`-` を未入力として扱う |
| `Normalize-VendorDateText` | 連続空白を1つに畳み、前後空白を除去する |
| `ConvertFrom-VendorDateOffsetPreservingDisplayedDate` | ISO 8601 + offset / `Z` 形式を、表示上の暦日を保って変換する |
| `ConvertFrom-VendorKnownLocalDate` | 日本語環境で想定されるローカル日付形式を変換する |
| `Select-VendorLeadingDatePart` | 文字列先頭にある日付部分だけを取り出す |
| `ConvertFrom-VendorLeadingDatePart` | 取り出した日付部分を日付へ変換する |

変換不能な値は、後続のPolicy判定でCSVエラーとして扱えるようにします。
このファイルでUI操作や失敗CSV出力まで行わないでください。

## offset付き日時で表示日を守る理由

`2025-09-07T00:30:00+09:00` のような値をUTCへ変換すると、日付が `2025-09-06` になる可能性があります。
しかし、このJobの判定対象はVendor CSVに表示された業務上の日付です。
そのため、`DateTimeOffset` として解釈しても、UTC変換後の日付ではなく、CSVに表示された暦日を保持します。

この方針は、手動スキャンの開始・完了日によるON/OFF判定の安定性に直結します。

## CSVエラー行

`New-ScanTargetSyncCsvErrorRow` は、CSVデータ不備を出力用の行構造にします。
ここで扱うのは、入力CSVに由来するデータエラーです。
UI上にendpointが存在しない、UI側に余分なendpointがある、といったUI照合結果の失敗行は `Workflow.Result.ps1` 側で扱います。

## 他ファイルとの関係

| ファイル | 関係 |
|---|---|
| `CsvInputFile.ps1` | ファイルからCSVを読み込む。読み込まれた行の契約検証はこのファイルが担当 |
| `Rules.ps1` | 正規化されたCSV行を使い、ON/OFF対象やCSVエラーを判定する |
| `Reconciliation.ps1` | Policy判定後の同期対象行をendpoint単位で突き合わせる |
| `Workflow.CsvPlan.ps1` | CSV読み込み、Policy判定、同期Plan化の順序を管理する |
| `Output.ps1` | CSVエラー行や失敗行をファイルへ出力する |

## ここに書かないこと

`CsvInput.ps1` に次を追加してはいけません。

- ブラウザやDOM操作
- checkboxをON/OFFする判断の実行順序
- UI一覧にendpointがあるかどうかの検証
- 結果CSVファイルの書き出し
- ログ出力やファイル削除などの副作用

## 変更時に見るテスト

- `main/tests/ScanTargetSync.CsvInput.Tests.ps1`
- `main/tests/ScanTargetSync.Rules.Tests.ps1`
- `main/tests/ScanTargetSync.Workflow.Tests.ps1`
- `main/tests/Architecture.Tests.ps1`

## 更新条件

必須列、日付変換の受け入れ形式、表示日維持の方針、CSVエラー行構造が変わった場合に更新します。
単なるテストケース追加だけなら、テスト側の更新で足ります。
