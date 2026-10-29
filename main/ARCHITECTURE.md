# AI保守向けアーキテクチャ判定基準: SRP / DIP

この文書は、AIまたは人間がリファクタリング対象を判定するときの強制規約である。
目的は、SOLID原則の全面適用ではなく、PowerShell 5.1で保守可能なブラウザ自動化コードを維持することである。

AIは、SRP / DIP のリファクタリング提案については、この文書に明記された `MUST` 違反だけを改修対象にする。
この制約は、構造改善や責務分離を目的とする改修提案に適用する。
機能バグ、セキュリティ問題、データ破損、運用障害、明示された仕様変更には適用しない。

`SHOULD`、`MAY`、理論上の改善余地、好みの問題、命名の微修正は、明示的な依頼がない限り改修しない。


## 0. ドキュメント正本ルール

このプロジェクトでは、ドキュメントを次の役割に分ける。

| 種別 | 正本性 | 更新対象 |
|---|---|---|
| `ARCHITECTURE.md` | 設計判断の正本 | SRP / DIP / Job境界 / Composite Job境界など、設計判断そのものが変わる場合 |
| 個別ファイルドキュメント | 対応source fileの保守意図・読み方・重要分岐の正本 | 対応する `.ps1` / `.psm1` / `.js` の責務、関数、入出力、重要な分岐が変わる場合 |
| 横断ガイド | 正本ではない | 読み順、責務の関係、誤解しやすい点、変更時の参照先が変わる場合 |
| テスト仕様ドキュメント | 正本ではない | テストの読み方、テスト群の分類、設計上の保護対象が変わる場合 |

横断ガイドは、詳細仕様を再掲しない。
関数一覧、引数一覧、DOM operation一覧、設定キー一覧、CSV列の完全仕様など、実装と1対1で変わる情報は個別ファイルドキュメントを正とする。
ただし、実行事実の最終確認は source と tests で行う。source / tests / docs に差異がある場合は、docs劣化か実装劣化かを判断して同期する。
横断ガイドに書いてよいのは、概要、読み順、責務境界、誤解しやすい点、変更内容別の参照先に限定する。

文書・テスト・実装が矛盾した場合は、まず意図した設計変更か、単なるドキュメント劣化かを判定する。
意図した設計変更である場合のみ、`ARCHITECTURE.md`、関連する個別ファイルドキュメント、`tests/Architecture.Tests.ps1` を同時に更新する。
テストを弱める変更は、設計意図が変わった場合に限り、理由を明記する。

---

## 1. 判定の優先順位

AIは、リファクタリング提案前に必ず次の順で判定する。

1. `vendor/**` なら改修しない
2. `tests/**` は、テスト追加・境界監視目的以外では改修しない
3. `Entry point` または `Module loader` の薄いファイルなら、SRP/DIP適用対象外にする
4. DIPの `MUST` 違反を確認する
5. SRPの `MUST` 違反を確認する
6. 明示された例外に該当するか確認する
7. どの `MUST` ルールにも該当しない場合、改修しない

AIは、ルールIDを示せない改修を提案してはならない。

---

## 2. SRPを必ず適用する場合

### SRP-MUST-01: Policyと外部I/Oが混在している

`POLICY` と、以下のいずれかが同じ関数に混在している場合、必ず分離する。

* `DOM`
* `BROWSER_CDP`
* `FILESYSTEM`
* `CONSOLE_LOG`
* `TIME_SLEEP`
* `CONFIG`

判定は `Rules.ps1`, `Reconciliation.ps1`, `Models.ps1` など、外部I/Oを持たない Policy / DataModel 系ファイルに置く。
DOM操作は `DomAdapter.ps1` または `DomOperations.ps1` に置く。
Workflowは判定結果と依存ポートをつなぐだけにする。

### SRP-MUST-02: Workflowが具体処理を実装している

`Workflow*.ps1` または `Runner.ps1` が、処理順序以外の責務を持っている場合、必ず分離する。

Workflowが持ってよい責務:

* 処理順序を決める
* 依存ポートを呼ぶ
* Policyの判定結果に従って分岐する
* 失敗時の上位方針を選ぶ
* 結果を集約する

