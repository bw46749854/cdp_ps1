# modules/InstalledAppExport/internal/Download.ps1

## 1. このファイルを一言でいうと

InstalledAppExportジョブでダウンロードされたCSVが、完全に保存されたことを安全に確認し、端末名つきのファイル名へリネームするファイルです。

このファイルは、画面上のCSVボタンを押しません。
CSVボタンを押した後に、ファイルシステム上でCSVが完成するまで待つことを担当します。

## このファイルを変更する典型ケース

- ダウンロード待ち、サイズ安定確認、timeout条件が変わった場合
- ダウンロード後のリネームや移動ルールが変わった場合
- ブラウザdownload directoryとの接続が変わった場合


## 2. このファイルが担当する範囲

- ファイル名に使えない文字を安全な文字へ置き換える
- ダウンロード中ファイルを判定する
- CSV候補を探す
- CSV候補が1つだけか確認する
- ファイルサイズが安定したか確認する
- ファイルが他プロセスに掴まれていないか確認する
- タイムアウトまでポーリングする
- CSVを端末名つきの最終ファイル名へ移動する

## 3. このファイルが担当しない範囲

| 担当しないこと | 担当ファイル |
|---|---|
| CSVボタンをクリックする | `DomAdapter.ps1` / `RowAction.ps1` |
| どの端末を処理するか決める | `Workflow.ps1` |
| 出力フォルダを初期化する | `Runner.ps1` |
| 失敗一覧CSVを書く | `Output.ps1` |

## 4. なぜダウンロード待ちが複雑なのか

ブラウザのダウンロードは、ボタンを押した瞬間に完成CSVが存在するとは限りません。
途中状態では、次のようなファイルが見えることがあります。

```text
*.crdownload
*.tmp
*.download
```

また、`.csv` が見えていても、まだサイズが変化中だったり、ブラウザがファイルを掴んでいたりする場合があります。

そのため、このファイルでは次を確認します。

```text
一時ダウンロードファイルがない
  ↓
CSV候補が1つだけ存在する
  ↓
一定秒数待ってもサイズが変わらない
  ↓
読み取り排他で開ける
  ↓
完成CSVと判断する
```

## 5. 主な処理の流れ

```text
Wait-InstalledAppExportDownloadedCsv
  └─ Wait-DownloadedCsv
      ├─ Resolve-DownloadWaitRuntime
      ├─ Assert-DownloadDirectoryExists
      ├─ deadlineを計算
      └─ タイムアウトまで繰り返し
          ├─ Get-PartialDownloadFiles
          ├─ Get-DownloadedCsvCandidates
          ├─ Resolve-SingleDownloadedCsvCandidate
          ├─ Resolve-StableDownloadedCsvCandidate
          │   ├─ サイズ取得
          │   ├─ StableSeconds待機
          │   ├─ 再度partial確認
          │   ├─ 再度CSV候補確認
          │   ├─ サイズ再取得
          │   └─ Test-FileReady
          └─ SleepMilliseconds
```

リネーム時は次の流れです。

```text
Rename-InstalledAppExportDownloadedCsv
  └─ Rename-DownloadedCsvWithAssetName
      ├─ DestinationDirectoryを作成
      ├─ Convert-ToSafeFileNamePart
      ├─ base名から " (1)" などを除去
      ├─ 端末名を付けた新ファイル名を作る
      ├─ Get-UniqueFilePath
      ├─ Move-Item
      └─ Get-Item
```

## 6. 関数ごとの説明

## Convert-ToSafeFileNamePart

### 何をするか

端末名などを、ファイル名に使える安全な文字列に変換します。

### 変換内容

- 前後の空白を削除する
- Windowsファイル名に使えない文字を `_` に置き換える
- 連続する空白を `_` に置き換える
- 空文字になった場合は `UNKNOWN` を返す

### なぜ必要か

端末名に `/`、`\`、`:` などが含まれると、そのままではファイル名にできません。

## Test-FileReady

### 何をするか

対象ファイルを読み取り専用かつ共有なしで開けるか確認します。

### なぜ必要か

CSVファイルが見えていても、ブラウザがまだ書き込み中の場合があります。
その状態で移動やリネームをすると失敗する可能性があります。

### 戻り値

```text
true  : ファイルを排他的に開けた
false : まだ他プロセスが掴んでいる、または開けない
```

## Get-UniqueFilePath

### 何をするか

指定パスが既に存在する場合、重複しないファイル名を生成します。

例:

```text
asset.csv
asset (1).csv
asset (2).csv
```

### 失敗条件

`(1)` から `(999)` まで試しても空きがない場合、例外を投げます。

## New-DownloadWaitRuntime

### 何をするか

ダウンロード待ちで使う時刻取得とsleep処理を持つruntimeオブジェクトを作ります。

### 戻り値

```text
DownloadWaitRuntime
  Now               : 現在時刻を返すscriptblock
  SleepMilliseconds : ミリ秒sleepするscriptblock
  SleepSeconds      : 秒sleepするscriptblock
