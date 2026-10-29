# modules/DeviceListExport/internal/Download.ps1

## 1. このファイルを一言でいうと

DeviceListExportのCSVダウンロード完了待ちと、最終保存名へのリネームを担当するファイルである。

このファイルはブラウザを操作しない。
画面上のボタンもクリックしない。
クリック後にファイルシステム上へ出てくるCSVを、安全に成果物として確定する。

## このファイルを変更する典型ケース

- ダウンロード待ち、サイズ安定確認、timeout条件が変わった場合
- ダウンロード後のリネームや移動ルールが変わった場合
- ブラウザdownload directoryとの接続が変わった場合


## 2. このファイルが担当する範囲

```text
- ファイル名に使えない文字を安全な文字に置き換える
- CSVファイルが読み取り可能か確認する
- 重複しない保存先パスを作る
- 一時フォルダ内の部分ダウンロードファイルを探す
- 一時フォルダ内のCSV候補を探す
- CSV候補が1つだけか確認する
- ファイルサイズが安定したか確認する
- CSVダウンロード完了まで待つ
- CSVを最終保存先へ移動・リネームする
```

## 3. このファイルが担当しない範囲

```text
- エクスポートボタンをクリックする
- ブラウザのダウンロード先を設定する
- 出力結果オブジェクトを作る
- 画面契約を検証する
```

このファイルは、あくまでファイルシステム上の成果物を確定する層である。

## 4. ダウンロード完了判定の流れ

```text
Wait-DeviceListExportDownloadedCsv
  ├─ Resolve-DeviceListExportDownloadWaitRuntime
  ├─ Assert-DeviceListExportDownloadDirectoryExists
  ├─ deadlineを計算
  └─ timeoutまで繰り返す
      ├─ Get-DeviceListExportPartialDownloadFiles
      │   └─ .crdownload / .tmp / .download があれば待つ
      ├─ Get-DeviceListExportDownloadedCsvCandidates
      ├─ Resolve-DeviceListExportSingleDownloadedCsvCandidate
      ├─ Resolve-DeviceListExportStableDownloadedCsvCandidate
      │   ├─ サイズ確認
      │   ├─ StableSecondsだけ待つ
      │   ├─ 部分ダウンロードファイル再確認
      │   ├─ CSV候補再確認
      │   ├─ サイズ再確認
      │   └─ Test-DeviceListExportFileReady
      └─ stableならFileInfoを返す
```

## 5. なぜ単にCSVが存在するだけでは不十分か

ブラウザのCSVダウンロード中は、次のような状態が起きる。

```text
- .crdownload が存在する
- .tmp が存在する
- .download が存在する
- .csv は見えているが、まだ書き込み中
- .csv のサイズが増え続けている
- .csv を他プロセスが掴んでいて読み取り専有で開けない
```

CSVファイルが見えた瞬間にMoveすると、未完成ファイルを成果物として保存する可能性がある。
そのため、このファイルでは「存在する」ではなく「安定していて読み取り可能である」ことを確認する。

## 6. 関数呼び出しツリー

```text
Wait-DeviceListExportDownloadedCsv
  ├─ Resolve-DeviceListExportDownloadWaitRuntime
  │   ├─ New-DeviceListExportDownloadWaitRuntime
  │   └─ Get-DeviceListExportDownloadWaitRuntimeScriptBlock
  ├─ Assert-DeviceListExportDownloadDirectoryExists
  ├─ Get-DeviceListExportDownloadWaitNow
  ├─ Get-DeviceListExportPartialDownloadFiles
  ├─ Get-DeviceListExportDownloadedCsvCandidates
  ├─ Resolve-DeviceListExportSingleDownloadedCsvCandidate
  ├─ Resolve-DeviceListExportStableDownloadedCsvCandidate
  │   ├─ Invoke-DeviceListExportDownloadSleepSeconds
  │   ├─ Get-DeviceListExportPartialDownloadFiles
  │   ├─ Get-DeviceListExportDownloadedCsvCandidates
  │   ├─ Resolve-DeviceListExportSingleDownloadedCsvCandidate
  │   └─ Test-DeviceListExportFileReady
  └─ Invoke-DeviceListExportDownloadSleepMilliseconds

Rename-DeviceListExportDownloadedCsv
  ├─ Test-DeviceListExportFileReady
  ├─ ConvertTo-DeviceListExportSafeFileNamePart
  ├─ Get-DeviceListExportUniqueFilePath
  ├─ Move-Item
  └─ Get-Item
```

## 7. 関数ごとの説明

### ConvertTo-DeviceListExportSafeFileNamePart

ファイル名の一部として使う文字列を安全化する。

処理内容は次である。

```text
1. 前後の空白を削る
2. Windowsファイル名に使えない文字を '_' に置き換える
3. 半角空白、ノーブレークスペース、全角空白を '_' に置き換える
4. 空になった場合は 'UNKNOWN' を返す
```

DeviceListExportでは、主に日付文字列をファイル名に入れるために使う。

### Test-DeviceListExportFileReady

対象ファイルを読み取り専有で開けるか確認する。

読み取り専有で開けない場合、ブラウザや別プロセスがまだファイルを書き込んでいる可能性がある。
その場合はfalseを返す。

### Get-DeviceListExportUniqueFilePath

同名ファイルがすでに存在する場合、重複しないファイル名を作る。

```text
file.csv
file (1).csv
file (2).csv
...
file (999).csv
```

999まで試しても空きがなければ例外にする。