ただし、Workflowで許される結果集約は、Policy判定の結果、UI走査結果、失敗行、成功行を処理順序としてまとめる範囲に限る。
業務判定そのものはPolicy / DataModel系ファイルへ置き、出力ファイルの具体的な書き出しは `Output.ps1` などの出力境界へ置く。

Workflowが持ってはいけない責務:

* DOMセレクタを知る
* CDP commandを送る
* CSVの細かいパース規則を持つ
* ファイルを直接作成・削除・移動する
* `Get-Date` や `Start-Sleep` を直接呼ぶ
* 出力フォーマットの詳細を持つ
* 業務判断の条件式を長く持つ

### SRP-MUST-03: 変更理由が2つ以上あり、片方が頻繁に変わる

同じファイルまたは関数に、次の変更理由が2つ以上あり、そのうち1つ以上が頻繁に変わる場合、必ず分離する。

* 画面DOMの変更
* CSV形式の変更
* 業務ルールの変更
* 出力形式の変更
* ブラウザ/CDP実装の変更
* エラー処理方針の変更
* 設定項目の変更

例:

* CSV仕様変更でDOM操作コードも触る必要がある → 分離する
* DOM仕様変更で業務ルールコードも触る必要がある → 分離する
* 出力形式変更でWorkflowの制御フローを触る必要がある → 分離する

### SRP-MUST-04: 単体テストしたいPolicyが外部依存を持っている

ブラウザ、DOM、ファイル、時刻、sleepなしでテストすべき判定ロジックが、外部依存を直接呼んでいる場合、必ず分離する。

対象例:

* チェック対象行の選択条件
* CSV行と画面行の照合
* 成功・失敗・スキップの判定
* リトライ対象の判定
* 出力レコードの構築

### SRP-MUST-05: 同じ関数内で「取得」「判断」「実行」「出力」をすべて行っている

次のうち3つ以上が同じ関数に含まれる場合、必ず分離する。

* 入力取得
* 入力検証
* 業務判断
* DOM操作
* ファイル操作
* 出力成形
* エラー分類
* 結果集約

---

## 3. SRPを適用しない例外

### SRP-EXCEPTION-01: 薄いEntry point

`*.bat`, `run_job.ps1` は、実行開始と引数受け渡しだけなら分離しない。

### SRP-EXCEPTION-02: Module loader

`*.psm1` が内部ファイル読み込みと公開関数定義だけを行う場合、SRP違反としない。

### SRP-EXCEPTION-03: Cohesive Orchestration

`Workflow*.ps1` が複数ステップを持っていても、各ステップが依存ポート呼び出しと制御フローだけで構成されている場合、分割しない。

分割しない条件:

* DOMセレクタを持たない
* CDPを直接呼ばない
* ファイルI/Oを直接呼ばない
* 業務判断の詳細条件を持たない
* 処理順序として読む方が理解しやすい

### SRP-EXCEPTION-04: Dependencies builder

`Dependencies.ps1` は依存ポートの生成・束ね上げを行う場所である。
複数の依存を組み立てること自体はSRP違反としない。

ただし、以下は違反とする。

* 業務判断を実装する
* DOMセレクタを直接管理する
* CDP commandを直接送る
* Workflow相当の実行順序を持つ

### SRP-EXCEPTION-05: Job境界を保つための類似コード

`DeviceListExport`, `InstalledAppExport`, `ScanTargetSync`, `LastMonthInstallExtract` 間の類似コードは、次の条件を満たす限り、無理に共通化しない。

* それぞれのジョブを単独で読める
* 将来の変更理由がジョブごとに異なる
* 共通化すると条件分岐が増える
* 共通化すると変更影響範囲が複数ジョブへ広がる

共通化してよいのは、複数ジョブで同じであり、今後も同じ意味を保つ安定した処理だけである。

### SRP-EXCEPTION-06: 小さな純粋ヘルパー

同一ファイル内でのみ使われる小さな純粋ヘルパーは、単独ファイルへ分離しない。

条件:

* 外部I/Oを持たない
* 副作用を持たない
* 20行以下を目安とする
* 呼び出し元と同じ変更理由を持つ

### SRP-EXCEPTION-07: PowerShell 5.1の可読性を悪化させる分割

抽象化やファイル分割によって、PowerShell 5.1での追跡性が悪化する場合、SRPを追加適用しない。

