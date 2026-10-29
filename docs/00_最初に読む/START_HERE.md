# 最初の読み方

この文書は、最初に読む量を絞るための入口です。
詳細仕様の正本ではありません。

## 1. まず読む3つ

| 順番 | 文書 | 目的 |
|---|---|---|
| 1 | `docs/00_最初に読む/01_全体像.md` | Job、Foundation、Workflow、Dependencies の大枠を知る |
| 2 | `docs/00_最初に読む/ファイル種別の役割.md` | ファイル名から責務を推測できるようにする |
| 3 | `docs/00_最初に読む/13_テストを仕様として読む.md` | テストを壊してよいか、実装を直すべきかを判断する |

`docs/00_最初に読む/00_MAINTENANCE_GUIDE.md` は詳細編です。
最初から通読する必要はありません。

## 2. 変更内容別の最短ルート

| 変更内容 | 先に読む文書 | 次に読む文書 |
|---|---|---|
| Jobの起動や `JobName` が分からない | `docs/00_最初に読む/03_JobNameとContextの関係.md` | `docs/01_起動設定/bat起動入口とJobName.md` / `docs/01_起動設定/run_job.ps1.md` |
| 設定値を変える | `docs/01_起動設定/config__foundation.config.psd1.md` | 該当Jobの個別docs |
| DeviceListExportを変える | `docs/00_最初に読む/07_DeviceListExportの読み方.md` | `docs/03_DeviceListExport/DeviceListExportの流れ.md` |
| InstalledAppExportを変える | `docs/00_最初に読む/08_InstalledAppExportの読み方.md` | `docs/04_InstalledAppExport/InstalledAppExport_業務トランザクション.md` |
| ScanTargetSyncを変える | `docs/00_最初に読む/09_ScanTargetSyncの読み方.md` | `docs/05_ScanTargetSync/ScanTargetSync_PolicyとWorkflowの分離.md` |
| LastMonthInstallExtractを変える | `docs/00_最初に読む/10_LastMonthInstallExtractの読み方.md` | `docs/06_LastMonthInstallExtract/LastMonthInstallExtract_ジョブ.md` |
| Composite Jobを変える | `docs/00_最初に読む/11_CompositeJobsの読み方.md` | `docs/07_CompositeJobs/CompositeJobs_ジョブ連携.md` |
| DOM JavaScriptを変える | `docs/00_最初に読む/12_DOM_JavaScriptの読み方.md` | `docs/08_DOM_JavaScript/DOM契約とselector診断の読み方.md` / `docs/08_DOM_JavaScript/PowerShell_DOM対応表.md` |
| テストが落ちた | `docs/00_最初に読む/13_テストを仕様として読む.md` | `docs/09_テスト仕様/05_変更時のテスト逆引き.md` |

## 3. 読むときの注意

- 横断ガイドは、読む順番や責務境界を知るために使います。
- 関数、引数、戻り値、DOM operation、設定キーの詳細は、対応する個別ファイルドキュメントを正とします。
- 設計判断で迷った場合は、`main/ARCHITECTURE.md` を正とします。
- テストが落ちた場合は、期待値だけを直す前に、どの境界を守るテストか確認します。

## 4. この文書を更新する条件

最初に読む文書、変更内容別の参照先、ドキュメントの正本関係が変わった場合に更新します。
個別関数や個別テストケースの詳細変更だけでは、この文書は更新不要です。