### New-DeviceListExportDownloadWaitRuntime

ダウンロード待ちで使う時刻・Sleep処理をまとめたオブジェクトを作る。

```text
Now
SleepMilliseconds
SleepSeconds
```

これを分けている理由は、テストで時間経過やSleepを偽物に差し替えられるようにするためである。

### Resolve-DeviceListExportDownloadWaitRuntime

`Runtime` が渡されなければ本番用Runtimeを作る。
渡された場合も、必要なscriptblockが揃っているか検証する。

### Get-DeviceListExportPartialDownloadFiles

一時フォルダ内の部分ダウンロードファイルを探す。

対象拡張子は次である。

```text
*.crdownload
*.tmp
*.download
```

これらが存在する間は、ダウンロード未完了とみなす。

### Get-DeviceListExportDownloadedCsvCandidates

一時フォルダ内のCSV候補を探す。

処理は次である。

```text
1. *.csv ファイルだけを取得する
2. FileNamePattern に一致するものだけ残す
3. LastWriteTimeの降順に並べる
```

### Resolve-DeviceListExportSingleDownloadedCsvCandidate

CSV候補が1つだけであることを確認する。

```text
0件 : nullを返す
1件 : 拡張子とサイズを確認して返す
2件以上 : 例外
```

複数候補を例外にする理由は、どれが今回の成果物か判断できないためである。

### Resolve-DeviceListExportStableDownloadedCsvCandidate

候補CSVが安定しているか確認する。

確認内容は次である。

```text
1. 現在のサイズを取得する
2. StableSecondsだけ待つ
3. 部分ダウンロードファイルがないことを確認する
4. CSV候補がまだ1つだけであることを確認する
5. 再度サイズを取得する
6. サイズが変わっていないことを確認する
7. 読み取り専有で開けることを確認する
```

この条件を満たしたら、ダウンロード完了済みのCSVとみなす。

### Wait-DeviceListExportDownloadedCsv

CSVダウンロード完了を待つ中心関数である。

指定されたタイムアウト秒数までループし、安定したCSVが見つかれば `System.IO.FileInfo` を返す。
タイムアウトまで見つからなければ例外を投げる。

### Rename-DeviceListExportDownloadedCsv

一時フォルダのCSVを最終保存先へ移動・リネームする。

処理は次の通り。

```text
1. 拡張子が.csvか確認する
2. 0 byteでないことを確認する
3. 読み取り可能であることを確認する
4. 保存先ディレクトリがなければ作る
5. TimestampTextを安全化する
6. FileNameTemplateにTimestampTextを埋め込む
7. 生成されたファイル名が.csvか確認する
8. ファイル名に禁止文字がないか確認する
9. 重複しない保存先パスを作る
10. Move-Itemで移動する
11. リネーム後も0 byteでないことを確認する
12. リネーム後のFileInfoを返す
```

## 8. 失敗条件

| 関数 | 失敗条件 |
|---|---|
| `Assert-DeviceListExportDownloadDirectoryExists` | 一時フォルダが存在しない |
| `Resolve-DeviceListExportSingleDownloadedCsvCandidate` | CSV候補が複数ある、拡張子がCSVでない、0 byte |
| `Resolve-DeviceListExportStableDownloadedCsvCandidate` | サイズが変わる、部分ファイルが残る、読み取り専有で開けない |
| `Wait-DeviceListExportDownloadedCsv` | タイムアウトまで安定CSVが見つからない |
| `Rename-DeviceListExportDownloadedCsv` | 出力ファイル名がCSVでない、禁止文字を含む、移動後0 byte |

## 9. PowerShell文法上のポイント

### `Get-ChildItem -LiteralPath`

`LiteralPath` は、パス中の `[` や `]` などをワイルドカードとして解釈しない。
ユーザー環境のフォルダ名に特殊文字が入っても安全に扱うために使う。

### `Where-Object`

取得したファイル一覧を条件で絞り込む。
ここでは、部分ダウンロード拡張子やファイル名パターンの判定に使う。

### `[System.IO.FileInfo]`

ファイル情報を表す.NET型である。
`FullName`、`Extension`、`Length`、`LastWriteTime` などのプロパティを持つ。

### `Move-Item`

ファイルを移動またはリネームするPowerShell cmdletである。
ここでは、一時フォルダのCSVを最終保存先へ移動する。

## 10. 変更時の注意

### 複数CSV候補を許容しない

複数候補の中から最新だけを採用すると、古いCSVを誤って成果物にする可能性がある。
一時フォルダはRunnerで空にしている前提なので、複数候補は異常として扱う。

### FileReady確認を削らない

サイズが変わっていなくても、ファイルを他プロセスが掴んでいる場合がある。
読み取り専有で開けることを確認してから移動する。

### OutputFileNameTemplateの `.csv` 契約を弱めない

最終成果物はCSVである。
テンプレートからCSV以外の名前が生成された場合は設定ミスとして止める。

### Runtime差し替え口を削らない

ダウンロード待ちは時間依存の処理である。
テストで本当に数秒待つと遅くなるため、`Runtime` によるNow/Sleep差し替えが必要である。

## 11. 本ドキュメント内容の要点

```text
- Download.ps1は画面操作後のCSV成果物確定を担当する
- CSVが存在するだけではダウンロード完了とはみなさない
- 部分ファイル、候補数、サイズ安定、読み取り可能性を確認する
- 一時フォルダのCSVを最終保存先へ移動・リネームする
- 時間依存処理はRuntimeで差し替え可能になっている
```