禁止例:

* 1関数1ファイルの機械的分割
* 1行ラッパー関数の大量作成
* 呼び出し階層が深くなるだけの分割
* テスト容易性も変更容易性も改善しない分割

---

## 4. DIPを必ず適用する場合

### DIP-MUST-01: Workflow / Runner が具体I/Oを直接呼んでいる

`Workflow*.ps1` または `Runner.ps1` は、以下を直接呼んではならない。

* `Invoke-WebRequest`
* `ClientWebSocket`
* `System.Net.WebSockets`
* `Send-CDPCommand`
* `Receive-CDPMessage`
* `Invoke-CDPJS`
* `Wait-CDPJS`
* `Open-CDPConnection`
* `Close-CDPConnection`
* `Set-CDPDownloadDirectory`
* `Invoke-FoundationDomHelperMethod`
* `Wait-FoundationDomHelperMethod`
* `Wait-FoundationDomHelperMethodResult`
* `Import-Csv`
* `Export-Csv`
* `Add-Content`
* `Set-Content`
* `Out-File`
* `Get-ChildItem`
* `Remove-Item`
* `New-Item`
* `Move-Item`
* `Copy-Item`
* `Write-Host`
* `Write-Warning`
* `Get-Date`
* `Start-Sleep`

これらが必要な場合、依存ポートを `Dependencies.ps1` で注入する。

### DIP-MUST-02: Feature module がConcrete CDP driverへ依存している

`modules/DeviceListExport/**`, `modules/InstalledAppExport/**`, `modules/ScanTargetSync/**`, `modules/LastMonthInstallExtract/**` は、`Foundation/internal/Cdp*.ps1` の具体関数や低レベルCDP transportへ直接依存してはならない。

Feature moduleは、Foundation moduleが公開する安定したサービス、またはFeature内のAdapterを通して利用する。

### DIP-MUST-03: DOM helper呼び出しがDomOperations以外に漏れている

Feature module内で、raw Foundation DOM helperを呼べる場所は原則として `DomOperations.ps1` のみとする。

許可:

* `modules/*/internal/DomOperations.ps1`

禁止:

* `Workflow*.ps1`
* `Runner.ps1`
* `Rules.ps1`
* `Reconciliation.ps1`
* `Output.ps1`
* `Models.ps1`

### DIP-MUST-04: テストダブル化すべき外部依存を直呼びしている

単体テストで差し替えるべき依存は、必ず依存ポート化する。

対象:

* ブラウザ操作
* DOM操作
* ファイルシステム
* CSV入出力
* ダウンロード処理
* 時刻
* sleep / wait
* ログ出力
* コンソール出力
* 設定読み込み

### DIP-MUST-05: Policyが外部依存を持っている

`Rules.ps1`, `Reconciliation.ps1`, `Models.ps1` などの Policy / DataModel 系ファイルは、外部依存を直接呼ばない。

Policy層は、原則として入力値を受け取り、判定結果またはデータ構造を返すだけにする。

### DIP-MUST-06: 上位層が下位層の例外型・戻り値詳細に依存している

WorkflowまたはPolicyが、CDPやDOM helper固有の生戻り値、例外文字列、HTTP構造に依存して分岐している場合、必ずAdapterでプロジェクト内の結果型へ変換する。

---

## 5. DIPを適用しない例外

### DIP-EXCEPTION-01: Concrete driver自身

以下は具体実装を持つことが役割なので、DIP違反としない。

* `modules/Foundation/internal/Cdp*.ps1`
* `modules/Foundation/internal/CdpBrowser.ps1`
* `modules/Foundation/internal/CdpTransport.ps1`
* `modules/Foundation/internal/CdpConnection.ps1`
* `modules/Foundation/internal/FileSystem.ps1`
* `modules/Foundation/internal/Logging.ps1`
* `modules/Foundation/internal/Config.ps1`
* `modules/Foundation/internal/DomHelper.ps1`
* `modules/Foundation/internal/DomBundle.ps1`

### DIP-EXCEPTION-02: Adapter自身

Adapterは外部依存を包む場所なので、一定の具体依存を持ってよい。

許可例:

