# modules/InstalledAppExport/internal/Output.ps1

## 1. このファイルを一言でいうと

InstalledAppExportジョブで発生した失敗結果を、失敗一覧CSVとして出力するファイルです。

失敗が1件もない場合は、古い失敗一覧CSVを削除します。

## このファイルを変更する典型ケース

- 出力CSVの列、ファイル名、文字コード、書き出し単位が変わった場合
- 成功行・失敗行・summaryの形が変わった場合
- 出力前の安全確認や既存ファイル扱いが変わった場合


## 2. このファイルが担当する範囲

- 失敗一覧CSVの出力先ディレクトリを確認する
- 出力先が許可ディレクトリ配下であることを確認する
- 失敗件数が0件なら古いCSVを削除する
- 失敗件数がある場合はCSVとして出力する
- 出力したCSVの `FileInfo` を返す

## 3. このファイルが担当しない範囲

| 担当しないこと | 担当ファイル |
|---|---|
| 失敗結果を作る | `Models.ps1` / `Dependencies.ps1` |
| 1行分の失敗を捕まえる | `Workflow.ps1` |
| 出力先パスを決める | `Runner.ps1` |
| ディレクトリ操作の安全性そのもの | `Foundation/internal/FileSystem.ps1` |

## 4. 主な処理の流れ

```text
Export-InstalledAppExportFailureCsv
  └─ Export-InstalledAppExportFailureResultsCsv
      ├─ Split-Pathで出力ディレクトリを取得
      ├─ ディレクトリが空でないことを確認
      ├─ FileSystemService.AssertSafeDirectory
      ├─ FileSystemService.TestPathUnderDirectory
      ├─ FailureResultsを配列化
      ├─ 件数0ならRemoveFileIfExistsしてnullを返す
      ├─ 件数ありならSelect-Objectで列を限定
      ├─ Export-Csvで書き出す
      └─ Get-ItemでFileInfoを返す
```

## 5. 関数ごとの説明

## Export-InstalledAppExportFailureResultsCsv

### 何をするか

失敗結果配列を、指定パスへCSV出力します。

### 入力

```text
FailureResults    : InstalledAppExportFailure[]
Path              : 出力先CSVパス
FileSystemService : 安全なファイル操作を行う共通サービス
```

### 出力

| 状況 | 戻り値 |
|---|---|
| 失敗結果がある | 出力したCSVのFileInfo |
| 失敗結果がない | `$null` |

### CSV列

出力列は次の4つに限定されます。

```text
DataId
AssetName
Reason
Timestamp
```

`Select-Object` を通すことで、余計なプロパティが混ざってもCSV列を固定しています。

### 失敗ゼロの場合の挙動

失敗結果が0件なら、新しい空CSVを作りません。
代わりに、同じパスに古い失敗CSVがあれば削除します。

これは、前回実行時の失敗CSVが残っていて、今回も失敗したように見えることを防ぐためです。

### 安全確認

出力前に次を確認します。

```text
出力ディレクトリが空でない
  ↓
AssertSafeDirectoryで安全なディレクトリか確認
  ↓
TestPathUnderDirectoryで出力先がその配下か確認
```

### 失敗条件

- 出力ディレクトリが空
- 出力先が許可ディレクトリ配下ではない
- CSV書き出しに失敗する

## Export-InstalledAppExportFailureCsv

### 何をするか

`Export-InstalledAppExportFailureResultsCsv` への薄いラッパーです。

### なぜ存在するか

呼び出し元である `Runner.ps1` から、InstalledAppExport文脈の名前で呼べるようにしています。

## 6. PowerShell文法上のポイント

### `Split-Path -Parent`

ファイルパスから親ディレクトリを取り出します。
ここでは、出力先CSVのディレクトリを安全確認するために使います。

### `@($FailureResults)`

`FailureResults` がnull、単一要素、配列のどれであっても配列として扱うために使います。

### `Export-Csv -NoTypeInformation -Encoding UTF8`

CSV出力します。
`-NoTypeInformation` は、PowerShell型情報のヘッダーを出さないための指定です。

## 7. 変更時の判断基準

- 安全確認を削ると、想定外のパスへCSVを書き込む危険がある
- 失敗ゼロ時に古いCSVを削除しないと、前回失敗が今回も残って見える
- CSV列名を変えると、後続で失敗CSVを読む人や処理に影響する
- `Export-Csv` の文字コードを変える場合は、Excelや後続処理での読み取りを確認する

## 8. 本ドキュメント内容の要点

- `Output.ps1` は失敗一覧CSVの出力だけを担当する
- 失敗ゼロなら古いCSVを削除する
- 出力先パスはFileSystemServiceで安全確認している
- CSV列は `DataId`, `AssetName`, `Reason`, `Timestamp` に固定されている
