# main/modules/LastMonthInstallExtract/internal/Rules.ps1

## 1. このファイルを一言でいうと

`LastMonthInstallExtract` の業務ルールを集めたファイルです。ファイル名から端末名を取り出す、必要ヘッダーを検証する、導入日を日付化する、前月範囲に入るか判定する、といった判断を行います。

## このファイルを変更する典型ケース

- 業務判定条件、抽出条件、CSVエラー条件が変わった場合
- Policy判定結果の形や分類名が変わった場合
- ルール説明文やテストで固定している境界が変わった場合


## 2. このファイルが担当する範囲

- 既定の必要ヘッダーを返す。
- 既定のファイル名パターンを返す。
- 前月の開始日・終了日を作る。
- ファイル名から端末名を抽出する。
- ヘッダーが完全一致しているか判定する。
- 導入日文字列を日付に変換する。
- 日付が対象範囲内か判定する。

## 3. このファイルが担当しない範囲

- ファイルを読むこと。
- CSVをparseすること。
- CSVを出力すること。
- ログを書くこと。

このファイルは原則として、入力値を受け取って判定結果を返すだけです。I/Oを持たないため、テストしやすいPolicy層です。

## 4. 関数ごとの説明

### Get-LastMonthInstallExtractDefaultRequiredHeaders

入力CSVに必要な既定ヘッダーを返します。

```text
アプリ名
バージョン
導入日
```

この順序も意味があります。`Test-LastMonthInstallExtractRequiredHeadersExact` は列名だけでなく順序も検証します。

### Get-LastMonthInstallExtractDefaultFileNamePattern

既定のファイル名パターンを返します。

```text
^.+_(PCXX-\d{2}-\d{3})\.csv$
```

この正規表現では、ファイル名中の `PCXX-00-000` 形式の部分を端末名として取り出します。

### Format-LastMonthInstallExtractListForLog

ヘッダー検証結果などの配列を、ログに出しやすい文字列へ整形します。

空なら `(なし)` を返します。

### New-LastMonthInstallExtractMonthlyDateRange

現在日付から前月範囲を作ります。

```text
Now = 2026-06-23
  Today          = 2026-06-23
  StartInclusive = 2026-05-01
  EndExclusive   = 2026-06-01
```

終了日は「未満」で比較するため、月末日を計算する必要がありません。

### Get-LastMonthInstallExtractAssetNameFromFileName

ファイル名がパターンに一致するか確認し、端末名を取り出します。

戻り値は次です。

```text
FileNameResult
  IsValid
  AssetName
  Reason
```

一致しない場合は例外ではなく `IsValid = false` を返します。Workflow側で失敗CSVに記録して、他のファイル処理を続けるためです。

### Test-LastMonthInstallExtractRequiredHeadersExact

入力CSVのヘッダーが、必要ヘッダーと完全一致しているか確認します。

判定対象は次です。

| 観点 | 内容 |
|---|---|
| 件数 | ヘッダー数が一致するか |
| 順序 | 同じ順番か |
| 不足 | 必要だが存在しない列があるか |
| 余分 | 期待していない列があるか |
| 重複 | 同じヘッダー名が複数あるか |

戻り値は次です。

```text
HeaderValidationResult
  IsValid
  MatchedHeaders
  MissingHeaders
  ExtraHeaders
  DuplicateHeaders
  SameOrder
```

### ConvertTo-LastMonthInstallExtractInstallDateOrNull

導入日文字列を `[datetime]` に変換します。

対応している代表形式は次です。

```text
yyyy-MM-dd
yyyy/M/d
yyyy-MM-dd HH:mm:ss
yyyy/M/d H:mm:ss
yyyy年M月d日
```

変換できない場合は例外ではなく `$null` を返します。Workflow側でその行を失敗CSVに記録するためです。

### Test-LastMonthInstallExtractDateInRange

日付が指定範囲に入るか判定します。

```text
Date >= StartInclusive
Date <  EndExclusive
```

## 5. 変更時の注意

ヘッダー検証を「列名が含まれていればOK」に緩めると、列順が変わったCSVを見逃す可能性があります。現在は安全側に倒して、完全一致だけを有効にしています。

ファイル名パターンのキャプチャ位置を変える場合は、`$Matches[1]` が端末名になることを維持してください。

日付範囲を `-le` に変えると、翌月1日が前月扱いになる可能性があります。現在の `StartInclusive` / `EndExclusive` は月境界を安全に扱うための設計です。

## 6. 関連するテスト

- `LastMonthInstallExtract.Rules.Tests.ps1`: ファイル名からの端末名抽出、ヘッダー完全一致、日付形式、前月範囲を確認する。
- `LastMonthInstallExtract.Architecture.Tests.ps1`: PolicyファイルがI/O、DOM、CDP、console、直接時刻に依存しないことを確認する。
