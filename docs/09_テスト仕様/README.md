# テスト仕様 README

このフォルダは、`main/tests` 配下を設計書として読むための補助資料である。

テストファイルそのものはプロダクト実行時には使われない。  
しかし、このプロジェクトではテストが以下を固定している。

- SOLID / SRP / DIP をこのプロジェクトでどう適用するか
- どの層がどの層に依存してよいか
- PowerShell側operationとJavaScript側methodの対応
- CSV業務ルール
- 出力CSVの列順
- CDP / DOM / FileSystem / Logger / Browser port の差し替え可能性

## このフォルダの読み方

| ファイル | 目的 |
|---|---|
| `01_設計境界ガード.md` | Architecture系テストが何を禁止しているかを理解する |
| `02_Foundationテスト.md` | Foundation内部のconfig、context、CDP、DOM helper、filesystemの仕様を読む |
| `03_FeatureModuleテスト.md` | DeviceListExport / InstalledAppExport / ScanTargetSync / LastMonthInstallExtract / CompositeJobsの仕様を読む |
| `04_DOM_JavaScriptテスト.md` | JS DOM helperの振る舞いとPowerShell連携契約を読む |
| `05_変更時のテスト逆引き.md` | 変更対象ファイルから確認すべきテストを逆引きする |
| `06_テストファイル一覧.md` | 全テストファイルの役割を一覧で確認する |
