# ScanTargetSync internal/Reconciliation.ps1

## この文書の位置づけ

この文書は `main/modules/ScanTargetSync/internal/Reconciliation.ps1` の個別ファイルドキュメントです。
Policy判定済みのON/OFF行を、UI同期に使える一意なendpoint単位の計画へ整える処理を説明します。

## このファイルを変更する典型ケース

- CSV行とUI行など、入力同士の突き合わせ条件が変わった場合
- 重複、欠落、不一致の扱いが変わった場合
- 後続Workflowへ渡す同期対象の形が変わった場合


## このファイルの責務

`Reconciliation.ps1` は、CSV全体としての整合性を確認します。
1行単位の業務判定は `Rules.ps1`、UI上の存在確認は `Workflow.Result.ps1` が担当します。

主な責務は次です。

```text
CSV内で同じendpointが複数行に出ていないか検出する
ON行 / OFF行を DesiredState 付きの SyncRow に変換する
SyncRowのendpoint一意性を保証する
```

## 関数ごとの役割

| 関数 | 役割 |
|---|---|
| `Get-ScanTargetSyncDuplicateEndpointErrors` | CSV内endpoint重複をCSVエラー行として返す |
| `New-ScanTargetSyncSyncRow` | ON/OFF対象行をUI同期用の行へ変換する |
| `Get-ScanTargetSyncSyncRows` | ON行とOFF行をまとめてSyncRow配列にする |
| `Assert-UniqueScanTargetSyncSyncRows` | SyncRowのendpoint重複を契約違反として検出する |

## endpoint重複を止める理由

同じendpointがCSV内に複数行存在すると、同じ画面行に対してONとOFFの両方の指示が発生する可能性があります。
この状態でDOM操作まで進むと、結果が入力CSVの行順に依存し、再現性が落ちます。

そのため、重複endpointはUI同期前にCSVデータエラーとして扱います。

## SyncRowの意味

`SyncRow` は、UI走査中にendpoint単位で参照される同期指示です。
概念上、次の情報を持ちます。

```text
Endpoint
User
Status
LastConnected
ScanStarted
ScanCompleted
DesiredState
DesiredChecked
```

`DesiredChecked` はDOM操作で直接必要になる真偽値です。
`DesiredState` はログや失敗理由で人に見せる分類です。

## ここに書かないこと

- CSVセル文字列の日付変換
- ON/OFF対象の業務判定
- UI行のdata-id検証
- DOM操作
- 結果CSVの出力

## 変更時に見るテスト

- `main/tests/ScanTargetSync.Reconciliation.Tests.ps1`
- `main/tests/ScanTargetSync.Workflow.Tests.ps1`
- `main/tests/Architecture.Tests.ps1`

## 更新条件

重複endpointの扱い、SyncRow構造、ON/OFF行からSyncRowへの変換方針が変わった場合に更新します。
