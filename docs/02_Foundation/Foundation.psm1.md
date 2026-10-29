# main/modules/Foundation/Foundation.psm1

## 1. このファイルを一言でいうと

このファイルは、Foundationモジュールの読み込み口です。

`internal` 配下の複数ファイルを同じモジュールスコープに読み込み、外部に公開する関数だけを `Export-ModuleMember` で指定します。

このファイルは、個別の処理ロジックを実装する場所ではありません。  
共通基盤の構成ファイルを組み立てる module loader です。

---

## このファイルを変更する典型ケース

- 公開関数、Job入口、内部ファイル読み込み順が変わった場合
- モジュール外へ公開する関数の範囲が変わった場合
- Runner / Workflow / Dependencies への接続方法が変わった場合


## 2. このファイルが担当する範囲

担当すること:

```text
- Foundation module の root path を記録する
- internal/*.ps1 を順番に dot-source する
- 存在しない internal ファイルがあれば起動時に止める
- 外部公開する関数を明示する
```

担当しないこと:

```text
- ジョブ設定を読み込む
- ジョブ定義を検証する
- ブラウザを開く
- CDPコマンドを送信する
- DOM helperを直接実行する
- Feature moduleの業務ロジックを実行する
```

---

## 3. 読み込み順

このファイルは、次の順に internal ファイルを読み込みます。

```text
Foundation.psm1
  ├─ internal\Config.ps1
  ├─ internal\JobRegistry.ps1
  ├─ internal\Logging.ps1
  ├─ internal\Errors.ps1
  ├─ internal\FileSystem.ps1
  ├─ internal\DomContract.ps1
  ├─ internal\CdpTransport.ps1
  ├─ internal\CdpSession.ps1
  ├─ internal\CdpConnection.ps1
  ├─ internal\CdpCommand.ps1
  ├─ internal\CdpBrowser.ps1
  ├─ internal\CdpRuntime.ps1
  ├─ internal\DomBundle.ps1
  ├─ internal\DomHelper.ps1
  ├─ internal\ScrollableList.ps1
  ├─ internal\RunContext.ps1
  └─ internal\Bootstrap.ps1
```

順番には意味があります。  
後から読み込まれるファイルが、前に読み込まれた関数を使うためです。

例:

```text
Bootstrap.ps1
  ├─ Import-FoundationConfig を使う      → Config.ps1 が先に必要
  ├─ Import-FoundationJobRegistry を使う → JobRegistry.ps1 が先に必要
  └─ New-FoundationRunContext を使う     → RunContext.ps1 が先に必要
```

---

## 4. dot-source の意味

このファイルでは、各 internal ファイルを次のように読み込んでいます。

```powershell
. $path
```

先頭の `.` は dot-source です。

dot-source すると、読み込まれた `.ps1` ファイル内の関数が、現在のモジュールスコープに定義されます。  
つまり、`Config.ps1` に定義された `Import-FoundationConfig` を、`Bootstrap.ps1` の `Initialize-FoundationRuntime` から呼べるようになります。

`& $path` のように実行するだけだと、関数定義が呼び出し元スコープに残らないため、この用途には合いません。

---

## 5. `$script:FoundationModuleRoot` の意味

```powershell
$script:FoundationModuleRoot = $PSScriptRoot
```

`$PSScriptRoot` は、この `Foundation.psm1` が置かれているフォルダです。

`$script:` は、モジュール内のscript scopeを表します。  
同じFoundationモジュール内の関数から参照できる共有変数として使えます。

この値は、Foundation module自身の場所を基準に何かを探す必要がある場合の基準点になります。

---

## 6. `Export-ModuleMember` の意味

`Export-ModuleMember` は、モジュール外から見える関数を指定します。

このファイルでは、多数の internal 関数を読み込んでいますが、すべてを外部公開しているわけではありません。

外部公開される主な関数:

