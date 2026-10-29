# modules/DeviceListExport/internal/Output.ps1

## 1. このファイルを一言でいうと

DeviceListExportの実行結果オブジェクト作成と、結果サマリーのログ出力を担当するファイルである。

処理本体は持たない。
「処理が終わった後に何を結果として返すか」「ログに何を出すか」を担当する。

## このファイルを変更する典型ケース

- 出力CSVの列、ファイル名、文字コード、書き出し単位が変わった場合
- 成功行・失敗行・summaryの形が変わった場合
- 出力前の安全確認や既存ファイル扱いが変わった場合


## 2. このファイルが担当する範囲

```text
- DeviceListExportResultオブジェクトを作る
- ダウンロード元CSVパスを結果に入れる
- リネーム後CSVパスを結果に入れる
- DOM操作結果を結果に入れる
- 結果サマリーをログに出す
```

## 3. このファイルが担当しない範囲

```text
- CSVをダウンロードする
- CSVをリネームする
- DOMを操作する
- 失敗結果を作る
```

DeviceListExportは、成功時に `New-DeviceListExportResult` を呼ぶ。
途中で失敗した場合は例外で止まるため、このファイルに失敗結果オブジェクトの生成処理はない。

## 4. 関数呼び出しツリー

```text
Invoke-DeviceListExportWorkflow
  └─ New-DeviceListExportResult

Invoke-DeviceListExportJob
  └─ Write-DeviceListExportResultSummary
      ├─ Write-FoundationSection
      ├─ Write-FoundationLog ダウンロードCSV
      └─ Write-FoundationLog リネーム済みCSV
```

## 5. 関数ごとの説明

### New-DeviceListExportResult

DeviceListExport成功時の結果オブジェクトを作る。

引数は次である。

```text
DownloadedCsvPath
  一時ダウンロードフォルダで検出されたCSVのパス。

ExportedCsvPath
  最終保存先に移動・リネームされたCSVのパス。

DomResult
  エクスポートメニュークリック時のDOM操作結果。
```

戻り値の形は次である。

```text
DeviceListExportResult
  Ok                : true
  Feature           : DeviceListExport
  DownloadedCsvPath : string
  ExportedCsvPath   : string
  DomResult         : object or null
```

`Feature` を持たせている理由は、CompositeJobsやログ確認時に、どのジョブの結果か識別しやすくするためである。

### Write-DeviceListExportResultSummary

処理結果をログに出す。

出力する内容は次である。

```text
DeviceListExport 処理結果
ダウンロードCSV: <一時CSVパス>
リネーム済みCSV: <最終保存先CSVパス>
```

ここでは画面操作結果の詳細や契約チェック詳細までは出さない。
DeviceListExportの成果物として人間がまず見るべきなのは、どのCSVが出たかである。

## 6. なぜOutputを分けるのか

Workflowの最後で直接 `[pscustomobject]` を作ったり、Runnerで直接ログ出力しても動く。
しかし、結果の形や表示内容を専用ファイルに分けることで、次の変更に強くなる。

```text
- 結果オブジェクトのプロパティを追加する
- ログ出力形式を変える
- CompositeJobsから参照しやすい形にする
- 成果物パスの表示を増やす
```

Workflowは「処理順序」に集中し、Outputは「結果の形」に集中する。

## 7. PowerShell文法上のポイント

### `[pscustomobject]@{ ... }`

名前付きプロパティを持つ結果オブジェクトを作る。

PowerShellでは、関数が複数値を返すより、名前付きプロパティを持つオブジェクトを返す方が後続処理で扱いやすい。

```text
$result.ExportedCsvPath
$result.DownloadedCsvPath
```

のように読める。

### 文字列展開

ログメッセージでは、`$($Result.DownloadedCsvPath)` のように `$()` を使ってプロパティ値を文字列内へ埋め込む。

`$Result.DownloadedCsvPath` をそのままダブルクォート内に書くと、PowerShellの解釈が分かりにくくなるため、プロパティ参照は `$()` で囲むのが安全である。

## 8. 変更時の注意

### Okの意味を曖昧にしない

この結果オブジェクトは成功時だけ作られる。
そのため `Ok = $true` で固定されている。
失敗時も結果オブジェクトを返したい場合は、DeviceListExport全体の失敗ハンドリング方針を変更する必要がある。

### ExportedCsvPathを削除しない

CompositeJobsや後続処理は、最終保存先のCSVパスを必要とする可能性がある。
一時パスだけでは成果物として扱いにくい。

### ログ出力と戻り値を混同しない

ログは人間が読むもの。
戻り値は後続処理やテストが読むもの。
片方だけ増やしても、もう片方からは参照できない。

## 9. 本ドキュメント内容の要点

```text
- Output.ps1は結果の形と結果ログを担当する
- DeviceListExportResultには一時CSVパスと最終CSVパスの両方が入る
- 成功時だけNew-DeviceListExportResultが呼ばれる
- ログ出力と戻り値は別の目的を持つ
```