```

### なぜ必要か

テストでは、本物の `Start-Sleep` を使うと遅くなります。
runtimeを差し替えることで、時間経過をテスト側で制御できます。

## Get-DownloadWaitRuntimeScriptBlock

### 何をするか

runtimeオブジェクトから、指定名のscriptblockを取り出して検査します。

### 失敗条件

必要なcallbackがない、またはscriptblockではない場合、例外を投げます。

## Resolve-DownloadWaitRuntime

### 何をするか

Runtimeがnullなら本番用runtimeを作り、必要なcallbackが揃っているか確認します。

### 検査対象

```text
Now
SleepMilliseconds
SleepSeconds
```

## Get-DownloadWaitNow

### 何をするか

runtimeの `Now` callbackを実行し、`datetime` として返します。

### 失敗条件

`Now` がnullを返した場合、例外を投げます。

## Invoke-DownloadWaitSleepMilliseconds / Invoke-DownloadWaitSleepSeconds

### 何をするか

runtime内のsleep callbackを呼びます。

### なぜ直接Start-Sleepしないのか

テスト時にsleepを差し替えられるようにするためです。

## Assert-DownloadDirectoryExists

### 何をするか

一時ダウンロードフォルダが存在することを確認します。

### 失敗条件

フォルダが存在しない場合、例外を投げます。

## Get-PartialDownloadFiles

### 何をするか

ダウンロード途中ファイルを取得します。

対象は次です。

```text
*.crdownload
*.tmp
*.download
```

### なぜ必要か

これらが残っている間は、ダウンロードがまだ完了していない可能性が高いためです。

## Get-DownloadedCsvCandidates

### 何をするか

指定Prefixで始まるCSVファイル候補を取得します。

```text
$Prefix*.csv
```

候補は更新日時の降順で並びます。

## Resolve-SingleDownloadedCsvCandidate

### 何をするか

CSV候補が1つだけであることを確認します。

### 挙動

| 候補数 | 結果 |
|---|---|
| 0 | `$null` を返す |
| 1 | そのFileInfoを返す |
| 2以上 | 例外を投げる |

### なぜ複数候補をエラーにするのか

一時フォルダに複数CSVがあると、どれが今回のダウンロードか判断できません。
誤ったCSVを端末名つきで保存しないため、複数候補は異常として止めます。

## Resolve-StableDownloadedCsvCandidate

### 何をするか

CSV候補が完成済みか確認します。

### 判定手順

```text
候補CSVのサイズを取得
  ↓
StableSeconds待つ
  ↓
partialファイルがないことを確認
  ↓
CSV候補を再取得
  ↓
候補が1つであることを確認
  ↓
サイズを再取得
  ↓
サイズが変わっていないことを確認
  ↓
Test-FileReadyで開けることを確認
  ↓
完成CSVとして返す
```

### 戻り値

完成と判断できれば `FileInfo`、まだなら `$null`。

## New-DownloadedCsvTimeoutMessage

### 何をするか

タイムアウト時のエラーメッセージを作ります。

メッセージには `Directory` と `Prefix` を含めます。

## Wait-DownloadedCsv

### 何をするか

CSVダウンロード完了まで待ちます。

### 入力

```text
Directory      : 一時ダウンロードフォルダ
Prefix         : 期待するCSVファイル名prefix
TimeoutSeconds : 最大待機秒数
StableSeconds  : サイズ安定確認の待機秒数
Runtime        : 時刻とsleepの差し替え用runtime
```

### 処理内容

タイムアウト時刻まで、partialファイルとCSV候補を繰り返し確認します。
完成CSVが見つかれば `FileInfo` を返します。
タイムアウトまで見つからなければ例外を投げます。

### 失敗条件

- ダウンロードフォルダが存在しない
- CSV候補が複数ある
- タイムアウトまで完成CSVが見つからない
- Runtime契約が壊れている

## Rename-DownloadedCsvWithAssetName

### 何をするか

完成CSVを、端末名つきのファイル名で最終保存先へ移動します。

### ファイル名の作り方

例:

```text
元CSV:
  app_list_20260604.csv

端末名:
  PC-001

保存後:
  app_list_20260604_PC-001.csv
```

元CSVが `app_list_20260604 (1).csv` のような名前でも、` (1)` を除いたbase名を使います。

### 副作用

- 保存先ディレクトリを作成する
- CSVを移動する
- 重複時は ` (1)` などを付ける

## Wait-InstalledAppExportDownloadedCsv

### 何をするか

InstalledAppExport用の薄いラッパーです。
内部では `Wait-DownloadedCsv` を呼びます。

### なぜ存在するか

RowAction側から、InstalledAppExport文脈の名前で呼べるようにするためです。

## Rename-InstalledAppExportDownloadedCsv

### 何をするか

InstalledAppExport用の薄いラッパーです。
内部では `Rename-DownloadedCsvWithAssetName` を呼びます。

## 7. 変更時の判断基準

- `.crdownload` の判定を削ると、未完成CSVを拾う可能性がある
- 複数CSV候補を許容すると、誤った端末へ誤ったCSVを紐づける可能性がある
- サイズ安定確認を削ると、書き込み途中のCSVを移動する可能性がある
- Runtime差し替えを削ると、ダウンロード待ちのテストが遅く不安定になる
- ファイル名安全化を削ると、端末名によって保存に失敗する

## 8. 本ドキュメント内容の要点

- CSVが見えた瞬間に完成とは限らない
- partialファイル、候補数、サイズ安定、ファイルロックを確認している
- `Runtime` はテストで時刻とsleepを差し替えるためにある
- リネーム時は端末名を安全なファイル名に変換している