```text
- Invoke-FoundationEntrypoint
- New-FoundationRunContext
- Close-FoundationRunContext
- Open-FoundationPage
- Open-FoundationPageMatchingIdentity
- Invoke-FoundationJavaScript
- Wait-FoundationJavaScript
- Set-FoundationDownloadDirectory
- Register-DomBundle
- Register-FoundationDomBundle
- Invoke-FoundationDomHelperMethod
- Wait-FoundationDomHelperMethod
- Wait-FoundationDomHelperMethodResult
- Assert-FoundationDomHelperContract
- Invoke-ScrollableListWorkflow
- Initialize-FoundationOutputDirectory
- Clear-DirectoryContentsSafely
- Assert-FoundationSafeDirectory
- Test-PathUnderDirectory
- Remove-FileIfExistsSafely
- Write-FoundationLog
- Write-FoundationSection
- Write-FoundationObject
- Test-FoundationFatalError
```

外部公開しない代表例:

```text
- Import-FoundationConfig
- Import-FoundationJobRegistry
- Get-FoundationJobDefinition
- Import-FoundationJobModule
- Get-FoundationJobCommand
- Send-CDPCommand
- Receive-CDPMessage
```

これにより、Feature moduleや外部スクリプトが低レベル内部関数に直接依存しにくくなります。

---

## 7. なぜ internal ファイルを全部 `.psm1` に直接書かないのか

1つの巨大な `Foundation.psm1` に全処理を書くと、次の問題が起きます。

```text
- 設定読み込み、CDP、DOM、FileSystem、Logger、Bootstrap が混ざる
- 変更箇所を探しにくい
- テスト対象の関心が分かりにくい
- 設計境界が崩れやすい
```

現在の構成では、関心ごとに internal ファイルを分けています。

```text
Config.ps1      → 設定ファイル
JobRegistry.ps1 → ジョブ定義
RunContext.ps1  → 実行時Context
Bootstrap.ps1   → 起動制御
Cdp*.ps1        → CDP通信
Dom*.ps1        → DOM helper
FileSystem.ps1  → 安全なファイル操作
Logging.ps1     → ログ出力
```

`Foundation.psm1` は、それらを束ねるだけにしています。

---

## 8. 失敗条件

| 場所 | 失敗条件 | 意味 |
|---|---|---|
| internalファイル存在確認 | 指定された internal ファイルが存在しない | Foundation moduleが壊れている |
| dot-source | internalファイルに構文エラーがある | モジュール読み込み不能 |
| Export-ModuleMember | 指定関数が定義されていない | 読み込み順または関数名が壊れている |

`Import-Module modules\Foundation\Foundation.psm1` の時点でこれらが発生します。  
つまり、`run_job.ps1` からFoundationに入る前段階で検出できます。

---

## 9. このファイルの設計境界を守るテスト

`Foundation.PublicApi.Tests.ps1` では、公開APIの一覧が固定されています。

確認されていること:

```text
- 外部公開される関数が期待された一覧と一致する
- CDP内部関数、Config内部関数、JobRegistry内部関数などが外部公開されていない
```

このため、`Export-ModuleMember` に関数を追加すると、公開API変更としてテストに影響します。

---

## 10. 変更時の注意

## internalファイルを追加する場合

次の両方を確認します。

```text
1. Foundation.psm1 の foreach 配列に追加する
2. そのファイルが依存する関数より後に置かれていないか確認する
```

例:

```text
NewFeature.ps1 が Config.ps1 の関数を使う
  → Config.ps1 より後に読み込む必要がある
```

## 公開関数を追加する場合

`Export-ModuleMember` に追加するだけでなく、次を確認します。

```text
- 本当に外部公開が必要か
- Feature moduleがその関数を直接呼ぶ設計でよいか
- Foundation.PublicApi.Tests.ps1 の期待値を更新すべきか
```

内部実装用の関数を安易に公開すると、後から名前や引数を変えにくくなります。

---

## 11. 本ドキュメント内容の要点

```text
- Foundation.psm1 は共通基盤のmodule loaderである
- internal/*.ps1 は dot-source によって同じモジュールスコープに読み込まれる
- 読み込み順は依存関係に影響する
- Export-ModuleMember が外部公開APIを決める
- internal関数は読み込まれていても、すべて外部公開されるわけではない
- このファイルに業務処理を追加してはいけない
```
