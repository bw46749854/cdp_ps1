# main/config/foundation.config.sample.psd1

## この文書の位置づけ

この文書は `main/config/foundation.config.sample.psd1` の個別ファイルドキュメントです。
実運用で編集する `foundation.config.psd1` を作るためのサンプル設定の読み方を説明します。

## このファイルを変更する典型ケース

- 設定キー、既定値、環境ごとに編集する項目が変わった場合
- Jobごとの設定構造や連携Job設定が変わった場合
- sampleから実設定を作る手順や注意点が変わった場合


## このファイルの役割

`foundation.config.sample.psd1` は、実行環境ごとの差分を埋めるための雛形です。
本番実行時に直接参照される正本は `foundation.config.psd1` ですが、初期導入時はこのsampleをコピーして編集します。

```text
foundation.config.sample.psd1
  ↓ copy / rename
foundation.config.psd1
  ↓
run_job.ps1 / Foundation Config
```

## 編集時に確認する項目

| 領域 | 確認内容 |
|---|---|
| `Common.DebuggerUrl` | Chrome DevTools Protocol のdebugger endpoint |
| `Common.Logging` | ログの出力先、console/file出力、ログレベル |
| `Common.Cdp` | 接続・コマンド timeout |
| `Jobs.DeviceListExport` | エクスポートCSVの出力先、ファイル名prefix |
| `Jobs.ScanTargetSync` | 入力CSV、出力CSV、走査上限、日付判定条件 |
| `Jobs.InstalledAppExport` | temporary directory、download directory、出力CSV名 |
| `Jobs.LastMonthInstallExtract` | 入力ディレクトリ、抽出条件、出力CSV名 |
| `Jobs.WeeklyScanTargetSync` | DeviceListExport結果をScanTargetSyncへ渡す連携設定 |
| `Jobs.MonthlyInstallReport` | InstalledAppExport→LastMonthInstallExtract連携の実行rootや成果物受け渡し設定 |

## 注意点

- sampleは雛形です。実行環境固有のパス、URL、日数閾値は確認してから使います。
- Jobの `ModulePath` や `CommandName` はこのファイルではなく `foundation.jobs.psd1` 側の責務です。
- DOM JavaScript の読み込み順もこのファイルではなく job registry 側の責務です。
- sample更新時は、実際の `foundation.config.psd1` ドキュメントも更新対象にしてください。

## 詳細参照

- `docs/01_起動設定/config__foundation.config.psd1.md`
- `docs/01_起動設定/config__foundation.jobs.sample.psd1.md`
- `docs/00_最初に読む/03_JobNameとContextの関係.md`
- `docs/02_Foundation/internal__Config.ps1.md`

## 更新条件

sampleのキー構造、初期値の意味、導入時に編集すべき項目が変わった場合に更新します。
