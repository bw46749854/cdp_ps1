# .bat 起動入口と JobName

## 1. この文書を一言でいうと

この文書は、root に置かれた `.bat` がどの `JobName` を `main\run_job.ps1` に渡すかを説明する文書です。

この文書は実行操作手順書ではありません。  
実際の起動操作、画面操作、実行前後の運用確認は、別途用意された実行操作手順書を参照してください。

---

## 2. root の起動ファイル

| 起動ファイル | 渡される `JobName` | 種別 | 実行内容 |
|---|---|---|---|
| `週次作業_スキャン対象整合.bat` | `WeeklyScanTargetSync` | Composite Job | `DeviceListExport` → `ScanTargetSync` |
| `月次作業_インストールレポート.bat` | `MonthlyInstallReport` | Composite Job | `InstalledAppExport` → `LastMonthInstallExtract` |

root の `.bat` は、現時点では単体Jobではなく Composite Job を呼びます。  
単体Jobを直接動かす場合は、`.bat` ではなく `main\run_job.ps1 -JobName <JobName>` の形で明示的に指定します。

---

## 3. `.bat` から `run_job.ps1` へ渡るもの

`.bat` が行うことは、基本的に次の1つです。

```text
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0main\run_job.ps1" -JobName "..."
```

ここで `"..."` に入る値が `JobName` です。

| `.bat` | `run_job.ps1` が受け取る値 |
|---|---|
| `週次作業_スキャン対象整合.bat` | `$JobName = 'WeeklyScanTargetSync'` |
| `月次作業_インストールレポート.bat` | `$JobName = 'MonthlyInstallReport'` |

`.bat` は `ConfigPath` や `JobRegistryPath` を指定していません。  
そのため、既定値として次が使われます。

```text
ConfigPath      → main\config\foundation.config.psd1
JobRegistryPath → main\config\foundation.jobs.psd1
```

---

## 4. なぜ `.bat` は単体Jobではなく Composite Job を呼ぶのか

週次・月次の実作業では、前段ジョブの成果物を後段ジョブが使うためです。

| Composite Job | 前段 | 後段 | 連携理由 |
|---|---|---|---|
| `WeeklyScanTargetSync` | `DeviceListExport` | `ScanTargetSync` | `DeviceListExport` が取得したデバイス一覧CSVを `ScanTargetSync` が入力として使う |
| `MonthlyInstallReport` | `InstalledAppExport` | `LastMonthInstallExtract` | `InstalledAppExport` が取得したLastMonthInstallExtract CSV群を `LastMonthInstallExtract` が解析する |

このため、`.bat` の `JobName` を `ScanTargetSync` や `LastMonthInstallExtract` に変えると、前段成果物の取得や今回実行分の隔離が行われません。

---

## 5. 成果物の主な出力先

ここでは、起動入口を読むために必要な最小限の出力先だけを示します。  
詳細な設定値は `docs/01_起動設定/config__foundation.config.psd1.md` を正とします。

| Job | 主な出力先・成果物 |
|---|---|
| `DeviceListExport` | `weekly\Downloads` 配下のデバイス一覧CSV |
| `ScanTargetSync` | `weekly\Downloads`, `scan_target_sync_error_list.csv`, `scan_target_sync_failure_list.csv` |
| `InstalledAppExport` | `monthly\Downloads`, `installed_app_export_error_list.csv` |
| `LastMonthInstallExtract` | `monthly\Downloads`, `pc_installation.csv`, `pc_installation_failure_list.csv` |
| `MonthlyInstallReport` | `monthly\runs` 配下の今回実行専用ディレクトリ |

`MonthlyInstallReport` は、毎回 `monthly\runs\yyyyMMdd_HHmmss` 形式の実行専用ディレクトリを作り、その中の `installed_app_export_downloads` を `LastMonthInstallExtract` へ渡します。  
これは、過去実行分のCSVを誤って解析しないためです。

---

## 6. 関連ファイル

| ファイル | 役割 |
|---|---|
| `main/run_job.ps1` | `JobName` を受け取り、Foundationへ渡す薄い入口 |
| `main/config/foundation.jobs.psd1` | `JobName` を `ModulePath` / `CommandName` に変換するジョブレジストリ |
| `main/config/foundation.config.psd1` | 各Jobの実行時設定を持つ設定ファイル |
| `docs/00_最初に読む/03_JobNameとContextの関係.md` | `JobName`, `JobDefinition`, `JobSettings`, `Context` の違いを説明する文書 |
| `docs/07_CompositeJobs/CompositeJobs_ジョブ連携.md` | Composite Job の責務と子Job連携を説明する文書 |

---

## 7. この文書を更新する条件

次が変わった場合に更新します。

```text
- root の .bat が増減した
- .bat が渡す JobName が変わった
- .bat が ConfigPath / JobRegistryPath を明示するようになった
- Composite Job の実行内容が変わった
- 出力先の読み方に影響する設定構造が変わった
```

操作手順の詳細だけが変わった場合、この文書ではなく実行操作手順書を更新します。