* `DomOperations.ps1` がDOM helperを呼ぶ
* `Output.ps1` が出力ポートを呼ぶ
* `Download.ps1` がダウンロード関連ポートを呼ぶ
* `CsvInput*.ps1` がCSV読み込みポートを呼ぶ

ただし、Adapterに業務判断を入れてはならない。

### DIP-EXCEPTION-03: Entry point / Bootstrap

起動処理、モジュール読み込み、初期化、設定組み立ては、必要最小限の具体依存を持ってよい。

対象:

* `*.bat`
* `main/*.ps1`
* `Bootstrap.ps1`
* `RunContext.ps1`
* `JobRegistry.ps1`

ただし、業務判断やDOM操作を直接実装してはならない。

### DIP-EXCEPTION-04: 純粋関数

外部依存を持たない純粋関数には、DIPを適用しない。

例:

* 文字列正規化
* オブジェクト生成
* 配列変換
* 判定結果の集約
* CSV行オブジェクトから内部モデルへの変換

### DIP-EXCEPTION-05: テストコード

`tests/**` は、境界検証・テストスタブ・失敗再現のために具体実装へ触れてよい。

ただし、Production codeのDIP違反を正当化するためにテストだけを変更してはならない。

### DIP-EXCEPTION-06: 1行だけの抽象化を増やす場合

次の条件をすべて満たす場合、DIPを追加適用しない。

* 具体依存がすでに許可されたAdapterまたはConcrete driver内にある
* 差し替えテストの必要がない
* 将来の実装差し替え予定がない
* 抽象化しても呼び出し元の知識が減らない


### DIP-EXCEPTION-07: Composite Job dependency builder

`modules/CompositeJobs/CompositeJobs.psm1` の `New-CompositeFoundationDependencies` は、Composite Job 用の依存portを構築する境界である。
この関数内では、次の具体実装を scriptblock 化してよい。

* `Invoke-FoundationEntrypoint`
* `Test-Path`
* `New-Item`
* `Get-ChildItem`
* `Get-Date`

ただし、Composite Job の orchestration 本体は、これらを直接呼ばず、`Dependencies.Foundation`、`Dependencies.FileSystem`、`Dependencies.Timing` のcallback経由で使う。
Composite Job がCSVの中身を読んだり、DOM/CDP/Feature内部処理を持ったりすることは、この例外では許可しない。

---

## 6. 改修してよい条件

AIは、次をすべて満たす場合だけ改修してよい。

1. `SRP-MUST-*` または `DIP-MUST-*` の具体的なルールIDに該当する
2. 例外ルールに該当しない
3. 変更対象ファイルと理由を説明できる
4. 既存テストまたは追加テストで境界を固定できる
5. 変更後の呼び出し経路が変更前より複雑になりすぎない

AIは、次の理由だけで改修してはならない。

* SOLID的にさらに綺麗にできる
* 抽象化した方が一般的に良い
* ファイルが長い
* 関数が長い
* 似ているコードがある
* 名前を少し改善できる
* 将来使うかもしれない
* interface風の構造にできる

---

## 7. 終了条件

SRP/DIPリファクタリングは、以下をすべて満たした時点で終了する。

1. Pesterテストがすべて通る
2. JavaScript DOMテストがすべて通る
3. `tests/Architecture.Tests.ps1` が通る
4. `Workflow*.ps1` と `Runner.ps1` に具体I/O、CDP、DOM helper、時刻、sleepの直呼びがない
5. `Rules.ps1`, `Reconciliation.ps1`, `Models.ps1` などの Policy / DataModel 系ファイルに外部I/Oがない
6. raw Foundation DOM helper呼び出しはFeature moduleでは `DomOperations.ps1` に閉じている
7. 新しい改修提案が `SRP-MUST-*` または `DIP-MUST-*` のルールIDを示せない
8. Medium/Low相当の改善余地は、改修せず記録のみとする

この状態に到達した場合、AIは次のように回答しなければならない。

```text
SRP/DIPの強制適用対象はありません。
現状はこのプロジェクトの設計バランス上、許容範囲です。
追加リファクタリングは、明確な機能変更・障害・テスト不能箇所が出るまで実施しません。
```

---

## 8. AIへの判定出力フォーマット

AIは、SRP/DIPレビュー時に必ず次の形式で回答する。

