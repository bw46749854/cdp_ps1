# main/modules/LastMonthInstallExtract/LastMonthInstallExtract.psm1

## 1. このファイルを一言でいうと

`LastMonthInstallExtract` ジョブのモジュールを組み立てるファイルです。`internal` 配下のPowerShellファイルを同じモジュールスコープへ読み込み、外部から呼べる入口として `Invoke-LastMonthInstallExtractJob` だけを公開します。

## このファイルを変更する典型ケース

- 公開関数、Job入口、内部ファイル読み込み順が変わった場合
- モジュール外へ公開する関数の範囲が変わった場合
- Runner / Workflow / Dependencies への接続方法が変わった場合


## 2. このファイルが担当する範囲

- `Foundation.psm1` を読み込む。
- `LastMonthInstallExtract/internal/*.ps1` を決められた順番で dot-source する。
- `Invoke-LastMonthInstallExtractJob` を `Export-ModuleMember` で外部公開する。

## 3. このファイルが担当しない範囲

- CSVファイルの探索はしません。
- CSVの文字コード判定はしません。
- 導入日の判定はしません。
- 出力CSVの作成はしません。

このファイルは「処理を実行する場所」ではなく、「処理に必要な関数を同じモジュール内に配置する場所」です。

## 4. 読み込み順序

```text
LastMonthInstallExtract.psm1
  ├─ Import-Module Foundation.psm1
  ├─ dot-source internal\Models.ps1
  ├─ dot-source internal\Encoding.ps1
  ├─ dot-source internal\DelimitedText.ps1
  ├─ dot-source internal\Rules.ps1
  ├─ dot-source internal\Input.ps1
  ├─ dot-source internal\Output.ps1
  ├─ dot-source internal\Dependencies.ps1
  ├─ dot-source internal\Workflow.ps1
  ├─ dot-source internal\Runner.ps1
  └─ Export-ModuleMember Invoke-LastMonthInstallExtractJob
```

## 5. なぜこの順番なのか

`Runner.ps1` は `Workflow.ps1` を呼びます。`Workflow.ps1` は `Rules.ps1`、`Encoding.ps1`、`DelimitedText.ps1`、`Models.ps1` などの関数を呼びます。したがって、部品側のファイルを先に読み、入口側の `Runner.ps1` を最後に読む構成になっています。

PowerShellでは、dot-source した関数は同じスコープに定義されます。このため、`Workflow.ps1` 内の関数から `ConvertFrom-LastMonthInstallExtractSupportedBytes` や `New-LastMonthInstallExtractWorkflowResult` を通常の関数名で呼べます。

## 6. 変更時の注意

`Export-ModuleMember` に `Invoke-LastMonthInstallExtractJob` 以外を追加すると、internal関数が外部API化します。テスト目的なら `Import-Module` 後のモジュールスコープやテスト補助で扱うべきで、プロダクトの公開入口は増やさない方が安全です。

読み込み順序を変える場合は、`Workflow.ps1` と `Runner.ps1` が参照する関数が先に定義されるか確認してください。PowerShellは実行時に関数を解決しますが、モジュール読み込み中に即時実行される処理があると順序の影響を受けます。

## 7. 関連するテスト

- `LastMonthInstallExtract.Architecture.Tests.ps1`: LastMonthInstallExtractがDOM/CDPへ依存しないことを守る。
- `LastMonthInstallExtract.Runner.Tests.ps1`: `Invoke-LastMonthInstallExtractJob` の入口動作を確認する。