```text
## 判定結果
- 結論: 改修する / 改修しない
- 理由: MUSTルールに該当する / 該当しない

## MUST違反
| ルールID | ファイル | 内容 | 改修要否 |
|---|---|---|---|

## 例外適用
| 例外ID | ファイル | 理由 |
|---|---|---|

## 改修対象外
| ファイル | 指摘内容 | 対応しない理由 |
|---|---|---|

## 実施する改修
1. ...

## 実施しない改修
1. ...
```

`MUST違反` が空の場合、AIは改修計画を作ってはならない。

---

## 9. 禁止事項

AIは次を行ってはならない。

* `MUST` ルールに該当しないリファクタリングを実施する
* 例外ルールを無視して機械的にSRP/DIPを適用する
* Job境界を壊す共通化を行う
* 1行ラッパーや過剰な抽象化を増やす
* Workflowを小さくする目的だけで分割する
* PolicyをDOMやCDPに依存させる
* Adapterに業務判断を混ぜる
* テストを弱めて設計違反を通す
* `vendor/**` を変更する

---

## 10. 変更時の原則

SRP/DIP方針を変更する場合は、次を同時に更新する。

1. この文書
2. `tests/Architecture.Tests.ps1`
3. 関連する単体テスト
4. 必要なら `docs/00_最初に読む/00_MAINTENANCE_GUIDE.md`

文書、Architecture test、実装が矛盾している場合は、まず意図した設計変更か、単なるドキュメント劣化かを判定する。
意図した設計変更である場合のみ、この文書とArchitecture testを同時に更新する。
ただし、テストを弱める場合は理由を明記する。

---

## 11. PowerShell 5.1向けSRP/DIPの非適用ルール

本プロジェクトでは、SRP/DIPをPowerShell 5.1の実益に合わせて適用する。
Java/C#風のinterface-first設計、IoC container、service locator、class階層は採用しない。

DIPは、feature-localな依存オブジェクトとScriptBlock/関数境界で実現する。
`Workflow*.ps1`、`Runner.ps1`、`RowAction.ps1` は、CDP、DOM helper、file system、clock、sleep、download、logなどの低レベル副作用に直接依存しない。
ただし、依存注入は業務フローの入口、または副作用を持つ境界に限定する。純粋な整形・判定関数へ機械的に依存オブジェクトを渡してはならない。

SRPは「1ステップ1関数」ではなく、「1つの変更理由」と「業務意味」で判定する。
`Click`、`Wait`、`Assert` は、業務上1つの操作であれば一体化してよい。
1関数1ファイル、1行ラッパーの大量作成、呼び出し階層が深くなるだけの分割は行わない。

### SRP-EXCEPTION-08: InstalledAppExport RowAction の業務トランザクション境界

`modules/InstalledAppExport/internal/RowAction.ps1` は、1台分のアプリCSV取得という業務トランザクションを表す。
対象行を開く、詳細パネルを確認する、アプリタブを開く、CSVを出力する、ダウンロードを待つ、リネームする、詳細パネルを閉じる、という順序を同じ関数または同じファイルで扱うことはSRP違反としない。

`RowAction.ps1` はDOM操作について `DomAdapter.ps1` の業務名関数を経由し、`Invoke-*DomOperation` / `Wait-*DomOperation` / `Assert-*DomOperationContract` などのFeature-local DomOperations wrapperを直接呼ばない。
これはDIP純度を上げるためではなく、InstalledAppExport RowActionという例外境界の中にさらにcleanup例外を作らず、AI保守時の判断ルールを単純に保つためである。

ただし、`RowAction.ps1` は次を持ってはならない。

* DOM selector の詳細
* raw Foundation DOM helper 呼び出し
* raw CDP 呼び出し
* raw file I/O primitive
* `Get-Date` / `Start-Sleep` の直接呼び出し
* CSV形式の細部

---

## 12. DOM helper未登録時の統一方針

`MissingHelperBehavior` は、DOM要素が見つからない時ではなく、`window.__XxxDomHelper` helper自体が未登録だった時の扱いを表す。
helper未登録は、軽微なDOM構造のゆれではなく、自動化基盤の破損、DOM bundle注入失敗、または対象ページ不整合として扱う。

統一方針は次のとおりとする。

| 操作種別 | MissingHelperBehavior | 方針 |
|---|---|---|
| page identity | `ReturnContractFailure` | helper未登録も診断可能な契約失敗として返す |
| contract validation | `ReturnContractFailure` | DOM契約失敗として構造化する |
| 業務操作 click / sync / export | `Throw` | helper未登録なら続行不能 |
| operational query / row scan | 原則 `Throw` | 0件とhelper未登録を混同しない |
| wait predicate | `ReturnValue` + `$false` | 待機中は false として扱う |
| cleanup | `ReturnValue` + 診断オブジェクト | finally中の二次例外を抑える |
| operational scroll | 原則 `Throw` | スキャン前提が崩れるため続行しない |

特に、一覧取得系で `MissingValue = @()` を返してはならない。
helper未登録と本当に0件である状態を混同するためである。

---

## 13. 機能間の同一コード方針

`DeviceListExport`、`ScanTargetSync`、`InstalledAppExport` のJob境界は維持し、共通化目的だけのファイル抽出は行わない。
ただし、本当に同じ意味を持つ処理は、各機能内で同じ構造・同じ分岐・同じ優先順位で書く。

機能名prefix、helper名、operation名、`ContractScope` などの機能固有値は違ってよい。
一方で、`DomOperations.ps1` の次の制御構造は機能間で揃える。

* `MissingHelperMessage` の付与
* `ContractScope` の伝播
* `MissingValue` の優先順位
* `Await` の優先順位
* `Description` の優先順位
* `Invoke` / `Wait` / `Assert` wrapper の責務境界

`Await` が operation の意味契約である場合は、operation registry に `Await = $true` を置く。
呼び出し側だけの都合として散在させない。

---

## 14. Composite Job の境界

`WeeklyScanTargetSync` と `MonthlyInstallReport` は、Featureではなく薄いComposite Jobである。
`modules/WeeklyScanTargetSync/` や `modules/MonthlyInstallReport/` のような個別Feature moduleは作らず、`modules/CompositeJobs/CompositeJobs.psm1` に正式なJob commandだけを置く。

Composite Jobが持つ責務は次に限定する。

* 子Jobを順番に実行する
* 子Jobの結果を検証する
* 必要なパスを次のJobへ渡す
* timestamp付きの今回実行専用ディレクトリを作る
* 連携全体の結果を返す

Composite Jobは、DOM操作、CDP操作、CSV列解析、各Feature内部処理を持たない。
成果物確認が必要な場合も、ファイル名と存在確認に限定し、CSVの中身は読まない。

`MonthlyInstallReport` は、定常作業の `InstalledAppExport → LastMonthInstallExtract` 実行単位である。
毎回 `yyyyMMdd_HHmmss` 形式の専用ディレクトリを作成し、その配下の `installed_app_export_tmp` と `installed_app_export_downloads` をInstalledAppExportへ渡す。
LastMonthInstallExtractには同じ `installed_app_export_downloads` を `TargetDirectory` overrideとして渡す。
これにより、過去実行分のCSVやブラウザの重複ファイル名付与により、LastMonthInstallExtractが古いCSVを処理することを防ぐ。

InstalledAppExport実行後、Composite Jobは今回の `installed_app_export_downloads` に `Jobs.InstalledAppExport.DownloadFilePrefix + '*.csv'` に一致するCSVが存在することを確認してからLastMonthInstallExtractを実行する。
これは成果物存在確認であり、CSV解析ではない。
対象CSVが存在しない場合は安全に停止し、LastMonthInstallExtractは実行しない。

`LastMonthInstallExtract` 単独実行は、手動確認、例外対応、再処理用である。
単独実行時の `LastMonthInstallExtract` は従来どおりconfigの `Jobs.LastMonthInstallExtract.TargetDirectory` を使う。
`LastMonthInstallExtract` は最新timestampディレクトリ探索、前回分/今回分の判断、重複ファイル判定、InstalledAppExport出力履歴の判断を行わない。

Composite Jobから子Jobを呼ぶ場合、親Contextの `ConfigPath` と `JobRegistryPath` をそのまま子Jobへ伝播する。
親と子が別のconfigまたは別のjob registryを読む状態は、同じ連携Jobの意味を壊すため許可しない。
